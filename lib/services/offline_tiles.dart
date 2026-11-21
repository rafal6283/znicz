import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

/// Kafelek mapy (z, x, y).
typedef Tile = (int, int, int);

/// Numery kafelków (schemat XYZ) obejmujące prostokąt na danym zbliżeniu.
List<Tile> tilesForBox(double s, double w, double n, double e, int z) {
  final count = 1 << z;
  int tx(double lng) => ((lng + 180) / 360 * count).floor().clamp(0, count - 1);
  int ty(double lat) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * count).floor().clamp(0, count - 1);
  }

  final out = <Tile>[];
  for (var x = tx(w); x <= tx(e); x++) {
    for (var y = ty(n); y <= ty(s); y++) {
      out.add((z, x, y));
    }
  }
  return out;
}

/// Prostokąt cmentarza z marginesem (obrys albo punkt ± promień).
(double, double, double, double) cemeteryBox(Cemetery c, {double marginM = 150}) {
  final pts = c.outline.length >= 3 ? c.outline : [if (c.hasLocation) (c.lat!, c.lng!)];
  var s = pts.map((e) => e.$1).reduce(math.min), n = pts.map((e) => e.$1).reduce(math.max);
  var w = pts.map((e) => e.$2).reduce(math.min), e = pts.map((e) => e.$2).reduce(math.max);
  final m = c.outline.length >= 3 ? marginM : marginM + 250; // bez obrysu – większy zapas
  final dLat = m / 110540, dLng = m / (111320 * math.cos(s * math.pi / 180));
  return (s - dLat, w - dLng, n + dLat, e + dLng);
}

/// Mapy offline: kafelki zapisane na telefonie dla Twoich cmentarzy (na cmentarzach bywa słaby zasięg).
class OfflineTiles {
  static Directory? _dir;
  static const layers = {
    'osm': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'sat': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  };
  static const minZoom = 13;
  static const maxZoom = 19;

  static Future<void> init() async {
    if (_dir != null) return;
    try {
      _dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'kafelki'));
    } catch (_) {}
  }

  static File? file(String layer, int z, int x, int y) => _dir == null ? null : File(p.join(_dir!.path, layer, '$z', '$x', '$y.png'));

  static String url(String layer, int z, int x, int y) =>
      layers[layer]!.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');

  static List<Tile> tilesFor(Cemetery c) {
    final (s, w, n, e) = cemeteryBox(c);
    return [for (var z = minZoom; z <= maxZoom; z++) ...tilesForBox(s, w, n, e, z)];
  }

  static Future<Set<String>> _downloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('offline_cems') ?? const []).toSet();
  }

  static Future<bool> isDownloaded(Cemetery c) async => (await _downloaded()).contains(c.uid);

  static Future<int> downloadedCount() async => (await _downloaded()).length;

  /// Pobiera kafelki obu warstw (mapa i satelita). Zwraca liczbę pobranych nowych kafelków.
  static Future<int> download(Cemetery c, {void Function(int done, int total)? onProgress, bool Function()? cancelled}) async {
    await init();
    if (_dir == null || (!c.hasLocation && c.outline.length < 3)) return 0;
    final tiles = tilesFor(c);
    final jobs = [for (final l in layers.keys) for (final t in tiles) (l, t)];
    final client = http.Client();
    var done = 0, fresh = 0, failed = 0;
    try {
      // po 4 naraz – szybko, ale bez zasypywania serwerów
      for (var i = 0; i < jobs.length; i += 4) {
        if (cancelled?.call() == true) break;
        await Future.wait(jobs.skip(i).take(4).map((j) async {
          final (layer, (z, x, y)) = j;
          final f = file(layer, z, x, y)!;
          if (!await f.exists()) {
            try {
              final r = await client
                  .get(Uri.parse(url(layer, z, x, y)), headers: {'User-Agent': 'Znicz/1.0 (pl.znicz.app; mapa offline cmentarza)'})
                  .timeout(const Duration(seconds: 20));
              if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
                await f.parent.create(recursive: true);
                await f.writeAsBytes(r.bodyBytes, flush: true);
                fresh++;
              } else {
                failed++;
              }
            } catch (_) {
              failed++;
            }
          }
          done++;
        }));
        onProgress?.call(done, jobs.length);
      }
    } finally {
      client.close();
    }
    if (cancelled?.call() != true && failed < jobs.length / 10) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('offline_cems', {...await _downloaded(), c.uid}.toList());
    }
    if (failed > jobs.length / 2) throw const HttpException('Nie udało się pobrać mapy – sprawdź internet');
    return fresh;
  }

  static Future<int> sizeBytes() async {
    await init();
    if (_dir == null || !await _dir!.exists()) return 0;
    var total = 0;
    await for (final e in _dir!.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  static Future<void> clear() async {
    await init();
    if (_dir != null && await _dir!.exists()) await _dir!.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_cems');
  }
}

/// Dostawca kafelków: najpierw zapisane na telefonie, potem z internetu.
class OfflineFirstTileProvider extends TileProvider {
  final String layer;
  final NetworkTileProvider _net = NetworkTileProvider();
  OfflineFirstTileProvider(this.layer);

  // flutter_map 8: NetworkTileProvider ładuje kafle tylko przez getImageWithCancelLoadingSupport,
  // a jego getImage rzuca UnimplementedError – stąd była pusta, szara mapa.
  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(TileCoordinates coordinates, TileLayer options, Future<void> cancelLoading) {
    final f = OfflineTiles.file(layer, coordinates.z, coordinates.x, coordinates.y);
    if (f != null && f.existsSync()) return FileImage(f);
    return _net.getImageWithCancelLoadingSupport(coordinates, options, cancelLoading);
  }

  // Jeden dostawca jest wspólny dla wszystkich map w aplikacji (MapLayers). flutter_map zamyka dostawcę
  // przy zamknięciu ekranu z mapą – zamknięty klient HTTP nie pobierał już kafli i każda kolejna mapa
  // była pusta. Dlatego nie zamykamy go (żyje tyle co aplikacja).
  @override
  void dispose() {}
}

String formatBytes(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).round()} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
