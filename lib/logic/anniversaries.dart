import '../data/models.dart';

enum EventKind { death, birth, fee, allSaints }

class UpcomingEvent {
  final EventKind kind;
  final DateTime date; // najbliższe wystąpienie (bez godziny)
  final Person? person;
  final int graveId;
  final int? years; // która rocznica / które urodziny
  UpcomingEvent(this.kind, this.date, this.graveId, {this.person, this.years});

  int daysFrom(DateTime today) => DateTime(date.year, date.month, date.day).difference(DateTime(today.year, today.month, today.day)).inDays;

  String get title {
    switch (kind) {
      case EventKind.death:
        return '${years}. rocznica śmierci – ${person!.fullName}';
      case EventKind.birth:
        return '${years}. rocznica urodzin – ${person!.fullName}';
      case EventKind.fee:
        return 'Kończy się opłata za grób';
      case EventKind.allSaints:
        return 'Wszystkich Świętych';
    }
  }
}

/// Następne wystąpienie dnia i miesiąca od [today] (29 lutego → 28 lutego w latach nieprzestępnych).
DateTime nextOccurrence(int month, int day, DateTime today) {
  DateTime make(int y) {
    final dim = DateTime(y, month + 1, 0).day;
    return DateTime(y, month, day > dim ? dim : day);
  }

  final t = DateTime(today.year, today.month, today.day);
  final thisYear = make(t.year);
  return thisYear.isBefore(t) ? make(t.year + 1) : thisYear;
}

List<UpcomingEvent> upcomingEvents(List<Person> people, List<Grave> graves, DateTime today, {int days = 366}) {
  final out = <UpcomingEvent>[];
  final limit = DateTime(today.year, today.month, today.day).add(Duration(days: days));
  for (final p in people) {
    final d = p.death;
    if (d != null && d.isFull) {
      final n = nextOccurrence(d.month!, d.day!, today);
      if (!n.isAfter(limit) && n.year > d.year) out.add(UpcomingEvent(EventKind.death, n, p.graveId, person: p, years: n.year - d.year));
    }
    final b = p.birth;
    if (b != null && b.isFull) {
      final n = nextOccurrence(b.month!, b.day!, today);
      if (!n.isAfter(limit) && n.year > b.year) out.add(UpcomingEvent(EventKind.birth, n, p.graveId, person: p, years: n.year - b.year));
    }
  }
  for (final g in graves) {
    final f = g.feePaidUntil;
    if (f == null) continue;
    final end = DateTime(f.year, f.month ?? 12, f.day ?? DateTime(f.year, (f.month ?? 12) + 1, 0).day);
    final t = DateTime(today.year, today.month, today.day);
    if (!end.isAfter(limit) && end.isAfter(t.subtract(const Duration(days: 365)))) {
      out.add(UpcomingEvent(EventKind.fee, end, g.id!));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Okres „Wszystkich Świętych” dla odhaczania wizyt: od 15 października do 2 listopada.
(DateTime, DateTime) allSaintsWindow(DateTime today) {
  // po 2 listopada pokazujemy jeszcze tegoroczny sezon do końca listopada, potem następny
  final y = today.month == 12 ? today.year + 1 : today.year;
  return (DateTime(y, 10, 15), DateTime(y, 11, 3));
}
