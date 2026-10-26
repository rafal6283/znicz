import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/db.dart';

/// Ustawienia przypomnień (zapisywane w SharedPreferences).
class ReminderSettings {
  bool enabled;
  int hour; // godzina powiadomienia
  int daysBefore; // ile dni wcześniej przypomnieć o rocznicy (0 = w dniu)
  bool allSaints; // przypomnienie przed 1 listopada
  int allSaintsDaysBefore;

  ReminderSettings({this.enabled = true, this.hour = 9, this.daysBefore = 1, this.allSaints = true, this.allSaintsDaysBefore = 7});

  static Future<ReminderSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ReminderSettings(
      enabled: p.getBool('rem_enabled') ?? true,
      hour: p.getInt('rem_hour') ?? 9,
      daysBefore: p.getInt('rem_days') ?? 1,
      allSaints: p.getBool('rem_all_saints') ?? true,
      allSaintsDaysBefore: p.getInt('rem_all_saints_days') ?? 7,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('rem_enabled', enabled);
    await p.setInt('rem_hour', hour);
    await p.setInt('rem_days', daysBefore);
    await p.setBool('rem_all_saints', allSaints);
    await p.setInt('rem_all_saints_days', allSaintsDaysBefore);
  }
}

class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationDetails(
    'rocznice',
    'Rocznice i przypomnienia',
    channelDescription: 'Rocznice śmierci i urodzin bliskich, Wszystkich Świętych, opłaty za groby',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const _details = NotificationDetails(android: _channel, iOS: DarwinNotificationDetails());

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      String name = 'Europe/Warsaw';
      try {
        name = await FlutterTimezone.getLocalTimezone();
      } catch (_) {}
      try {
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
      }
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('Powiadomienia niedostępne: $e');
    }
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    return false;
  }

  /// Przelicza wszystkie przypomnienia od nowa (po każdej zmianie danych).
  static Future<int> reschedule() async {
    await init();
    if (!_ready) return 0;
    try {
      await _plugin.cancelAll();
      final s = await ReminderSettings.load();
      if (!s.enabled) return 0;
      final people = await AppDb.I.allPeople();
      final graves = {for (final g in (await AppDb.I.graveViews())) g.grave.id!: g};
      var id = 1;
      var count = 0;

      Future<void> yearly(int month, int day, String title, String body) async {
        // przypomnienie N dni wcześniej, powtarzane co roku
        final d = DateTime(2001, month, day).subtract(Duration(days: s.daysBefore));
        final now = tz.TZDateTime.now(tz.local);
        var when = tz.TZDateTime(tz.local, now.year, d.month, d.day, s.hour);
        if (when.isBefore(now)) when = tz.TZDateTime(tz.local, now.year + 1, d.month, d.day, s.hour);
        await _plugin.zonedSchedule(id++, title, body, when, _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.dateAndTime);
        count++;
      }

      String when0(String what) => s.daysBefore == 0 ? 'Dziś $what' : (s.daysBefore == 1 ? 'Jutro $what' : 'Za ${s.daysBefore} dni $what');

      for (final p in people) {
        final gv = graves[p.graveId];
        final where = gv?.cemetery?.label ?? '';
        if (p.remindDeath && p.death != null && p.death!.isFull) {
          await yearly(p.death!.month!, p.death!.day!, when0('rocznica śmierci'), '${p.fullName}${where.isEmpty ? '' : ' · $where'}');
        }
        if (p.remindBirth && p.birth != null && p.birth!.isFull) {
          await yearly(p.birth!.month!, p.birth!.day!, when0('rocznica urodzin'), '${p.fullName}${where.isEmpty ? '' : ' · $where'}');
        }
        if (id > (Platform.isIOS ? 55 : 400)) break; // iOS pozwala na 64 zaplanowane powiadomienia
      }

      if (s.allSaints && graves.isNotEmpty) {
        final d = DateTime(2001, 11, 1).subtract(Duration(days: s.allSaintsDaysBefore));
        final now = tz.TZDateTime.now(tz.local);
        var when = tz.TZDateTime(tz.local, now.year, d.month, d.day, s.hour);
        if (when.isBefore(now)) when = tz.TZDateTime(tz.local, now.year + 1, d.month, d.day, s.hour);
        final n = graves.values.where((g) => g.grave.allSaints).length;
        await _plugin.zonedSchedule(id++, 'Wszystkich Świętych za ${s.allSaintsDaysBefore} dni', 'Groby do odwiedzenia: $n. Otwórz listę i zaplanuj trasę.', when, _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, matchDateTimeComponents: DateTimeComponents.dateAndTime);
        count++;
      }

      // opłaty za groby – jednorazowo 60 dni przed końcem
      for (final gv in graves.values) {
        final f = gv.grave.feePaidUntil;
        if (f == null) continue;
        final end = DateTime(f.year, f.month ?? 12, f.day ?? 28);
        final remind = end.subtract(const Duration(days: 60));
        final when = tz.TZDateTime(tz.local, remind.year, remind.month, remind.day, s.hour);
        if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;
        await _plugin.zonedSchedule(id++, 'Za 2 miesiące kończy się opłata za grób', '${gv.title} · opłacony do ${f.format()}', when, _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('Planowanie przypomnień nie powiodło się: $e');
      return 0;
    }
  }

  static Future<void> test() async {
    await init();
    await _plugin.show(9999, 'Znicz', 'Tak będą wyglądały przypomnienia o rocznicach.', _details);
  }
}
