import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../logic/dates_pl.dart';
import '../logic/geo.dart';
import '../logic/inscription_parser.dart';

/// Cmentarz znaleziony w OpenStreetMap.
class OsmCemetery {
  final String osmId; // „way/123”, „relation/45”, „node/9”
  final Map<String, String> tags;
  final List<(double, double)> outline;
  final double lat;
  final double lng;
  double distance = 0; // od miejsca wyszukiwania

  OsmCemetery(this.osmId, this.tags, this.outline, this.lat, this.lng);

  String? get name => tags['name'];

  /// Rodzaj w nazewnictwie aplikacji.
  String? get kind {
    final r = '${tags['religion'] ?? ''} ${tags['denomination'] ?? ''} ${tags['cemetery'] ?? ''}'.toLowerCase();
    if (r.contains('military') || r.contains('war')) return 'wojskowy';
    if (r.contains('jewish')) return 'żydowski';
    if (r.contains('orthodox')) return 'prawosławny';
    if (r.contains('lutheran') || r.contains('protestant') || r.contains('evangelical')) return 'ewangelicki';
    if (tags['operator']?.toLowerCase().contains('parafi') == true || r.contains('catholic') || tags['amenity'] == 'grave_yard') return 'parafialny';
    if (tags['operator']?.toLowerCase().contains('gmin') == true || tags['operator']?.toLowerCase().contains('miast') == true) return 'komunalny';
    return null;
  }

  String? get town => tags['addr:city'] ?? tags['addr:place'] ?? tags['is_in:city'];

  /// Nazwa do wyświetlenia (cmentarze w OSM często nie mają nazwy).
  String get label {
    if ((name ?? '').isNotEmpty) return name!;
    final k = kind;
    return k == null ? 'Cmentarz' : 'Cmentarz $k';
  }

  double get areaHa {
    if (outline.length < 3) return 0;
    // pole w przybliżeniu płaskim (wystarcza dla małych obszarów)
    final lat0 = outline.first.$1;
    final kx = 111320 * cosDeg(lat0), ky = 110540.0;
    var a = 0.0;
    for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      a += (outline[j].$2 * kx) * (outline[i].$1 * ky) - (outline[i].$2 * kx) * (outline[j].$1 * ky);
    }
    return (a.abs() / 2) / 10000;
  }
}

/// Grób z imieniem opisany w OpenStreetMap (cemetery=grave), z osobami z relacji type=person.
class OsmGrave {
  final String osmId;
  final double lat;
  final double lng;
  final String? inscription;
  final List<PersonGuess> people;
  OsmGrave(this.osmId, this.lat, this.lng, this.inscription, this.people);

  String get title => people.isEmpty ? 'Grób' : people.map((p) => '${p.firstName} ${p.lastName}'.trim()).join(', ');
}

class OsmException implements Exception {
  final String message;
  OsmException(this.message);
  @override
  String toString() => message;
}

class Osm {
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static Future<Map<String, dynamic>> _query(String q) async {
    Object? lastErr;
    for (final url in _endpoints) {
      try {
        final res = await http
            .post(Uri.parse(url), headers: {'User-Agent': 'Znicz/1.0 (prywatna aplikacja do notowania grobow)'}, body: {'data': q})
            .timeout(const Duration(seconds: 45));
        if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        lastErr = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastErr = e;
      }
    }
    throw OsmException('Nie udało się pobrać danych z OpenStreetMap ($lastErr). Sprawdź internet i spróbuj za chwilę.');
  }

  static Future<List<OsmCemetery>> cemeteriesNear(double lat, double lng, {int radiusM = 5000}) async {
    final a = '(around:$radiusM,$lat,$lng)';
    final q = '[out:json][timeout:40];('
        'way["landuse"="cemetery"]$a;relation["landuse"="cemetery"]$a;'
        'way["amenity"="grave_yard"]$a;relation["amenity"="grave_yard"]$a;node["amenity"="grave_yard"]$a;'
        ');out geom;';
    return parseCemeteries(await _query(q), lat, lng);
  }

  /// Cmentarze w prostokącie widocznym na mapie (płd., zach., płn., wsch.).
  /// [refLat]/[refLng] – punkt, od którego liczona jest odległość (np. Twoja pozycja albo środek mapy).
  static Future<List<OsmCemetery>> cemeteriesInBox(double s, double w, double n, double e, double refLat, double refLng) async {
    final b = '(${s.toStringAsFixed(5)},${w.toStringAsFixed(5)},${n.toStringAsFixed(5)},${e.toStringAsFixed(5)})';
    final q = '[out:json][timeout:40];('
        'way["landuse"="cemetery"]$b;relation["landuse"="cemetery"]$b;'
        'way["amenity"="grave_yard"]$b;relation["amenity"="grave_yard"]$b;node["amenity"="grave_yard"]$b;'
        ');out geom;';
    return parseCemeteries(await _query(q), refLat, refLng);
  }

  /// Nazwa miejscowości dla punktu (Nominatim, OpenStreetMap). Null, gdy się nie uda.
  static Future<String?> townAt(double lat, double lng) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=14&accept-language=pl'
          '&lat=${lat.toStringAsFixed(6)}&lon=${lng.toStringAsFixed(6)}');
      final res = await http.get(uri, headers: {'User-Agent': 'Znicz/1.0 (prywatna aplikacja do notowania grobow)'}).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return townFromNominatim(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static String? townFromNominatim(Map<String, dynamic> j) {
    final a = (j['address'] as Map?) ?? const {};
    for (final k in ['village', 'town', 'city', 'hamlet', 'suburb', 'municipality']) {
      final v = a[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static Future<List<OsmGrave>> gravesIn(List<(double, double)> outline, double lat, double lng) async {
    double s, w, n, e;
    if (outline.length >= 3) {
      s = outline.map((p) => p.$1).reduce((a, b) => a < b ? a : b);
      n = outline.map((p) => p.$1).reduce((a, b) => a > b ? a : b);
      w = outline.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
      e = outline.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
    } else {
      s = lat - 0.003;
      n = lat + 0.003;
      w = lng - 0.005;
      e = lng + 0.005;
    }
    final q = '[out:json][timeout:40];'
        'nw["cemetery"="grave"]($s,$w,$n,$e)->.g;'
        '(rel(bn.g)["type"="person"];rel(bw.g)["type"="person"];)->.p;'
        '.g out body center;.p out body;';
    final all = parseGraves(await _query(q));
    if (outline.length < 3) return all;
    return all.where((g) => pointInPolygon(g.lat, g.lng, outline)).toList();
  }

  // ---------- parsowanie (czyste funkcje – testowane) ----------

  static List<OsmCemetery> parseCemeteries(Map<String, dynamic> json, double lat, double lng) {
    final out = <String, OsmCemetery>{};
    for (final el in (json['elements'] as List? ?? const [])) {
      final m = el as Map<String, dynamic>;
      final type = m['type'] as String;
      final id = '$type/${m['id']}';
      final tags = {for (final e in ((m['tags'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'};
      var outline = <(double, double)>[];
      if (type == 'way') {
        outline = [for (final g in (m['geometry'] as List? ?? const [])) ((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble())];
      } else if (type == 'relation') {
        // najdłuższy zewnętrzny pierścień
        for (final mem in (m['members'] as List? ?? const [])) {
          if (mem['type'] != 'way' || (mem['role'] ?? 'outer') == 'inner') continue;
          final pts = [for (final g in (mem['geometry'] as List? ?? const [])) ((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble())];
          if (pts.length > outline.length) outline = pts;
        }
      }
      double cLat, cLng;
      if (type == 'node') {
        cLat = (m['lat'] as num).toDouble();
        cLng = (m['lon'] as num).toDouble();
      } else if (outline.isNotEmpty) {
        (cLat, cLng) = centroid(outline);
      } else {
        continue;
      }
      outline = simplifyOutline(outline, 300);
      final c = OsmCemetery(id, tags, outline, cLat, cLng)..distance = distanceToArea(lat, lng, outline, cLat, cLng);
      out[id] = c;
    }
    // ten sam cmentarz oznaczony podwójnie (landuse + amenity) – zostaw większy obrys
    final list = out.values.toList()..sort((a, b) => b.outline.length.compareTo(a.outline.length));
    final kept = <OsmCemetery>[];
    for (final c in list) {
      final dup = kept.any((k) => k.outline.length >= 3 && pointInPolygon(c.lat, c.lng, k.outline) && (c.name == null || c.name == k.name));
      if (!dup) kept.add(c);
    }
    kept.sort((a, b) => a.distance.compareTo(b.distance));
    return kept;
  }

  static List<OsmGrave> parseGraves(Map<String, dynamic> json) {
    final graves = <String, Map<String, dynamic>>{};
    final persons = <Map<String, dynamic>>[];
    for (final el in (json['elements'] as List? ?? const [])) {
      final m = el as Map<String, dynamic>;
      final tags = (m['tags'] as Map?) ?? const {};
      if (m['type'] == 'relation' && tags['type'] == 'person') {
        persons.add(m);
      } else if (tags['cemetery'] == 'grave') {
        graves['${m['type']}/${m['id']}'] = m;
      }
    }
    final peopleOf = <String, List<PersonGuess>>{};
    for (final r in persons) {
      final tags = Map<String, dynamic>.from(r['tags'] as Map);
      final guess = _personFromTags(tags);
      if (guess == null) continue;
      for (final mem in (r['members'] as List? ?? const [])) {
        final key = '${mem['type']}/${mem['ref']}';
        if (graves.containsKey(key)) peopleOf.putIfAbsent(key, () => []).add(guess);
      }
    }
    final out = <OsmGrave>[];
    for (final e in graves.entries) {
      final m = e.value;
      final tags = Map<String, dynamic>.from((m['tags'] as Map?) ?? const {});
      final lat = ((m['lat'] ?? m['center']?['lat']) as num?)?.toDouble();
      final lng = ((m['lon'] ?? m['center']?['lon']) as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final people = peopleOf[e.key] ?? [];
      if (people.isEmpty) {
        final g = _personFromTags(tags);
        if (g != null) people.add(g);
      }
      if (people.isEmpty && tags['inscription'] == null) continue; // grób bez żadnych danych
      out.add(OsmGrave(e.key, lat, lng, tags['inscription'] as String?, people));
    }
    return out;
  }

  static const _birthKeys = ['born', 'birth', 'date_of_birth', 'person:date_of_birth', 'dob', 'birth_date', 'person:born'];
  static const _deathKeys = ['died', 'death', 'date_of_death', 'person:date_of_death', 'dod', 'death_date', 'person:died'];

  static PersonGuess? _personFromTags(Map<String, dynamic> tags) {
    final name = (tags['name'] ?? tags['person:name']) as String?;
    if (name == null || name.trim().isEmpty) return null;
    PartialDate? date(List<String> keys) {
      for (final k in keys) {
        final v = tags[k];
        if (v is String && v.isNotEmpty) {
          final d = parseLooseDate(v);
          if (d != null) return d;
        }
      }
      return null;
    }

    final g = splitName(name.trim());
    if (g.firstName.isNotEmpty && g.lastName.isEmpty && !name.contains(' ')) {
      g
        ..lastName = g.firstName
        ..firstName = '';
    }
    g.birth = date(_birthKeys);
    g.death = date(_deathKeys);
    return g;
  }
}

/// Upraszcza obrys do co najwyżej [maxPts] punktów (co n-ty wierzchołek).
List<(double, double)> simplifyOutline(List<(double, double)> pts, int maxPts) {
  if (pts.length <= maxPts) return pts;
  final step = (pts.length / maxPts).ceil();
  return [for (var i = 0; i < pts.length; i += step) pts[i]];
}
