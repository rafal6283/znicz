import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/geo.dart';

/// Pobyt zapisany przez aplikację Doba (automatyczny dziennik miejsc).
class DobaStay {
  final int start;
  final int end;
  final double lat;
  final double lng;
  final String? place;
  DobaStay(this.start, this.end, this.lat, this.lng, this.place);
  Duration get length => Duration(milliseconds: end - start);
}

/// Propozycja: pobyt na cmentarzu, przy którym są Twoje groby bez wpisanej wizyty tego dnia.
class DobaVisitProposal {
  final DobaStay stay;
  final Cemetery? cemetery;
  final List<GraveView> graves;
  DobaVisitProposal(this.stay, this.cemetery, this.graves);
  String get key => '${stay.start}';
}

/// Most do Doby: Doba wie, kiedy byłeś na cmentarzu — Znicz wie, gdzie leżą bliscy.
class DobaBridge {
  static const _ch = MethodChannel('znicz/doba');
  static const _dismissedKey = 'doba_dismissed';
  static const _enabledKey = 'doba_enabled';

  static Future<({bool installed, bool granted})> status() async {
    if (!Platform.isAndroid) return (installed: false, granted: false);
    try {
      final m = await _ch.invokeMapMethod<String, Object?>('status') ?? {};
      return (installed: m['installed'] == true, granted: m['granted'] == true);
    } catch (_) {
      return (installed: false, granted: false);
    }
  }

  static Future<bool> request() async {
    try {
      final ok = await _ch.invokeMethod<bool>('request') ?? false;
      if (ok) await setEnabled(true);
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;
  static Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_enabledKey, v);

  static Future<List<DobaStay>> stays(DateTime from, DateTime to) async {
    try {
      final l = await _ch.invokeListMethod<Map>('stays', {'from': from.millisecondsSinceEpoch, 'to': to.millisecondsSinceEpoch}) ?? [];
      return [
        for (final m in l)
          DobaStay((m['start'] as num).toInt(), (m['end'] as num).toInt(), (m['lat'] as num).toDouble(), (m['lng'] as num).toDouble(),
              m['place'] as String?)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<Set<String>> _dismissed() async =>
      ((await SharedPreferences.getInstance()).getStringList(_dismissedKey) ?? const []).toSet();

  static Future<void> dismiss(DobaVisitProposal p) async {
    final sp = await SharedPreferences.getInstance();
    final s = (sp.getStringList(_dismissedKey) ?? <String>[]).toList()..add(p.key);
    // Pamiętamy tylko ostatnie 300 decyzji.
    await sp.setStringList(_dismissedKey, s.length > 300 ? s.sublist(s.length - 300) : s);
  }

  /// Czy pobyt był na tym cmentarzu (obrys, okolica punktu cmentarza albo blisko grobu).
  static bool _onCemetery(DobaStay s, Cemetery? c, List<GraveView> graves) {
    if (c != null && c.outline.length >= 3 && pointInPolygon(s.lat, s.lng, c.outline)) return true;
    if (c?.lat != null && c?.lng != null && distanceM(s.lat, s.lng, c!.lat!, c.lng!) <= 250) return true;
    for (final g in graves) {
      final la = g.grave.lat, ln = g.grave.lng;
      if (la != null && ln != null && distanceM(s.lat, s.lng, la, ln) <= 150) return true;
    }
    return false;
  }

  /// Propozycje wizyt z ostatnich [days] dni.
  static Future<List<DobaVisitProposal>> proposals({int days = 90}) async {
    if (!await enabled()) return [];
    final st = await status();
    if (!st.granted) return [];
    final now = DateTime.now();
    final from = now.subtract(Duration(days: days));
    final list = (await stays(from, now)).where((s) => s.length >= const Duration(minutes: 5)).toList();
    if (list.isEmpty) return [];
    final views = await AppDb.I.graveViews();
    final byCem = <int?, List<GraveView>>{};
    for (final g in views) {
      byCem.putIfAbsent(g.grave.cemeteryId, () => []).add(g);
    }
    final visits = await AppDb.I.visitsBetween(from, now.add(const Duration(days: 1)));
    final visitedDays = {for (final v in visits) '${v.graveId}:${_day(v.date)}'};
    final dismissed = await _dismissed();
    final out = <DobaVisitProposal>[];
    for (final s in list) {
      if (dismissed.contains('${s.start}')) continue;
      for (final e in byCem.entries) {
        final cem = e.value.first.cemetery;
        if (!_onCemetery(s, cem, e.value)) continue;
        final todo = e.value.where((g) => !visitedDays.contains('${g.grave.id}:${_day(s.start)}')).toList();
        if (todo.isNotEmpty) out.add(DobaVisitProposal(s, cem, todo));
        break;
      }
    }
    out.sort((a, b) => b.stay.start.compareTo(a.stay.start));
    return out;
  }

  static String _day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month}-${d.day}';
  }

  /// Zapisuje wizyty przy zaznaczonych grobach.
  static Future<void> accept(DobaVisitProposal p, Set<int> graveIds, Set<String> actions) async {
    final mins = p.stay.length.inMinutes;
    for (final id in graveIds) {
      await AppDb.I.saveVisit(Visit(graveId: id, date: p.stay.start, actions: {...actions}, note: 'Z Doby · $mins min na cmentarzu'));
    }
    await dismiss(p);
  }
}
