import 'dart:convert';

/// Plik grobu na serwerze: grób + osoby + zdjęcia (opis) + wizyty, razem z rekordami usuniętymi.
/// Identyfikatory lokalne (id) nie są wysyłane – łączy się po `uid`.
class GraveBundle {
  final Map<String, Object?> grave; // zawiera cemetery_uid
  final List<Map<String, Object?>> people;
  final List<Map<String, Object?>> photos; // zawierają „file”
  final List<Map<String, Object?>> visits;

  GraveBundle(this.grave, this.people, this.photos, this.visits);

  String get uid => grave['uid'] as String;

  Map<String, Object?> toJson() => {'format': 'znicz-sync-grob', 'v': 1, 'grave': grave, 'people': people, 'photos': photos, 'visits': visits};

  List<int> encode() => utf8.encode(jsonEncode(toJson()));

  static GraveBundle decode(List<int> bytes) {
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (j['format'] != 'znicz-sync-grob') throw const FormatException('To nie jest plik grobu Znicz');
    List<Map<String, Object?>> l(String k) => [for (final e in (j[k] as List? ?? const [])) Map<String, Object?>.from(e as Map)];
    return GraveBundle(Map<String, Object?>.from(j['grave'] as Map), l('people'), l('photos'), l('visits'));
  }

  /// Odcisk zawartości: zmienia się, gdy zmieni się którykolwiek rekord.
  String get fingerprint => fingerprintOf([grave, ...people, ...photos, ...visits]);
}

String fingerprintOf(Iterable<Map<String, Object?>> records) {
  final keys = records.map((r) => '${r['uid']}:${r['updated']}:${r['deleted']}').toList()..sort();
  return fnv64(keys.join('|'));
}

/// FNV-1a 64-bit jako tekst szesnastkowy.
String fnv64(String s) {
  // 0xcbf29ce484222325 jako 64-bitowa liczba ze znakiem (int w Dart zawija się przy mnożeniu)
  var h = -0x340d631b7bdddcdb;
  const prime = 0x100000001b3;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h *= prime;
  }
  return h.toRadixString(16);
}

/// Wybór wersji rekordu: nowsza (`updated`) wygrywa; przy remisie usunięcie wygrywa z edycją.
bool remoteWins(Map<String, Object?> remote, Map<String, Object?>? local) {
  if (local == null) return true;
  final ru = (remote['updated'] as num?)?.toInt() ?? 0;
  final lu = (local['updated'] as num?)?.toInt() ?? 0;
  if (ru != lu) return ru > lu;
  return (remote['deleted'] as num? ?? 0) == 1 && (local['deleted'] as num? ?? 0) == 0;
}
