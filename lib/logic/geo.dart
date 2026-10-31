import 'dart:math';

const _earth = 6371000.0;

double _rad(double d) => d * pi / 180;
double _deg(double r) => r * 180 / pi;

/// Odległość w metrach (haversine).
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) + cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * _earth * atan2(sqrt(a), sqrt(1 - a));
}

/// Kierunek z punktu 1 do punktu 2 w stopniach (0 = północ, zgodnie z ruchem wskazówek).
double bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final y = sin(_rad(lng2 - lng1)) * cos(_rad(lat2));
  final x = cos(_rad(lat1)) * sin(_rad(lat2)) - sin(_rad(lat1)) * cos(_rad(lat2)) * cos(_rad(lng2 - lng1));
  return (_deg(atan2(y, x)) + 360) % 360;
}

/// Różnica kątów w zakresie -180..180.
double angleDiff(double a, double b) => ((a - b + 540) % 360) - 180;

String formatDistance(double m) {
  if (m < 1) return '< 1 m';
  if (m < 100) return '${m.round()} m';
  if (m < 1000) return '${(m / 5).round() * 5} m';
  if (m < 10000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${(m / 1000).round()} km';
}

const _dirs = ['północ', 'północny wschód', 'wschód', 'południowy wschód', 'południe', 'południowy zachód', 'zachód', 'północny zachód'];

String compassWord(double bearing) => _dirs[((bearing % 360) / 45).round() % 8];

class GeoSample {
  final double lat;
  final double lng;
  final double accuracy;
  GeoSample(this.lat, this.lng, this.accuracy);
}

/// Uśrednia serię odczytów GPS: odrzuca słabe odczyty, waży 1/dokładność².
/// Zwraca uśrednioną pozycję i szacowaną dokładność.
GeoSample? averageSamples(List<GeoSample> samples) {
  if (samples.isEmpty) return null;
  final best = samples.map((s) => s.accuracy).reduce(min);
  // odczyty dużo gorsze od najlepszego tylko psują wynik
  final good = samples.where((s) => s.accuracy <= max(best * 2.5, best + 5)).toList();
  var wSum = 0.0, lat = 0.0, lng = 0.0;
  for (final s in good) {
    final acc = max(s.accuracy, 1.0);
    final w = 1 / (acc * acc);
    wSum += w;
    lat += s.lat * w;
    lng += s.lng * w;
  }
  lat /= wSum;
  lng /= wSum;
  // dokładność uśrednionej pozycji: połączenie błędów, ale nie lepiej niż połowa najlepszego odczytu
  final combined = sqrt(1 / wSum);
  return GeoSample(lat, lng, max(combined, best / 2));
}

/// Kolejność odwiedzania punktów: najbliższy sąsiad od startu + poprawa 2-opt.
List<int> visitOrder(List<(double, double)> points, {(double, double)? start}) {
  final n = points.length;
  if (n <= 1) return List.generate(n, (i) => i);
  double d(int a, int b) => distanceM(points[a].$1, points[a].$2, points[b].$1, points[b].$2);
  final left = List.generate(n, (i) => i).toSet();
  final order = <int>[];
  int cur;
  if (start != null) {
    cur = left.reduce((a, b) => distanceM(start.$1, start.$2, points[a].$1, points[a].$2) <= distanceM(start.$1, start.$2, points[b].$1, points[b].$2) ? a : b);
  } else {
    cur = 0;
  }
  order.add(cur);
  left.remove(cur);
  while (left.isNotEmpty) {
    final c = cur;
    cur = left.reduce((a, b) => d(c, a) <= d(c, b) ? a : b);
    order.add(cur);
    left.remove(cur);
  }
  // 2-opt (trasa otwarta)
  var improved = true;
  var guard = 0;
  while (improved && guard++ < 50) {
    improved = false;
    for (var i = 0; i < n - 2; i++) {
      for (var k = i + 1; k < n - 1; k++) {
        final a = order[i], b = order[i + 1], c = order[k], e = order[k + 1];
        if (d(a, c) + d(b, e) < d(a, b) + d(c, e) - 0.01) {
          final rev = order.sublist(i + 1, k + 1).reversed.toList();
          order.replaceRange(i + 1, k + 1, rev);
          improved = true;
        }
      }
    }
  }
  return order;
}

/// Czy punkt leży wewnątrz wielokąta (obrysu cmentarza). Algorytm promienia.
bool pointInPolygon(double lat, double lng, List<(double, double)> poly) {
  if (poly.length < 3) return false;
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final (yi, xi) = poly[i];
    final (yj, xj) = poly[j];
    if ((yi > lat) != (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/// Środek ciężkości punktów (wystarczający dla małych obszarów jak cmentarz).
(double, double) centroid(List<(double, double)> pts) {
  var a = 0.0, b = 0.0;
  for (final p in pts) {
    a += p.$1;
    b += p.$2;
  }
  return (a / pts.length, b / pts.length);
}

/// Odległość od punktu do obszaru: 0 wewnątrz, inaczej do najbliższego wierzchołka.
double distanceToArea(double lat, double lng, List<(double, double)> poly, double cLat, double cLng) {
  if (poly.length >= 3) {
    if (pointInPolygon(lat, lng, poly)) return 0;
    return poly.map((p) => distanceM(lat, lng, p.$1, p.$2)).reduce(min);
  }
  return distanceM(lat, lng, cLat, cLng);
}

double cosDeg(double d) => cos(_rad(d));

/// Przystanki trasy samochodowej: kolejne punkty na tym samym cmentarzu ([keys] równe) łączone w jeden.
List<(double, double)> routeStops(List<(double, double)> points, List<Object?> keys) {
  final out = <(double, double)>[];
  Object? last;
  for (var i = 0; i < points.length; i++) {
    final k = keys[i];
    if (i > 0 && k != null && k == last) continue;
    out.add(points[i]);
    last = k;
  }
  return out;
}

/// Długość trasy w linii prostej (m).
double routeLength(List<(double, double)> stops, {(double, double)? start}) {
  var sum = 0.0;
  var prev = start;
  for (final s in stops) {
    if (prev != null) sum += distanceM(prev.$1, prev.$2, s.$1, s.$2);
    prev = s;
  }
  return sum;
}

/// Link do nawigacji Google Maps przez kolejne przystanki (do 9 punktów pośrednich).
Uri? directionsUrl(List<(double, double)> stops, {(double, double)? origin}) {
  if (stops.isEmpty) return null;
  String f((double, double) p) => '${p.$1.toStringAsFixed(6)},${p.$2.toStringAsFixed(6)}';
  final s = stops.length > 10 ? stops.sublist(0, 10) : stops;
  final mid = s.sublist(0, s.length - 1);
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    if (origin != null) 'origin': f(origin),
    'destination': f(s.last),
    if (mid.isNotEmpty) 'waypoints': mid.map(f).join('|'),
    'travelmode': 'driving',
  });
}
