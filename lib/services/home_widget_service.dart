import 'dart:async';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../data/db.dart';
import '../logic/anniversaries.dart';

/// Teksty widżetu: tytuł, najbliższa rocznica, kiedy, postęp na 1 listopada.
(String, String, String, String) widgetTexts({
  required List<UpcomingEvent> events,
  required int allSaintsTotal,
  required int allSaintsDone,
  required DateTime today,
}) {
  final next = events.where((e) => e.daysFrom(today) >= 0).toList();
  String line1 = 'Brak nadchodzących rocznic', line2 = '';
  if (next.isNotEmpty) {
    final e = next.first;
    final d = e.daysFrom(today);
    line1 = e.title;
    line2 = d == 0 ? 'dziś' : (d == 1 ? 'jutro' : 'za $d dni · ${e.date.day}.${e.date.month.toString().padLeft(2, '0')}');
  }
  final as = DateTime(today.month == 11 && today.day > 2 || today.month == 12 ? today.year + 1 : today.year, 11, 1);
  final days = as.difference(DateTime(today.year, today.month, today.day)).inDays;
  final line3 = allSaintsTotal == 0
      ? ''
      : (days <= 21 ? 'Wszystkich Świętych: odwiedzone $allSaintsDone z $allSaintsTotal' : 'Do Wszystkich Świętych: $days dni · $allSaintsTotal grobów');
  return ('Znicz – pamięć', line1, line2, line3);
}

/// Odświeża widżet na ekranie głównym (Android).
class HomeWidgetService {
  static Timer? _debounce;

  static void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), update);
  }

  static Future<void> update() async {
    if (!Platform.isAndroid) return;
    try {
      final now = DateTime.now();
      final views = await AppDb.I.graveViews();
      final people = await AppDb.I.allPeople();
      final events = upcomingEvents(people, views.map((v) => v.grave).toList(), now, days: 400)
          .where((e) => e.kind == EventKind.death || e.kind == EventKind.birth)
          .toList();
      final (from, to) = allSaintsWindow(now);
      final visited = (await AppDb.I.visitsBetween(from, to)).map((v) => v.graveId).toSet();
      final list = views.where((v) => v.grave.allSaints).toList();
      final (t, l1, l2, l3) = widgetTexts(
        events: events,
        allSaintsTotal: list.length,
        allSaintsDone: list.where((v) => visited.contains(v.grave.id)).length,
        today: now,
      );
      await HomeWidget.saveWidgetData<String>('w_title', t);
      await HomeWidget.saveWidgetData<String>('w_line1', l1);
      await HomeWidget.saveWidgetData<String>('w_line2', l2);
      await HomeWidget.saveWidgetData<String>('w_line3', l3);
      await HomeWidget.updateWidget(qualifiedAndroidName: 'pl.znicz.znicz.ZniczWidget');
    } catch (_) {}
  }
}
