import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../data/models.dart';
import '../logic/geo.dart';
import 'osm.dart';

/// Wbudowany katalog cmentarzy z okolicy (z OpenStreetMap, pobrany przy budowaniu aplikacji).
/// Działa bez internetu.
class CemeteryCatalog {
  static List<OsmCemetery>? _items;
  static String generated = '';
  static double radiusKm = 0;

  static Future<List<OsmCemetery>> load() async {
    if (_items != null) return _items!;
    try {
      _items = parse(await rootBundle.loadString('assets/cmentarze_okolica.json'));
    } catch (_) {
      _items = const [];
    }
    return _items!;
  }

  /// Dostępne od razu, gdy katalog był już wczytany (inaczej pusta lista).
  static List<OsmCemetery> get cached => _items ?? const [];

  static List<OsmCemetery> parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['format'] != 'znicz-katalog-cmentarzy') return const [];
    generated = j['generated'] as String? ?? '';
    radiusKm = (j['radius_km'] as num?)?.toDouble() ?? 0;
    return [
      for (final m in (j['items'] as List))
        OsmCemetery(
          m['id'] as String,
          {for (final e in (m['tags'] as Map).entries) '${e.key}': '${e.value}'},
          [for (final p in (m['o'] as List? ?? const [])) ((p[0] as num).toDouble(), (p[1] as num).toDouble())],
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
        ),
    ];
  }

  static List<OsmCemetery> inBox(double s, double w, double n, double e, double refLat, double refLng) {
    final out = <OsmCemetery>[];
    for (final c in cached) {
      final inside = c.lat >= s && c.lat <= n && c.lng >= w && c.lng <= e;
      final touches = c.outline.any((p) => p.$1 >= s && p.$1 <= n && p.$2 >= w && p.$2 <= e);
      if (!inside && !touches) continue;
      out.add(c.copyWithDistance(distanceToArea(refLat, refLng, c.outline, c.lat, c.lng)));
    }
    out.sort((a, b) => a.distance.compareTo(b.distance));
    return out;
  }

  /// Cmentarz z katalogu w danym punkcie (w obrysie albo do 80 m od punktu bez obrysu).
  static OsmCemetery? at(double lat, double lng) {
    for (final c in cached) {
      if (c.outline.length >= 3) {
        if (pointInPolygon(lat, lng, c.outline)) return c;
      } else if (distanceM(lat, lng, c.lat, c.lng) < 80) {
        return c;
      }
    }
    return null;
  }

  /// Wyszukiwanie po nazwie i miejscowości (bez polskich znaków), posortowane wg odległości od [refLat]/[refLng].
  static List<OsmCemetery> search(String q, double refLat, double refLng) {
    final words = _fold(q).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <OsmCemetery>[];
    for (final c in cached) {
      final hay = _fold('${c.label} ${c.town ?? ''} ${c.kind ?? ''} ${c.tags['official_name'] ?? ''}');
      if (words.every(hay.contains)) out.add(c.copyWithDistance(distanceToArea(refLat, refLng, c.outline, c.lat, c.lng)));
    }
    out.sort((a, b) => a.distance.compareTo(b.distance));
    return out;
  }

  static String _fold(String s) {
    const from = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
    const to = 'acelnoszzACELNOSZZ';
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString().toLowerCase();
  }
}

/// Szkic cmentarza do zapisania w aplikacji na podstawie danych z mapy.
Cemetery cemeteryDraftFrom(OsmCemetery o) {
  final street = [o.tags['addr:street'], o.tags['addr:housenumber']].whereType<String>().join(' ').trim();
  return Cemetery(
    name: o.name ?? '',
    town: o.town,
    kind: o.kind,
    lat: o.lat,
    lng: o.lng,
    osmId: o.osmId,
    outline: o.outline,
    address: street.isEmpty ? null : street,
    phone: o.tags['phone'] ?? o.tags['contact:phone'],
    hours: o.tags['opening_hours'],
    searchUrl: o.tags['website'] ?? o.tags['contact:website'],
  );
}
