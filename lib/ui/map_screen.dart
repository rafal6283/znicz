import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/location.dart';
import 'common.dart';
import 'graves_list.dart';
import 'nearby_cemeteries.dart';

const _poland = LatLng(52.07, 19.48);

/// Warstwy mapy: OpenStreetMap albo zdjęcia satelitarne (na cmentarzu lepiej widać alejki).
class MapLayers {
  static bool satellite = false;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    satellite = p.getBool('map_sat') ?? false;
  }

  static Future<void> toggle() async {
    satellite = !satellite;
    final p = await SharedPreferences.getInstance();
    await p.setBool('map_sat', satellite);
  }

  static List<Widget> tiles() => [
        if (!satellite)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'pl.znicz.app',
            maxNativeZoom: 19,
            maxZoom: 22,
          )
        else
          TileLayer(
            urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'pl.znicz.app',
            maxNativeZoom: 19,
            maxZoom: 22,
          ),
      ];

  static Widget attribution() => RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          if (!satellite)
            TextSourceAttribution('OpenStreetMap', onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')))
          else
            const TextSourceAttribution('Esri, Maxar, Earthstar Geographics'),
        ],
      );
}

Marker myLocationMarker(LatLng p, {double? accuracy}) => Marker(
      point: p,
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E88E5),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      ),
    );

class GravePin extends StatelessWidget {
  final Color color;
  final IconData icon;
  const GravePin({super.key, required this.color, this.icon = Icons.local_fire_department});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)]),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      CustomPaint(size: const Size(10, 8), painter: _Tip(color)),
    ]);
  }
}

class _Tip extends CustomPainter {
  final Color c;
  _Tip(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    canvas.drawPath(p, Paint()..color = c);
  }

  @override
  bool shouldRepaint(_Tip o) => o.c != c;
}

/// Mapa wszystkich grobów i cmentarzy.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  List<GraveView> _graves = [];
  List<Cemetery> _cems = [];
  bool _loaded = false;
  GraveView? _selected;
  LatLng? _me;

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    MapLayers.load().then((_) => _load());
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final g = await AppDb.I.graveViews();
    final c = await AppDb.I.cemeteries();
    if (!mounted) return;
    setState(() {
      _graves = g;
      _cems = c;
      _loaded = true;
      if (_selected != null) {
        final s = g.where((x) => x.grave.id == _selected!.grave.id);
        _selected = s.isEmpty ? null : s.first;
      }
    });
  }

  List<LatLng> get _points => [
        for (final g in _graves)
          if (g.grave.hasLocation) LatLng(g.grave.lat!, g.grave.lng!),
        for (final c in _cems)
          if (c.hasLocation && !_graves.any((g) => g.grave.cemeteryId == c.id && g.grave.hasLocation)) LatLng(c.lat!, c.lng!),
      ];

  Future<void> _locate() async {
    final err = await LocationService.ensurePermission();
    if (err != null) {
      if (mounted) snack(context, err);
      return;
    }
    final p = await LocationService.current(timeout: const Duration(seconds: 10)) ?? await LocationService.last();
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    _map.move(_me!, 17);
  }

  void _fitAll() {
    final pts = _points;
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 17);
    } else {
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(56), maxZoom: 18));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pts = _points;
    final options = MapOptions(
      initialCenter: pts.isEmpty ? _poland : pts.first,
      initialZoom: pts.isEmpty ? 6 : 16,
      initialCameraFit: pts.length > 1 ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(56), maxZoom: 18) : null,
      maxZoom: 22,
      onTap: (_, __) => setState(() => _selected = null),
    );
    final markers = <Marker>[
      for (final c in _cems)
        if (c.hasLocation)
          Marker(
            point: LatLng(c.lat!, c.lng!),
            width: 40,
            height: 46,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => snack(context, c.label),
              child: GravePin(color: cs.tertiary, icon: Icons.park_outlined),
            ),
          ),
      for (final g in _graves)
        if (g.grave.hasLocation)
          Marker(
            point: LatLng(g.grave.lat!, g.grave.lng!),
            width: 40,
            height: 46,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => setState(() => _selected = g),
              child: GravePin(color: _selected?.grave.id == g.grave.id ? cs.error : cs.primary),
            ),
          ),
      if (_me != null) myLocationMarker(_me!),
    ];
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: options,
          children: [
            ...MapLayers.tiles(),
            cemeteryPolygons(_cems.map((c) => c.outline), cs.tertiary),
            MarkerLayer(markers: markers),
            MapLayers.attribution(),
          ],
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FloatingActionButton.small(
                  heroTag: 'm_layer',
                  tooltip: MapLayers.satellite ? 'Mapa' : 'Satelita',
                  onPressed: () async {
                    await MapLayers.toggle();
                    setState(() {});
                  },
                  child: Icon(MapLayers.satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(heroTag: 'm_fit', tooltip: 'Pokaż wszystkie', onPressed: _fitAll, child: const Icon(Icons.zoom_out_map)),
                const SizedBox(height: 8),
                FloatingActionButton.small(heroTag: 'm_me', tooltip: 'Moja pozycja', onPressed: _locate, child: const Icon(Icons.my_location)),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'm_near',
                  tooltip: 'Cmentarze w pobliżu',
                  onPressed: () {
                    final c = _map.camera.center;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => NearbyCemeteriesScreen(lat: _me != null ? null : c.latitude, lng: _me != null ? null : c.longitude)));
                  },
                  child: const Icon(Icons.travel_explore),
                ),
              ]),
            ),
          ),
        ),
        if (pts.isEmpty)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Card(
                margin: const EdgeInsets.fromLTRB(16, 16, 72, 0),
                child: const Padding(padding: EdgeInsets.all(12), child: Text('Groby z zapisanym położeniem pojawią się na mapie.')),
              ),
            ),
          ),
        if (_selected != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Card(
              margin: const EdgeInsets.all(12),
              elevation: 3,
              child: GraveTile(_selected!),
            ),
          ),
      ]),
    );
  }
}

/// Wybór punktu na mapie: celownik w środku ekranu.
class MapPickerScreen extends StatefulWidget {
  final LatLng? initial;
  final String title;
  const MapPickerScreen({super.key, this.initial, this.title = 'Wskaż miejsce'});
  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  LatLng? _me;

  @override
  void initState() {
    super.initState();
    MapLayers.load().then((_) => setState(() {}));
    if (widget.initial == null) _locate(move: true);
  }

  Future<void> _locate({bool move = true}) async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final err = await LocationService.ensurePermission();
      if (err != null) return;
    }
    final p = await LocationService.last() ?? await LocationService.current(timeout: const Duration(seconds: 10));
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    if (move) _map.move(_me!, 18);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(initialCenter: widget.initial ?? _poland, initialZoom: widget.initial == null ? 6 : 19, maxZoom: 22),
          children: [
            ...MapLayers.tiles(),
            if (_me != null) MarkerLayer(markers: [myLocationMarker(_me!)]),
            MapLayers.attribution(),
          ],
        ),
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 46),
              child: GravePin(color: cs.error),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(children: [
            FloatingActionButton.small(
              heroTag: 'p_layer',
              onPressed: () async {
                await MapLayers.toggle();
                setState(() {});
              },
              child: Icon(MapLayers.satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'p_me', onPressed: () => _locate(), child: const Icon(Icons.my_location)),
          ]),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, _map.camera.center),
              icon: const Icon(Icons.check),
              label: const Text('Tu jest to miejsce'),
            ),
          ),
        ),
      ]),
    );
  }
}
