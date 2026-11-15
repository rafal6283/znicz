import '../data/models.dart';

/// Relacje rodzinne zapisane przy osobach (matka, ojciec, małżonek – po uid).
class FamilyIndex {
  final Map<String, Person> byUid;
  FamilyIndex(Iterable<Person> people) : byUid = {for (final p in people) p.uid: p};

  Person? mother(Person p) => p.motherUid == null ? null : byUid[p.motherUid];
  Person? father(Person p) => p.fatherUid == null ? null : byUid[p.fatherUid];

  /// Małżonek – zapisany przy tej osobie albo przy drugiej stronie.
  Person? spouse(Person p) {
    if (p.spouseUid != null && byUid[p.spouseUid] != null) return byUid[p.spouseUid];
    for (final o in byUid.values) {
      if (o.spouseUid == p.uid) return o;
    }
    return null;
  }

  List<Person> children(Person p) {
    final s = spouse(p);
    final out = byUid.values
        .where((c) => c.motherUid == p.uid || c.fatherUid == p.uid || (s != null && (c.motherUid == s.uid || c.fatherUid == s.uid)))
        .toList();
    out.sort((a, b) => (a.birth?.year ?? 9999).compareTo(b.birth?.year ?? 9999));
    return out;
  }

  /// Przodkowie pokoleniami: [rodzice], [dziadkowie], … (null tam, gdzie nieznany).
  List<List<Person?>> ancestors(Person p, {int generations = 3}) {
    final out = <List<Person?>>[];
    var level = <Person?>[p];
    for (var g = 0; g < generations; g++) {
      final next = <Person?>[];
      for (final x in level) {
        next
          ..add(x == null ? null : father(x))
          ..add(x == null ? null : mother(x));
      }
      if (next.every((e) => e == null)) break;
      out.add(next);
      level = next;
    }
    return out;
  }

  /// Czy ustawienie [candidateUid] jako przodka [p] utworzy pętlę (ktoś byłby własnym przodkiem).
  bool wouldCycle(Person p, String candidateUid) {
    final seen = <String>{};
    final stack = <String>[candidateUid];
    while (stack.isNotEmpty) {
      final u = stack.removeLast();
      if (u == p.uid) return true;
      if (!seen.add(u)) continue;
      final x = byUid[u];
      if (x == null) continue;
      if (x.motherUid != null) stack.add(x.motherUid!);
      if (x.fatherUid != null) stack.add(x.fatherUid!);
    }
    return false;
  }
}

/// Płeć potrzebna w GEDCOM – zgadywana z polskiego imienia (kończy się na „a” → kobieta).
String guessSex(Person p) {
  final f = p.firstName.trim().split(RegExp(r'\s+')).first.toLowerCase();
  if (f.isEmpty) return 'U';
  const maleA = {'kuba', 'barnaba', 'bonawentura', 'kosma', 'jarema'};
  return f.endsWith('a') && !maleA.contains(f) ? 'F' : 'M';
}

String _gedDate(PartialDate d) {
  const m = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  if (d.month == null) return '${d.year}';
  if (d.day == null) return '${m[d.month! - 1]} ${d.year}';
  return '${d.day} ${m[d.month! - 1]} ${d.year}';
}

/// Eksport osób i relacji do GEDCOM 5.5.1 (format programów genealogicznych: MyHeritage, Ancestry, Gramps…).
/// [placeOf] – opis miejsca pochówku dla osoby (cmentarz, kwatera).
String buildGedcom(List<Person> people, {String Function(Person)? placeOf, DateTime? now}) {
  final idx = FamilyIndex(people);
  final ids = <String, String>{};
  var n = 1;
  for (final p in people) {
    ids[p.uid] = '@I${n++}@';
  }
  // rodziny: para rodziców (ojciec+matka) albo małżonkowie
  final fams = <String, (String?, String?, List<String>)>{}; // klucz → (mąż, żona, dzieci)
  String key(String? a, String? b) => '${a ?? '-'}|${b ?? '-'}';
  for (final p in people) {
    final f = p.fatherUid != null && ids.containsKey(p.fatherUid) ? p.fatherUid : null;
    final m = p.motherUid != null && ids.containsKey(p.motherUid) ? p.motherUid : null;
    if (f != null || m != null) {
      final k = key(f, m);
      fams.putIfAbsent(k, () => (f, m, <String>[])).$3.add(p.uid);
    }
  }
  for (final p in people) {
    final s = idx.spouse(p);
    if (s == null || !ids.containsKey(s.uid)) continue;
    final (h, w) = guessSex(p) == 'F' ? (s.uid, p.uid) : (p.uid, s.uid);
    final k = key(h, w);
    final alt = fams.keys.where((x) => x == key(h, w) || x == key(w, h));
    if (alt.isEmpty) fams[k] = (h, w, <String>[]);
  }
  final famIds = <String, String>{};
  var fn = 1;
  for (final k in fams.keys) {
    famIds[k] = '@F${fn++}@';
  }
  final t = now ?? DateTime.now();
  final b = StringBuffer()
    ..writeln('0 HEAD')
    ..writeln('1 SOUR ZNICZ')
    ..writeln('2 NAME Znicz')
    ..writeln('1 GEDC')
    ..writeln('2 VERS 5.5.1')
    ..writeln('2 FORM LINEAGE-LINKED')
    ..writeln('1 CHAR UTF-8')
    ..writeln('1 DATE ${_gedDate(PartialDate(t.year, t.month, t.day))}');
  for (final p in people) {
    b.writeln('0 ${ids[p.uid]} INDI');
    final given = p.firstName.trim();
    final surname = p.lastName.trim();
    b.writeln('1 NAME $given /$surname/');
    if (given.isNotEmpty) b.writeln('2 GIVN $given');
    if (surname.isNotEmpty) b.writeln('2 SURN $surname');
    if ((p.maidenName ?? '').isNotEmpty) {
      b
        ..writeln('1 NAME $given /${p.maidenName}/')
        ..writeln('2 TYPE birth');
    }
    b.writeln('1 SEX ${guessSex(p)}');
    if (p.birth != null) {
      b
        ..writeln('1 BIRT')
        ..writeln('2 DATE ${_gedDate(p.birth!)}');
    }
    if (p.death != null) {
      b
        ..writeln('1 DEAT')
        ..writeln('2 DATE ${_gedDate(p.death!)}');
    }
    final place = placeOf?.call(p);
    if (p.burial != null || (place ?? '').isNotEmpty) {
      b.writeln('1 BURI');
      if (p.burial != null) b.writeln('2 DATE ${_gedDate(p.burial!)}');
      if ((place ?? '').isNotEmpty) b.writeln('2 PLAC $place');
    }
    final notes = [if ((p.inscription ?? '').isNotEmpty) 'Napis: ${p.inscription}', if ((p.notes ?? '').isNotEmpty) p.notes!];
    if (notes.isNotEmpty) b.writeln('1 NOTE ${notes.join(' / ').replaceAll('\n', ' ')}');
    for (final e in fams.entries) {
      final (h, w, kids) = e.value;
      if (h == p.uid || w == p.uid) b.writeln('1 FAMS ${famIds[e.key]}');
      if (kids.contains(p.uid)) b.writeln('1 FAMC ${famIds[e.key]}');
    }
  }
  for (final e in fams.entries) {
    final (h, w, kids) = e.value;
    b.writeln('0 ${famIds[e.key]} FAM');
    if (h != null) b.writeln('1 HUSB ${ids[h]}');
    if (w != null) b.writeln('1 WIFE ${ids[w]}');
    for (final c in kids) {
      b.writeln('1 CHIL ${ids[c]}');
    }
  }
  b.writeln('0 TRLR');
  return b.toString();
}

/// Kody województw w Genetece (indeksy metrykalne).
const genetekaRegions = {
  '07mz': 'mazowieckie',
  '71wa': 'Warszawa',
  '01ds': 'dolnośląskie',
  '02kp': 'kujawsko-pomorskie',
  '03lb': 'lubelskie',
  '04ls': 'lubuskie',
  '05ld': 'łódzkie',
  '06mp': 'małopolskie',
  '08op': 'opolskie',
  '09pk': 'podkarpackie',
  '10pl': 'podlaskie',
  '11pm': 'pomorskie',
  '12sl': 'śląskie',
  '13sk': 'świętokrzyskie',
  '14wm': 'warmińsko-mazurskie',
  '15wp': 'wielkopolskie',
  '16zp': 'zachodniopomorskie',
};

/// Adres wyszukiwania w Genetece. [kind]: B – urodzenia, S – zgony, M – małżeństwa.
Uri genetekaUri({required String lastName, String firstName = '', String region = '07mz', String kind = 'S', int? fromYear, int? toYear}) {
  return Uri.https('geneteka.genealodzy.pl', '/index.php', {
    'op': 'gt',
    'lang': 'pol',
    'bdm': kind,
    'w': region,
    'rid': kind,
    'search_lastname': lastName,
    'search_name': firstName,
    'search_lastname2': '',
    'search_name2': '',
    'from_date': fromYear?.toString() ?? '',
    'to_date': toYear?.toString() ?? '',
  });
}
