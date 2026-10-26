import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/data/models.dart';
import 'package:znicz/logic/geo.dart';
import 'package:znicz/services/osm.dart';

void main() {
  const square = [(52.0, 21.0), (52.0, 21.01), (52.01, 21.01), (52.01, 21.0)];

  test('punkt w wielokącie', () {
    expect(pointInPolygon(52.005, 21.005, square), isTrue);
    expect(pointInPolygon(52.02, 21.005, square), isFalse);
    expect(pointInPolygon(52.0, 21.0, const [(52.0, 21.0)]), isFalse);
  });

  test('obrys w bazie w obie strony', () {
    final s = encodeOutline(square)!;
    expect(decodeOutline(s), square);
    expect(decodeOutline(null), isEmpty);
    expect(encodeOutline(const []), isNull);
  });

  test('cmentarze z Overpass', () {
    final json = {
      'elements': [
        {
          'type': 'way',
          'id': 1,
          'tags': {'landuse': 'cemetery', 'religion': 'christian', 'denomination': 'roman_catholic'},
          'geometry': [
            {'lat': 52.0, 'lon': 21.0},
            {'lat': 52.0, 'lon': 21.01},
            {'lat': 52.01, 'lon': 21.01},
            {'lat': 52.01, 'lon': 21.0},
            {'lat': 52.0, 'lon': 21.0},
          ],
        },
        // ten sam cmentarz oznaczony drugi raz jako mniejszy obszar wewnątrz
        {
          'type': 'way',
          'id': 2,
          'tags': {'amenity': 'grave_yard'},
          'geometry': [
            {'lat': 52.004, 'lon': 21.004},
            {'lat': 52.004, 'lon': 21.006},
            {'lat': 52.006, 'lon': 21.005},
          ],
        },
        {
          'type': 'node',
          'id': 3,
          'lat': 52.1,
          'lon': 21.1,
          'tags': {'amenity': 'grave_yard', 'name': 'Cmentarz wojenny', 'cemetery': 'war_cemetery'},
        },
      ],
    };
    final r = Osm.parseCemeteries(json, 52.005, 21.005);
    expect(r.length, 2);
    expect(r.first.osmId, 'way/1');
    expect(r.first.distance, 0);
    expect(r.first.kind, 'parafialny');
    expect(r.first.label, 'Cmentarz parafialny');
    expect(r.first.areaHa, greaterThan(70));
    expect(r[1].label, 'Cmentarz wojenny');
    expect(r[1].kind, 'wojskowy');
  });

  test('groby z relacjami osób', () {
    final json = {
      'elements': [
        {'type': 'node', 'id': 10, 'lat': 52.005, 'lon': 21.005, 'tags': {'cemetery': 'grave', 'inscription': 'Ś.P.'}},
        {'type': 'node', 'id': 11, 'lat': 52.006, 'lon': 21.006, 'tags': {'cemetery': 'grave', 'name': 'Jan Nowak', 'born': '1901-02-03', 'died': '1970'}},
        {'type': 'node', 'id': 12, 'lat': 52.007, 'lon': 21.007, 'tags': {'cemetery': 'grave'}},
        {
          'type': 'relation',
          'id': 100,
          'tags': {'type': 'person', 'name': 'Anna Kowalska', 'born': '1920', 'died': '1990-05-06'},
          'members': [
            {'type': 'node', 'ref': 10, 'role': 'tomb'},
          ],
        },
      ],
    };
    final g = Osm.parseGraves(json);
    expect(g.length, 2);
    final a = g.firstWhere((x) => x.osmId == 'node/10');
    expect(a.people.single.lastName, 'Kowalska');
    expect(a.people.single.death, const PartialDate(1990, 5, 6));
    expect(a.inscription, 'Ś.P.');
    final b = g.firstWhere((x) => x.osmId == 'node/11');
    expect(b.people.single.firstName, 'Jan');
    expect(b.people.single.birth, const PartialDate(1901, 2, 3));
  });

  test('upraszczanie obrysu', () {
    final pts = [for (var i = 0; i < 1000; i++) (52.0 + i * 1e-5, 21.0)];
    expect(simplifyOutline(pts, 300).length, lessThanOrEqualTo(300));
  });
}
