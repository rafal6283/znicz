import 'dart:math';

final _rnd = Random.secure();

/// Stały identyfikator rekordu – wspólny na wszystkich telefonach rodziny.
String newUid() => List.generate(16, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// Data niepełna – na nagrobkach często jest tylko rok albo miesiąc i rok.
class PartialDate implements Comparable<PartialDate> {
  final int year;
  final int? month;
  final int? day;

  const PartialDate(this.year, [this.month, this.day]);

  bool get isFull => month != null && day != null;

  static PartialDate? parse(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$').firstMatch(t);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = iso.group(2) != null ? int.parse(iso.group(2)!) : null;
      final d = iso.group(3) != null ? int.parse(iso.group(3)!) : null;
      return PartialDate.checked(y, m, d);
    }
    // format polski: 12.03.1932, 03.1932, 1932
    final pl = RegExp(r'^(?:(\d{1,2})[.\-/ ])?(?:(\d{1,2}|[IVX]{1,4})[.\-/ ])?(\d{4})$').firstMatch(t);
    if (pl != null) {
      final a = pl.group(1);
      final b = pl.group(2);
      final y = int.parse(pl.group(3)!);
      if (a != null && b != null) return PartialDate.checked(y, monthFromToken(b), int.tryParse(a));
      if (a != null) return PartialDate.checked(y, int.tryParse(a), null);
      return PartialDate.checked(y, null, null);
    }
    return null;
  }

  /// Zwraca null, gdy liczby nie tworzą sensownej daty.
  static PartialDate? checked(int y, int? m, int? d) {
    if (y < 1000 || y > 2200) return null;
    if (m != null && (m < 1 || m > 12)) return null;
    if (d != null) {
      if (m == null) return null;
      final dim = DateTime(y, m + 1, 0).day;
      if (d < 1 || d > dim) return null;
    }
    return PartialDate(y, m, d);
  }

  static int? monthFromToken(String t) {
    final n = int.tryParse(t);
    if (n != null) return n;
    const roman = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12};
    return roman[t.toUpperCase()];
  }

  String toStorage() {
    final b = StringBuffer(year.toString().padLeft(4, '0'));
    if (month != null) b.write('-${month.toString().padLeft(2, '0')}');
    if (month != null && day != null) b.write('-${day.toString().padLeft(2, '0')}');
    return b.toString();
  }

  /// 12.03.1932 / 03.1932 / 1932
  String format() {
    if (month == null) return '$year';
    final mm = month.toString().padLeft(2, '0');
    if (day == null) return '$mm.$year';
    return '${day.toString().padLeft(2, '0')}.$mm.$year';
  }

  DateTime toDateTime() => DateTime(year, month ?? 1, day ?? 1);

  @override
  int compareTo(PartialDate o) {
    if (year != o.year) return year.compareTo(o.year);
    if ((month ?? 0) != (o.month ?? 0)) return (month ?? 0).compareTo(o.month ?? 0);
    return (day ?? 0).compareTo(o.day ?? 0);
  }

  @override
  bool operator ==(Object other) => other is PartialDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toStorage();
}

/// Wiek w chwili śmierci (pełne lata), jeśli da się go wyliczyć.
int? ageAt(PartialDate? birth, PartialDate? death) {
  if (birth == null || death == null) return null;
  var age = death.year - birth.year;
  if (birth.month != null && death.month != null) {
    if (death.month! < birth.month! ||
        (death.month == birth.month && birth.day != null && death.day != null && death.day! < birth.day!)) {
      age--;
    }
  }
  return age < 0 ? null : age;
}

const cemeteryKinds = ['komunalny', 'parafialny', 'wojskowy', 'żydowski', 'ewangelicki', 'prawosławny', 'inny'];

class Cemetery {
  int? id;
  String name;
  String? town;
  String? address;
  double? lat;
  double? lng;
  String? kind;
  String? phone;
  String? hours;
  String? searchUrl; // np. strona wyszukiwarki grobów tego cmentarza
  String? notes;
  String? osmId; // np. way/123456 – cmentarz zaimportowany z OpenStreetMap
  List<(double, double)> outline; // obrys cmentarza (szer., dł.)
  String uid;
  int updated;
  bool deleted;

  Cemetery({
    this.id,
    required this.name,
    this.town,
    this.address,
    this.lat,
    this.lng,
    this.kind,
    this.phone,
    this.hours,
    this.searchUrl,
    this.notes,
    this.osmId,
    List<(double, double)>? outline,
    String? uid,
    int? updated,
    this.deleted = false,
  })  : outline = outline ?? const [],
        uid = uid ?? newUid(),
        updated = updated ?? nowMs();

  bool get hasLocation => lat != null && lng != null;

  String get label => town == null || town!.isEmpty || name.toLowerCase().contains(town!.toLowerCase()) ? name : '$name, $town';

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'town': town,
        'address': address,
        'lat': lat,
        'lng': lng,
        'kind': kind,
        'phone': phone,
        'hours': hours,
        'search_url': searchUrl,
        'notes': notes,
        'osm_id': osmId,
        'outline': encodeOutline(outline),
        'uid': uid,
        'updated': updated,
        'deleted': deleted ? 1 : 0,
      };

  factory Cemetery.fromMap(Map<String, Object?> m) => Cemetery(
        id: m['id'] as int?,
        name: m['name'] as String,
        town: m['town'] as String?,
        address: m['address'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        kind: m['kind'] as String?,
        phone: m['phone'] as String?,
        hours: m['hours'] as String?,
        searchUrl: m['search_url'] as String?,
        notes: m['notes'] as String?,
        osmId: m['osm_id'] as String?,
        outline: decodeOutline(m['outline'] as String?),
        uid: m['uid'] as String?,
        updated: m['updated'] as int?,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}

/// Obrys jako tekst „lat,lng;lat,lng;…” (6 miejsc po przecinku ≈ 10 cm).
String? encodeOutline(List<(double, double)> pts) =>
    pts.isEmpty ? null : pts.map((p) => '${p.$1.toStringAsFixed(6)},${p.$2.toStringAsFixed(6)}').join(';');

List<(double, double)> decodeOutline(String? s) {
  if (s == null || s.isEmpty) return const [];
  final out = <(double, double)>[];
  for (final part in s.split(';')) {
    final xy = part.split(',');
    if (xy.length != 2) continue;
    final a = double.tryParse(xy[0]), b = double.tryParse(xy[1]);
    if (a != null && b != null) out.add((a, b));
  }
  return out;
}

const graveTypes = ['ziemny', 'murowany', 'grobowiec rodzinny', 'urnowy', 'kolumbarium (nisza)', 'katakumby', 'inny'];

class Grave {
  int? id;
  int? cemeteryId;
  double? lat;
  double? lng;
  double? accuracy; // metry
  String? section; // kwatera / pole
  String? row; // rząd
  String? number; // numer grobu
  String? type;
  String? directions; // jak dojść od bramy
  String? notes;
  PartialDate? feePaidUntil; // opłata za miejsce
  bool allSaints; // na liście do odwiedzenia 1 listopada
  bool favorite;
  int created;
  String? osmId; // grób zaimportowany z OpenStreetMap
  String uid;
  int updated;
  bool deleted;

  Grave({
    this.id,
    this.cemeteryId,
    this.lat,
    this.lng,
    this.accuracy,
    this.section,
    this.row,
    this.number,
    this.type,
    this.directions,
    this.notes,
    this.feePaidUntil,
    this.allSaints = true,
    this.favorite = false,
    int? created,
    this.osmId,
    String? uid,
    int? updated,
    this.deleted = false,
  })  : created = created ?? nowMs(),
        uid = uid ?? newUid(),
        updated = updated ?? nowMs();

  bool get hasLocation => lat != null && lng != null;

  /// „kw. 12, rząd 3, nr 45”
  String get placeLabel {
    final parts = <String>[];
    if ((section ?? '').isNotEmpty) parts.add('kw. $section');
    if ((row ?? '').isNotEmpty) parts.add('rząd $row');
    if ((number ?? '').isNotEmpty) parts.add('nr $number');
    return parts.join(', ');
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'cemetery_id': cemeteryId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'section': section,
        'row_no': row,
        'number': number,
        'type': type,
        'directions': directions,
        'notes': notes,
        'fee_until': feePaidUntil?.toStorage(),
        'all_saints': allSaints ? 1 : 0,
        'favorite': favorite ? 1 : 0,
        'created': created,
        'osm_id': osmId,
        'uid': uid,
        'updated': updated,
        'deleted': deleted ? 1 : 0,
      };

  factory Grave.fromMap(Map<String, Object?> m) => Grave(
        id: m['id'] as int?,
        cemeteryId: m['cemetery_id'] as int?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        accuracy: (m['accuracy'] as num?)?.toDouble(),
        section: m['section'] as String?,
        row: m['row_no'] as String?,
        number: m['number'] as String?,
        type: m['type'] as String?,
        directions: m['directions'] as String?,
        notes: m['notes'] as String?,
        feePaidUntil: PartialDate.parse(m['fee_until'] as String?),
        allSaints: (m['all_saints'] as int? ?? 1) == 1,
        favorite: (m['favorite'] as int? ?? 0) == 1,
        created: m['created'] as int?,
        osmId: m['osm_id'] as String?,
        uid: m['uid'] as String?,
        updated: m['updated'] as int?,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}

class Person {
  int? id;
  int graveId;
  String firstName;
  String lastName;
  String? maidenName;
  PartialDate? birth;
  PartialDate? death;
  PartialDate? burial;
  String? relation; // np. „babcia ze strony mamy”
  String? inscription;
  String? notes;
  bool remindDeath;
  bool remindBirth;
  int sort;
  String uid;
  int updated;
  bool deleted;

  Person({
    this.id,
    required this.graveId,
    this.firstName = '',
    this.lastName = '',
    this.maidenName,
    this.birth,
    this.death,
    this.burial,
    this.relation,
    this.inscription,
    this.notes,
    this.remindDeath = true,
    this.remindBirth = false,
    this.sort = 0,
    String? uid,
    int? updated,
    this.deleted = false,
  })  : uid = uid ?? newUid(),
        updated = updated ?? nowMs();

  String get fullName {
    final n = '$firstName $lastName'.trim();
    if ((maidenName ?? '').isNotEmpty) return '$n z d. $maidenName';
    return n.isEmpty ? 'Bez imienia' : n;
  }

  /// „1932–2010”
  String get lifespan {
    if (birth == null && death == null) return '';
    return '${birth?.year ?? '?'}–${death?.year ?? '?'}';
  }

  int? get age => ageAt(birth, death);

  Map<String, Object?> toMap() => {
        'id': id,
        'grave_id': graveId,
        'first_name': firstName,
        'last_name': lastName,
        'maiden_name': maidenName,
        'birth': birth?.toStorage(),
        'death': death?.toStorage(),
        'burial': burial?.toStorage(),
        'relation': relation,
        'inscription': inscription,
        'notes': notes,
        'remind_death': remindDeath ? 1 : 0,
        'remind_birth': remindBirth ? 1 : 0,
        'sort': sort,
        'uid': uid,
        'updated': updated,
        'deleted': deleted ? 1 : 0,
      };

  factory Person.fromMap(Map<String, Object?> m) => Person(
        id: m['id'] as int?,
        graveId: m['grave_id'] as int,
        firstName: m['first_name'] as String? ?? '',
        lastName: m['last_name'] as String? ?? '',
        maidenName: m['maiden_name'] as String?,
        birth: PartialDate.parse(m['birth'] as String?),
        death: PartialDate.parse(m['death'] as String?),
        burial: PartialDate.parse(m['burial'] as String?),
        relation: m['relation'] as String?,
        inscription: m['inscription'] as String?,
        notes: m['notes'] as String?,
        remindDeath: (m['remind_death'] as int? ?? 1) == 1,
        remindBirth: (m['remind_birth'] as int? ?? 0) == 1,
        sort: m['sort'] as int? ?? 0,
        uid: m['uid'] as String?,
        updated: m['updated'] as int?,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}

class GravePhoto {
  int? id;
  int graveId;
  String path; // względna ścieżka w katalogu aplikacji
  String? caption;
  int taken;
  bool cover;
  String uid;
  int updated;
  bool deleted;

  GravePhoto({this.id, required this.graveId, required this.path, this.caption, int? taken, this.cover = false, String? uid, int? updated, this.deleted = false})
      : taken = taken ?? nowMs(),
        uid = uid ?? newUid(),
        updated = updated ?? nowMs();

  Map<String, Object?> toMap() => {
        'id': id,
        'grave_id': graveId,
        'path': path,
        'caption': caption,
        'taken': taken,
        'cover': cover ? 1 : 0,
        'uid': uid,
        'updated': updated,
        'deleted': deleted ? 1 : 0,
      };

  factory GravePhoto.fromMap(Map<String, Object?> m) => GravePhoto(
        id: m['id'] as int?,
        graveId: m['grave_id'] as int,
        path: m['path'] as String,
        caption: m['caption'] as String?,
        taken: m['taken'] as int?,
        cover: (m['cover'] as int? ?? 0) == 1,
        uid: m['uid'] as String?,
        updated: m['updated'] as int?,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}

const visitActions = ['znicz', 'kwiaty', 'sprzątanie', 'modlitwa', 'naprawa'];

class Visit {
  int? id;
  int graveId;
  int date;
  Set<String> actions;
  String? note;
  String? by; // kto z rodziny zapisał wizytę
  String uid;
  int updated;
  bool deleted;

  Visit({this.id, required this.graveId, int? date, Set<String>? actions, this.note, this.by, String? uid, int? updated, this.deleted = false})
      : date = date ?? nowMs(),
        actions = actions ?? {},
        uid = uid ?? newUid(),
        updated = updated ?? nowMs();

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(date);

  Map<String, Object?> toMap() => {
        'id': id,
        'grave_id': graveId,
        'date': date,
        'actions': actions.join(','),
        'note': note,
        'by_name': by,
        'uid': uid,
        'updated': updated,
        'deleted': deleted ? 1 : 0,
      };

  factory Visit.fromMap(Map<String, Object?> m) => Visit(
        id: m['id'] as int?,
        graveId: m['grave_id'] as int,
        date: m['date'] as int,
        actions: ((m['actions'] as String?) ?? '').split(',').where((e) => e.isNotEmpty).toSet(),
        note: m['note'] as String?,
        by: m['by_name'] as String?,
        uid: m['uid'] as String?,
        updated: m['updated'] as int?,
        deleted: (m['deleted'] as int? ?? 0) == 1,
      );
}

/// Grób ze wszystkim, co potrzebne do wyświetlenia na liście.
class GraveView {
  final Grave grave;
  final Cemetery? cemetery;
  final List<Person> people;
  final GravePhoto? cover;
  final Visit? lastVisit;

  GraveView(this.grave, this.cemetery, this.people, this.cover, this.lastVisit);

  String get title {
    if (people.isEmpty) return grave.placeLabel.isEmpty ? 'Grób bez opisu' : 'Grób – ${grave.placeLabel}';
    final names = people.map((p) => p.fullName).toList();
    if (names.length <= 2) return names.join(' i ');
    return '${names.first} i ${names.length - 1} os.';
  }

  /// Wspólne nazwisko rodziny, np. „Grób rodziny Kowalskich” – używane przy wielu osobach.
  String get subtitle {
    final parts = <String>[];
    if (cemetery != null) parts.add(cemetery!.label);
    if (grave.placeLabel.isNotEmpty) parts.add(grave.placeLabel);
    return parts.join(' · ');
  }
}
