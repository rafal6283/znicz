import '../data/models.dart';
import 'dates_pl.dart';

/// Propozycja osoby odczytana z napisu na nagrobku albo z dyktowania.
class PersonGuess {
  String firstName;
  String lastName;
  String? maidenName;
  PartialDate? birth;
  PartialDate? death;
  PartialDate? burial;
  String? relation;
  String? note;

  PersonGuess({this.firstName = '', this.lastName = '', this.maidenName, this.birth, this.death, this.burial, this.relation, this.note});

  bool get isEmpty => firstName.isEmpty && lastName.isEmpty && birth == null && death == null;

  @override
  String toString() => '$firstName|$lastName|${maidenName ?? ''}|${birth ?? ''}|${death ?? ''}';
}

/// Słowa, które nie są imionami ani nazwiskami (napisy nagrobne).
const _stopWords = {
  'sp', 'swp', 'swietej', 'pamieci', 'tu', 'spoczywa', 'spoczywaja', 'spoczywaj', 'w', 'pokoju', 'prosi', 'prosza', 'o',
  'modlitwe', 'westchnienie', 'zdrowas', 'maryjo', 'ur', 'urodz', 'urodzony', 'urodzona', 'zm', 'zmarl', 'zmarla', 'zyl',
  'zyla', 'zyli', 'lat', 'lata', 'roku', 'r', 'dnia', 'kochany', 'kochana', 'ukochany', 'ukochana', 'mama', 'tata', 'maz',
  'zona', 'ojciec', 'matka', 'syn', 'corka', 'dziadek', 'babcia', 'brat', 'siostra', 'odszedl', 'odeszla', 'odeszli',
  'pamietamy', 'pamiec', 'wieczny', 'wieczne', 'wieczna', 'odpoczywaj', 'pokoj', 'jego', 'jej', 'ich', 'duszy', 'rodzina',
  'rodzinny', 'grob', 'grobowiec', 'rodziny', 'kwatera', 'rzad', 'nr', 'numer', 'z', 'domu', 'd', 'i', 'oraz', 'a', 'na',
  'do', 'od', 'dla', 'nie', 'jest', 'bog', 'boze', 'panie', 'amen', 'aniol', 'jezu', 'ufam', 'tobie', 'smierc', 'zycie',
  'prosimy', 'pozostal', 'pozostala', 'zalu', 'zal', 'tesknota', 'zasnal', 'zasnela', 'panu', 'pana', 'w.', 'kpt', 'por',
  'plk', 'gen', 'mjr', 'dr', 'inz', 'mgr', 'prof', 'ks', 'lek', 'sw',
};

final _letters = RegExp(r"^[A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźżÄÖÜäöüé'\-]+$", unicode: true);

String _cleanWord(String w) => w.replaceAll(RegExp(r'^[^\p{L}]+|[^\p{L}]+$', unicode: true), '');

/// Linia wygląda na imię i nazwisko (1–4 słowa z wielkiej litery, bez słów z napisów nagrobnych).
bool looksLikeName(String line) {
  var t = line.trim();
  // „z d. Nowak” / „z domu Nowak” to dopisek do poprzedniej osoby, nie nowa osoba
  if (RegExp(r'^z\s*(?:d\.?|domu)(?:\s|$)', caseSensitive: false).hasMatch(t)) return false;
  t = t.replaceFirst(RegExp(r'^(ś\.?\s*p\.?|s\.?\s*p\.?)\s+', caseSensitive: false), '');
  final words = t.split(RegExp(r'\s+')).map(_cleanWord).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty || words.length > 5) return false;
  var nameWords = 0;
  for (final w in words) {
    if (!_letters.hasMatch(w)) return false;
    final f = fold(w);
    if (f == 'z' || f == 'd' || f == 'domu') continue; // „z d.”, „z domu”
    if (_stopWords.contains(f)) return false;
    if (monthFromWord(w) != null && w.length > 3) return false;
    if (w[0] != w[0].toUpperCase()) return false;
    if (w.length < 2) return false;
    nameWords++;
  }
  return nameWords >= 1;
}

/// Rozbija linię z imieniem i nazwiskiem: ostatnie słowo = nazwisko, „z d. X” / „z domu X” = nazwisko rodowe.
PersonGuess splitName(String line) {
  var t = line.trim().replaceFirst(RegExp(r'^(ś\.?\s*p\.?|s\.?\s*p\.?)\s+', caseSensitive: false), '');
  String? maiden;
  final md = RegExp(r'\bz\s*(?:d\.?|domu)\s+([^\s,]+)', caseSensitive: false, unicode: true).firstMatch(t);
  if (md != null) {
    maiden = titleCase(_cleanWord(md.group(1)!));
    t = (t.substring(0, md.start) + t.substring(md.end)).trim();
  }
  final words = t.split(RegExp(r'\s+')).map(_cleanWord).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return PersonGuess(maidenName: maiden);
  if (words.length == 1) return PersonGuess(firstName: titleCase(words.first), maidenName: maiden);
  return PersonGuess(
    firstName: titleCase(words.sublist(0, words.length - 1).join(' ')),
    lastName: titleCase(words.last),
    maidenName: maiden,
  );
}

enum _Role { birth, death, unknown }

_Role _roleBefore(String text, int pos) {
  final from = pos - 14 < 0 ? 0 : pos - 14;
  final ctx = fold(text.substring(from, pos));
  // ostatni znacznik przed datą wygrywa
  final b = RegExp(r'(ur\b|ur\.|urodz|\*)').allMatches(ctx).map((m) => m.end).fold<int>(-1, (a, b) => b > a ? b : a);
  final d = RegExp(r'(zm\b|zm\.|zmar|†|\+|odsz|zgin|polegl)').allMatches(ctx).map((m) => m.end).fold<int>(-1, (a, b) => b > a ? b : a);
  if (b < 0 && d < 0) return _Role.unknown;
  return b > d ? _Role.birth : _Role.death;
}

void _assignDates(PersonGuess g, String text) {
  final hits = findDates(text);
  final unknown = <PartialDate>[];
  for (final h in hits) {
    switch (_roleBefore(text, h.start)) {
      case _Role.birth:
        g.birth ??= h.date;
      case _Role.death:
        g.death ??= h.date;
      case _Role.unknown:
        unknown.add(h.date);
    }
  }
  // bez znaczników: pierwsza data = urodzenie, druga = śmierć (układ „1932 – 2010”)
  for (final d in unknown) {
    if (g.birth == null && (g.death == null || d.compareTo(g.death!) < 0)) {
      g.birth = d;
    } else if (g.death == null) {
      g.death = d;
    }
  }
  if (g.birth != null && g.death != null && g.birth!.compareTo(g.death!) > 0) {
    final t = g.birth;
    g.birth = g.death;
    g.death = t;
  }
  // „żył lat 78” → przybliżony rok urodzenia
  final age = RegExp(r'(?:zyl[a]?|zyli|lat)\s*(?:lat\s*)?(\d{1,3})').firstMatch(fold(text));
  if (age != null) {
    final a = int.parse(age.group(1)!);
    if (g.birth == null && g.death != null && a > 0 && a < 120) {
      g.birth = PartialDate(g.death!.year - a);
      g.note = 'Rok urodzenia wyliczony z napisu „żył(a) lat $a” (±1 rok).';
    }
  }
}

/// Odczytuje osoby z tekstu nagrobka (OCR). Każda linia z imieniem zaczyna nową osobę,
/// a daty pod nią należą do tej osoby.
List<PersonGuess> parseInscription(String raw) {
  final lines = raw.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  // scal imię i nazwisko rozbite na dwie linie („JAN” / „KOWALSKI”)
  final merged = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (i + 1 < lines.length && looksLikeName(l) && looksLikeName(lines[i + 1])) {
      final a = l.split(RegExp(r'\s+')).length;
      final b = lines[i + 1].split(RegExp(r'\s+')).length;
      final nextNext = i + 2 < lines.length ? lines[i + 2] : '';
      // „JAN” + „KOWALSKI”, ale nie dwie osoby pod sobą ani nazwisko rodziny w liczbie mnogiej
      if (a == 1 && b <= 2 && !looksLikeName(nextNext) && familySurnameToSingular(lines[i + 1], female: false) == null) {
        merged.add('$l ${lines[i + 1]}');
        i++;
        continue;
      }
    }
    merged.add(l);
  }

  final people = <PersonGuess>[];
  String? currentName;
  final buf = StringBuffer();
  final orphan = StringBuffer(); // tekst przed pierwszym imieniem

  void flush() {
    if (currentName == null) return;
    final g = splitName(currentName!);
    _assignDates(g, buf.toString());
    people.add(g);
    buf.clear();
  }

  for (final l in merged) {
    // linia z imieniem i datami w jednej („JAN KOWALSKI 1932-2010”)
    final dates = findDates(l);
    final namePart = dates.isEmpty ? l : l.substring(0, dates.first.start);
    final cleanName = namePart.replaceAll(RegExp(r'(\bur\.?|\bzm\.?|[*†+–\-])\s*$', caseSensitive: false), '').trim();
    if (cleanName.isNotEmpty && looksLikeName(cleanName)) {
      flush();
      currentName = cleanName;
      if (dates.isNotEmpty) buf.writeln(l.substring(namePart.length));
      // „z domu Nowak” w następnej linii trafi do bufora – obsługa niżej
      continue;
    }
    final maiden = RegExp(r'^z\s*(?:d\.?|domu)\s+(\S+)', caseSensitive: false).firstMatch(l);
    if (maiden != null && currentName != null) {
      currentName = '$currentName z d. ${maiden.group(1)}';
      buf.writeln(l.substring(maiden.end));
      continue;
    }
    if (currentName == null) {
      orphan.writeln(l);
    } else {
      buf.writeln(l);
    }
  }
  flush();

  // daty przed imieniem (rzadkie) albo napis bez imion
  if (people.isEmpty) {
    final g = PersonGuess();
    _assignDates(g, orphan.toString());
    if (!g.isEmpty) people.add(g);
  }

  // nazwisko rodziny w liczbie mnogiej („KOWALSCY”, „NOWAKOWIE”) jako osobna linia
  final family = people.where((p) => p.lastName.isEmpty && p.birth == null && p.death == null && familySurnameToSingular(p.firstName, female: false) != null).toList();
  if (family.isNotEmpty && people.length > family.length) {
    final plural = family.first.firstName;
    people.removeWhere(family.contains);
    for (final p in people) {
      if (p.lastName.isEmpty) p.lastName = familySurnameToSingular(plural, female: isFemaleFirstName(p.firstName)) ?? plural;
    }
  }

  // wspólne nazwisko: tylko jedna osoba ma nazwisko – uzupełnij u pozostałych
  final withLast = people.where((p) => p.lastName.isNotEmpty).toList();
  if (withLast.length == 1 && people.length > 1) {
    final ln = withLast.first.lastName;
    for (final p in people) {
      if (p.lastName.isEmpty) p.lastName = ln;
    }
  }
  // osoba bez dat i bez nazwiska najpewniej jest nazwiskiem rodziny („KOWALSCY”) – usuń
  people.removeWhere((p) => p.lastName.isEmpty && p.birth == null && p.death == null && people.length > 1);
  return people;
}

/// Imię żeńskie wg polskiej reguły (kończy się na „a”, z kilkoma wyjątkami męskimi).
bool isFemaleFirstName(String first) {
  final f = fold(first.trim().split(RegExp(r'\s+')).first);
  if (f.isEmpty) return false;
  const maleA = {'kuba', 'barnaba', 'bonawentura', 'kosma', 'jarema', 'boryna', 'saba'};
  return f.endsWith('a') && !maleA.contains(f);
}

/// „Kowalscy” → Kowalski/Kowalska, „Zawadzcy” → Zawadzki/Zawadzka, „Nowakowie” → Nowak.
/// Zwraca null, gdy słowo nie wygląda na nazwisko rodziny w liczbie mnogiej.
String? familySurnameToSingular(String word, {required bool female}) {
  final w = titleCase(word.trim());
  if (w.contains(' ') || w.length < 5) return null;
  final f = fold(w);
  String base(int cut) => w.substring(0, w.length - cut);
  if (f.endsWith('scy')) return '${base(3)}${female ? 'ska' : 'ski'}';
  if (f.endsWith('ccy')) return '${base(3)}${female ? 'cka' : 'cki'}';
  if (f.endsWith('dzcy')) return '${base(4)}${female ? 'dzka' : 'dzki'}';
  if (f.endsWith('cy') && f.length > 5) return '${base(2)}${female ? 'ka' : 'ki'}';
  if (f.endsWith('owie') && f.length > 6) return base(4);
  return null;
}
