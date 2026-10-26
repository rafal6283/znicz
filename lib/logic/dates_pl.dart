import '../data/models.dart';

/// Zamienia polskie znaki na łacińskie 1:1 (indeksy znaków się nie zmieniają) i zmniejsza litery.
String fold(String s) {
  const from = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
  const to = 'acelnoszzACELNOSZZ';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString().toLowerCase();
}

/// Rdzenie nazw miesięcy (po usunięciu polskich znaków) – pasują do mianownika i dopełniacza.
const _monthStems = <String, int>{
  'styczn': 1, 'styczen': 1,
  'lut': 2,
  'marz': 3, 'marc': 3,
  'kwiet': 4, 'kwiecien': 4,
  'maj': 5,
  'czerw': 6,
  'lip': 7,
  'sierp': 8,
  'wrzes': 9,
  'pazdziern': 10,
  'listopad': 11,
  'grud': 12,
};

int? monthFromWord(String w) {
  final f = fold(w).replaceAll('.', '');
  if (f.length < 3) return null;
  final roman = PartialDate.monthFromToken(w.toUpperCase().replaceAll('.', ''));
  if (roman != null && RegExp(r'^[ivxIVX]+$').hasMatch(w.replaceAll('.', ''))) return roman;
  // „maj” musi być dokładnie maj/maja/maju, żeby nie łapać innych słów
  if (f == 'maj' || f == 'maja' || f == 'maju') return 5;
  // „lut” – luty/lutego/lutym
  if (RegExp(r'^lut(y|ego|ym|ow)?$').hasMatch(f)) return 2;
  if (RegExp(r'^lip(iec|ca|cu)$').hasMatch(f)) return 7;
  for (final e in _monthStems.entries) {
    if (e.key == 'maj' || e.key == 'lut' || e.key == 'lip') continue;
    if (f.startsWith(e.key)) return e.value;
  }
  // skróty: sty, lut, mar, kwi, maj, cze, lip, sie, wrz, paz, lis, gru
  const abbr = {'sty': 1, 'mar': 3, 'kwi': 4, 'cze': 6, 'sie': 8, 'wrz': 9, 'paz': 10, 'lis': 11, 'gru': 12};
  if (f.length == 3 && abbr.containsKey(f)) return abbr[f];
  return null;
}

const _ordinals = <String, int>{
  'pierwszego': 1, 'drugiego': 2, 'trzeciego': 3, 'czwartego': 4, 'piatego': 5, 'szostego': 6, 'siodmego': 7,
  'osmego': 8, 'dziewiatego': 9, 'dziesiatego': 10, 'jedenastego': 11, 'dwunastego': 12, 'trzynastego': 13,
  'czternastego': 14, 'pietnastego': 15, 'szesnastego': 16, 'siedemnastego': 17, 'osiemnastego': 18,
  'dziewietnastego': 19, 'dwudziestego': 20, 'trzydziestego': 30,
};

/// Zamienia słowne liczebniki porządkowe dni (z dyktowania) na cyfry: „dwudziestego pierwszego” → „21”.
String ordinalDaysToDigits(String text) {
  final words = text.split(RegExp(r'\s+'));
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final f = fold(words[i]).replaceAll(RegExp(r'[^a-z]'), '');
    final v = _ordinals[f];
    if (v != null) {
      if ((v == 20 || v == 30) && i + 1 < words.length) {
        final n = _ordinals[fold(words[i + 1]).replaceAll(RegExp(r'[^a-z]'), '')];
        if (n != null && n < 10) {
          out.add('${v + n}');
          i++;
          continue;
        }
      }
      out.add('$v');
    } else {
      out.add(words[i]);
    }
  }
  return out.join(' ');
}

class DateHit {
  final PartialDate date;
  final int start;
  final int end;
  DateHit(this.date, this.start, this.end);
  @override
  String toString() => '$date@$start';
}

/// Wszystkie daty w tekście, po kolei. Obsługuje 12.03.1932, 12-03-1932, 12 III 1932, 12 marca 1932,
/// marzec 1932, 03.1932 i same lata (1800–2199).
List<DateHit> findDates(String text) {
  final hits = <DateHit>[];
  final taken = List<bool>.filled(text.length, false);

  void add(PartialDate? d, int s, int e) {
    if (d == null) return;
    for (var i = s; i < e; i++) {
      if (taken[i]) return;
    }
    for (var i = s; i < e; i++) {
      taken[i] = true;
    }
    hits.add(DateHit(d, s, e));
  }

  // 1) dzień + miesiąc słownie/rzymsko + rok
  final wordy = RegExp(r'(?<![\d])(\d{1,2})[.\s]*\s*([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]{3,}\.?|[IVXivx]{1,4}\.?)\s*[.,]?\s*(\d{4})(?!\d)(?:\s*r\.?)?', unicode: true);
  for (final m in wordy.allMatches(text)) {
    final mon = monthFromWord(m.group(2)!);
    if (mon == null) continue;
    add(PartialDate.checked(int.parse(m.group(3)!), mon, int.parse(m.group(1)!)), m.start, m.end);
  }
  // 2) liczbowo: 12.03.1932 / 12-3-1932 / 12/03/1932 / 12 . 03 . 1932 (OCR)
  final numeric = RegExp(r'(?<!\d)(\d{1,2})\s?[.\-/,]\s?(\d{1,2})\s?[.\-/,]\s?(\d{4})(?!\d)');
  for (final m in numeric.allMatches(text)) {
    add(PartialDate.checked(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)), m.start, m.end);
  }
  // 3) miesiąc słownie + rok
  final monthYear = RegExp(r'([A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]{3,})\.?\s+(\d{4})(?!\d)', unicode: true);
  for (final m in monthYear.allMatches(text)) {
    final mon = monthFromWord(m.group(1)!);
    if (mon == null) continue;
    add(PartialDate.checked(int.parse(m.group(2)!), mon, null), m.start, m.end);
  }
  // 4) 03.1932
  final mY = RegExp(r'(?<![\d.])(\d{1,2})[.\-/](\d{4})(?!\d)');
  for (final m in mY.allMatches(text)) {
    add(PartialDate.checked(int.parse(m.group(2)!), int.parse(m.group(1)!), null), m.start, m.end);
  }
  // 5) sam rok
  final y = RegExp(r'(?<!\d)(1[89]\d{2}|20\d{2}|21\d{2})(?!\d)');
  for (final m in y.allMatches(text)) {
    add(PartialDate.checked(int.parse(m.group(1)!), null, null), m.start, m.end);
  }
  hits.sort((a, b) => a.start.compareTo(b.start));
  return hits;
}

/// Wielkie litery z OCR → „Kowalski”, z zachowaniem nazwisk złożonych („Nowak-Jeziorańska”).
String titleCase(String s) {
  return s.split(' ').where((w) => w.isNotEmpty).map((w) {
    return w.split('-').map((p) {
      if (p.isEmpty) return p;
      return p[0].toUpperCase() + p.substring(1).toLowerCase();
    }).join('-');
  }).join(' ');
}

/// Data wpisana lub podyktowana w dowolnej postaci: „12.03.1932”, „12 marca 1932”, „dwunastego marca 1932”, „1932”.
PartialDate? parseLooseDate(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final direct = PartialDate.parse(t);
  if (direct != null) return direct;
  final hits = findDates(ordinalDaysToDigits(t));
  return hits.isEmpty ? null : hits.first.date;
}
