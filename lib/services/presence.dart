import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/geo.dart';
import 'location.dart';

/// Cmentarz, na którego terenie jest teraz telefon (sprawdzane po otwarciu aplikacji, bez pytania o uprawnienia).
class CemeteryPresence {
  static final current = ValueNotifier<Cemetery?>(null);
  static final dismissed = <String>{}; // uid cmentarzy zamkniętych w tej sesji

  /// Czy punkt jest na terenie cmentarza: w obrysie albo do 120 m od punktu cmentarza bez obrysu.
  static Cemetery? cemeteryAt(List<Cemetery> cems, double lat, double lng) {
    for (final c in cems) {
      if (c.outline.length >= 3 && pointInPolygon(lat, lng, c.outline)) return c;
    }
    for (final c in cems) {
      if (c.outline.length < 3 && c.hasLocation && distanceM(lat, lng, c.lat!, c.lng!) < 120) return c;
    }
    return null;
  }

  static Future<void> check() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
      final p = await LocationService.current(timeout: const Duration(seconds: 8)) ?? await LocationService.last();
      if (p == null) return;
      // pozycja sprzed kwadransa nie świadczy, że ktoś stoi na cmentarzu
      if (DateTime.now().difference(p.timestamp).inMinutes > 15) return;
      final c = cemeteryAt(await AppDb.I.cemeteries(), p.latitude, p.longitude);
      current.value = c != null && !dismissed.contains(c.uid) ? c : null;
    } catch (_) {}
  }
}
