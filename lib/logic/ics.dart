import '../data/models.dart';

String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// Zawija linie powyżej 75 znaków (wymóg formatu iCalendar).
String _fold(String line) {
  if (line.length <= 74) return line;
  final b = StringBuffer();
  var i = 0;
  while (i < line.length) {
    final end = (i + (i == 0 ? 74 : 73)).clamp(0, line.length);
    if (i > 0) b.write('\r\n ');
    b.write(line.substring(i, end));
    i = end;
  }
  return b.toString();
}

/// Kalendarz z corocznymi rocznicami śmierci i urodzin (całodniowe, z przypomnieniem dzień wcześniej)
/// oraz Wszystkich Świętych – do zaimportowania w Kalendarzu Google / Apple.
/// [whereOf] – opis miejsca (cmentarz) dla osoby.
String buildIcs(List<Person> people, {String Function(Person)? whereOf, bool allSaints = true, DateTime? now}) {
  final stamp = now ?? DateTime.now().toUtc();
  final st = '${_d(stamp)}T${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}00Z';
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Znicz//Rocznice//PL',
    'CALSCALE:GREGORIAN',
    'X-WR-CALNAME:Znicz – rocznice',
  ];
  void event(String uid, DateTime start, String title, String? where, String desc) {
    final end = start.add(const Duration(days: 1));
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:$uid@znicz',
      'DTSTAMP:$st',
      'DTSTART;VALUE=DATE:${_d(start)}',
      'DTEND;VALUE=DATE:${_d(end)}',
      // 29 lutego → w latach nieprzestępnych kalendarze pomijają; użytkownik dostaje to, co zapisał
      'RRULE:FREQ=YEARLY',
      'SUMMARY:${_esc(title)}',
      if ((where ?? '').isNotEmpty) 'LOCATION:${_esc(where!)}',
      if (desc.isNotEmpty) 'DESCRIPTION:${_esc(desc)}',
      'TRANSP:TRANSPARENT',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${_esc(title)}',
      'TRIGGER:-PT15H',
      'END:VALARM',
      'END:VEVENT',
    ]);
  }

  for (final p in people) {
    final where = whereOf?.call(p);
    if (p.death != null && p.death!.isFull) {
      event('d-${p.uid}', p.death!.toDateTime(), 'Rocznica śmierci – ${p.fullName}', where,
          'Zmarł(a) ${p.death!.format()}${p.relation != null ? ' · ${p.relation}' : ''}');
    }
    if (p.birth != null && p.birth!.isFull) {
      event('b-${p.uid}', p.birth!.toDateTime(), 'Rocznica urodzin – ${p.fullName}', where,
          'Urodził(a) się ${p.birth!.format()}${p.relation != null ? ' · ${p.relation}' : ''}');
    }
  }
  if (allSaints) {
    final y = (now ?? DateTime.now()).year;
    event('wszystkich-swietych', DateTime(y, 11, 1), 'Wszystkich Świętych', null, 'Lista grobów do odwiedzenia – aplikacja Znicz');
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
