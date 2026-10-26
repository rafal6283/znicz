import '../data/models.dart';
import 'dates_pl.dart';
import 'inscription_parser.dart';

/// Wynik dyktowania całego grobu, np.:
/// „Jan Kowalski, dziadek, urodzony 12 marca 1932, zmarł 5 listopada 2010, kwatera 12, rząd 3, numer 45,
///  cmentarz parafialny w Celestynowie, oraz Anna Kowalska z domu Nowak, zmarła w 2015”.
class DictationResult {
  final List<PersonGuess> people = [];
  String? section;
  String? row;
  String? number;
  String? cemetery;
  String? directions;

  bool get isEmpty => people.isEmpty && section == null && row == null && number == null && cemetery == null && directions == null;
}

const relationWords = [
  'prapradziadek', 'praprababcia', 'pradziadek', 'prababcia', 'dziadek', 'babcia', 'tata', 'ojciec', 'mama', 'matka',
  'brat', 'siostra', 'wujek', 'wuj', 'stryj', 'ciocia', 'ciotka', 'kuzyn', 'kuzynka', 'syn', 'córka', 'mąż', 'żona',
  'teść', 'teściowa', 'szwagier', 'szwagierka', 'bratanek', 'bratanica', 'siostrzeniec', 'siostrzenica', 'wnuk',
  'wnuczka', 'przyjaciel', 'przyjaciółka', 'chrzestny', 'chrzestna', 'ojciec chrzestny', 'matka chrzestna',
];

/// Słowa kluczowe dzielące wypowiedź na pola (po usunięciu polskich znaków).
final _keyword = RegExp(
  r'\b(urodzon[ya]|urodzil[ao]?\s+sie|ur\.?|zmarl[ay]?|zmar[lł]a|zm\.?|zginal|zginela|polegl[ay]?|pochowan[ya]|pogrzeb|'
  r'kwatera|kwaterze|kwatery|pole|polu|sektor|sektorze|aleja|alei|rzad|rzedzie|numer|nr|grob\s+numer|'
  r'cmentarz|cmentarzu|z\s+domu|z\s+d\b|droga|jak\s+dojsc|dojscie|zyl[ay]?)\b',
);

String _fieldValue(String s) {
  // wartość pola: „12”, „12a”, „b”, „IV”, „12 b” – do przecinka lub kolejnego słowa kluczowego
  final t = s.trim().replaceAll(RegExp(r'^[:\-,.]\s*'), '');
  final m = RegExp(r'^(\d+\s?[a-zA-Z]?\b|[a-zA-Z]{1,2}\b|[IVXivx]{1,4}\b|\w+)', unicode: true).firstMatch(t);
  if (m == null) return '';
  return m.group(1)!.replaceAll(' ', '').toUpperCase().replaceFirstMapped(RegExp(r'^(\d+)([A-Z])$'), (x) => '${x[1]}${x[2]!.toLowerCase()}');
}

List<String> _splitPeople(String text) {
  return text
      .split(RegExp(r'\b(?:oraz|nastepna osoba|następna osoba|kolejna osoba|druga osoba|trzecia osoba|i jeszcze)\b|;', caseSensitive: false))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

DictationResult parseDictation(String spoken) {
  final r = DictationResult();
  final text0 = ordinalDaysToDigits(spoken.replaceAll(RegExp(r'\s+'), ' ').trim());
  for (final seg in _splitPeople(text0)) {
    _parseSegment(seg, r);
  }
  return r;
}

void _parseSegment(String text, DictationResult r) {
  final folded = fold(text); // indeksy zgodne z text
  final marks = _keyword.allMatches(folded).toList();
  // początek segmentu przed pierwszym słowem kluczowym = imię i nazwisko (+ ewentualnie relacja)
  final head = marks.isEmpty ? text : text.substring(0, marks.first.start);
  final g = PersonGuess();

  var namePart = head.replaceAll(RegExp(r'[,.]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  // relacja na początku albo na końcu: „babcia Anna Nowak” / „Anna Nowak babcia ze strony mamy”
  for (final rel in relationWords) {
    final m = RegExp('(?:^|\\s)(${RegExp.escape(fold(rel))})(\\s+ze\\s+strony\\s+\\S+)?(?=\\s|\$)').firstMatch(fold(namePart));
    if (m != null) {
      g.relation = namePart.substring(m.start, m.end).trim();
      namePart = (namePart.substring(0, m.start) + namePart.substring(m.end)).replaceAll(RegExp(r'\s+'), ' ').trim();
      break;
    }
  }
  // usuń wtrącenia typu „grób”, „pan”, „pani”, „ś.p.”
  namePart = namePart.replaceAll(RegExp(r'\b(grób|grob|pan|pani|świętej pamięci|swietej pamieci|ś\.?p\.?)\b', caseSensitive: false), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (namePart.isNotEmpty) {
    final words = namePart.split(' ');
    // dyktowanie nie zawsze ma wielkie litery – i tak traktujemy jako imię + nazwisko
    if (words.length <= 4 && words.every((w) => RegExp(r"^[\p{L}'\-]+$", unicode: true).hasMatch(w))) {
      final s = splitName(titleCase(namePart));
      g.firstName = s.firstName;
      g.lastName = s.lastName;
    }
  }

  for (var i = 0; i < marks.length; i++) {
    final m = marks[i];
    final kw = m.group(1)!;
    final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
    final value = text.substring(m.end, end);
    final dates = findDates(value);
    if (kw.startsWith('urodz') || kw.startsWith('ur')) {
      if (dates.isNotEmpty) g.birth ??= dates.first.date;
    } else if (kw.startsWith('zm') || kw.startsWith('zgin') || kw.startsWith('polegl')) {
      if (dates.isNotEmpty) g.death ??= dates.first.date;
    } else if (kw.startsWith('pochowan') || kw == 'pogrzeb') {
      if (dates.isNotEmpty) g.burial ??= dates.first.date;
    } else if (kw.startsWith('kwater') || kw.startsWith('pol') || kw.startsWith('sektor') || kw.startsWith('ale')) {
      final v = _fieldValue(value);
      if (v.isNotEmpty) r.section ??= v;
    } else if (kw.startsWith('rz')) {
      final v = _fieldValue(value);
      if (v.isNotEmpty) r.row ??= v;
    } else if (kw == 'numer' || kw == 'nr' || kw.startsWith('grob')) {
      final v = _fieldValue(value);
      if (v.isNotEmpty) r.number ??= v;
    } else if (kw.startsWith('cmentarz')) {
      final v = value.split(',').first.trim();
      if (v.isNotEmpty) r.cemetery ??= _cemeteryName(v);
    } else if (kw.startsWith('z ')) {
      final w = value.trim().split(RegExp(r'[\s,]+')).where((e) => e.isNotEmpty).toList();
      if (w.isNotEmpty) g.maidenName = titleCase(w.first);
    } else if (kw.startsWith('drog') || kw.startsWith('jak') || kw.startsWith('dojsc')) {
      final v = value.trim().replaceFirst(RegExp(r'^[:\-,]\s*'), '');
      if (v.isNotEmpty) r.directions = v[0].toUpperCase() + v.substring(1);
    } else if (kw.startsWith('zyl')) {
      final a = RegExp(r'(\d{1,3})').firstMatch(value);
      if (a != null && g.birth == null && g.death != null) {
        g.birth = PartialDate(g.death!.year - int.parse(a.group(1)!));
        g.note = 'Rok urodzenia wyliczony z wieku (±1 rok).';
      }
    }
  }
  // same daty bez słów kluczowych: „Jan Kowalski 1932 2010”
  if (g.birth == null && g.death == null && marks.isEmpty) {
    final d = findDates(text);
    if (d.length >= 2) {
      g.birth = d[0].date;
      g.death = d[1].date;
    } else if (d.length == 1) {
      g.death = d[0].date;
    }
    if (d.isNotEmpty) {
      final s = splitName(titleCase(text.substring(0, d.first.start).replaceAll(RegExp(r'[,.]'), ' ').trim()));
      g.firstName = s.firstName;
      g.lastName = s.lastName;
    }
  }
  if (!g.isEmpty || g.relation != null || g.maidenName != null) r.people.add(g);
}

/// „parafialnym w Celestynowie” → „Cmentarz parafialny w Celestynowie”
String _cemeteryName(String v) {
  var t = v.trim().replaceAll(RegExp(r'[.]$'), '');
  t = t
      .replaceAllMapped(RegExp(r'\b(komunaln|parafialn|wojskow|zydowsk|żydowsk|ewangelick|prawoslawn|prawosławn)(ym|ego|y)\b', caseSensitive: false), (m) => '${m[1]}y')
      .replaceAll(RegExp(r'\b(stary|starym|starego)\b', caseSensitive: false), 'stary')
      .replaceAll(RegExp(r'\b(nowym|nowego)\b', caseSensitive: false), 'nowy');
  // nazwa miejscowości z wielkiej litery po „w”/„na”
  t = t.replaceAllMapped(RegExp(r'\b(w|we|na)\s+(\p{L}+)', unicode: true), (m) => '${m[1]} ${titleCase(m[2]!)}');
  return 'Cmentarz $t'.replaceAll(RegExp(r'\s+'), ' ').trim();
}
