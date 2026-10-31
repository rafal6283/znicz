import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/logic/geo.dart';
import 'package:znicz/data/models.dart';
import 'package:znicz/ui/grave_years.dart';

void main() {
  test('przystanki: groby na jednym cmentarzu łączone', () {
    final s = routeStops([(52.0, 21.0), (52.0001, 21.0001), (52.1, 21.1), (52.0, 21.0)], [1, 1, 2, 1]);
    expect(s.length, 3);
    expect(routeLength(s), greaterThan(20000));
  });

  test('link nawigacji', () {
    final u = directionsUrl([(52.0, 21.0), (52.1, 21.1)], origin: (51.9, 20.9))!;
    expect(u.queryParameters['destination'], '52.100000,21.100000');
    expect(u.queryParameters['waypoints'], '52.000000,21.000000');
    expect(u.queryParameters['origin'], '51.900000,20.900000');
    expect(directionsUrl([]), isNull);
  });

  test('zdjęcia według lat', () {
    final p = [
      GravePhoto(graveId: 1, path: 'a', taken: DateTime(2023, 11, 1).millisecondsSinceEpoch),
      GravePhoto(graveId: 1, path: 'b', taken: DateTime(2026, 11, 1).millisecondsSinceEpoch),
      GravePhoto(graveId: 1, path: 'c', taken: DateTime(2026, 5, 1).millisecondsSinceEpoch),
    ];
    final y = photosByYear(p);
    expect(y.keys.toList(), [2026, 2023]);
    expect(y[2026]!.first.path, 'b');
  });

  test('pole visitor w mapie grobu', () {
    final g = Grave(visitor: 'Ania');
    expect(Grave.fromMap(g.toMap()).visitor, 'Ania');
  });
}
