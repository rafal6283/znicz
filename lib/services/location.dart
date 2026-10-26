import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../logic/geo.dart';

class LocationService {
  /// Prosi o uprawnienia. Zwraca komunikat błędu albo null, gdy wszystko gra.
  static Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Lokalizacja w telefonie jest wyłączona. Włącz GPS i spróbuj ponownie.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return 'Bez dostępu do lokalizacji nie da się zapisać miejsca grobu.';
    if (perm == LocationPermission.deniedForever) {
      return 'Dostęp do lokalizacji jest zablokowany. Włącz go w ustawieniach telefonu dla aplikacji Znicz.';
    }
    return null;
  }

  static LocationSettings get _settings => Platform.isAndroid
      ? AndroidSettings(accuracy: LocationAccuracy.best, distanceFilter: 0, intervalDuration: const Duration(milliseconds: 1000))
      : AppleSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
        );

  static Stream<Position> stream() => Geolocator.getPositionStream(locationSettings: _settings);

  static Future<Position?> last() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> current({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.best, timeLimit: timeout));
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openSettings() => Geolocator.openAppSettings();
}

/// Zbiera odczyty GPS przez pewien czas i uśrednia je – pinezka przy grobie jest dokładniejsza
/// niż z pojedynczego odczytu.
class LocationSampler {
  final _samples = <GeoSample>[];
  StreamSubscription<Position>? _sub;
  final void Function(GeoSample? avg, int count, double? lastAcc) onUpdate;
  bool get running => _sub != null;
  int get count => _samples.length;

  LocationSampler(this.onUpdate);

  void start() {
    _samples.clear();
    _sub?.cancel();
    _sub = LocationService.stream().listen((p) {
      if (p.accuracy <= 0 || p.accuracy > 200) return;
      _samples.add(GeoSample(p.latitude, p.longitude, p.accuracy));
      // przy długim staniu trzymaj ostatnie 40 odczytów
      if (_samples.length > 40) _samples.removeAt(0);
      onUpdate(averageSamples(_samples), _samples.length, p.accuracy);
    }, onError: (_) {});
  }

  GeoSample? get result => averageSamples(_samples);

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
