import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/models.dart';
import '../logic/geo.dart';
import '../services/location.dart';
import 'cemetery.dart';
import 'common.dart';
import 'map_screen.dart';
import 'nearby_cemeteries.dart';
import 'visit_edit.dart';

/// Prowadzenie do grobu: strzałka kompasu + odległość + mapa (jak w BillionGraves).
class CompassScreen extends StatefulWidget {
  final GraveView grave;
  const CompassScreen({super.key, required this.grave});
  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compSub;
  Position? _pos;
  double? _heading; // kierunek telefonu
  double _smoothHeading = 0;
  bool _noCompass = false;
  String? _error;
  final _map = MapController();
  bool _follow = true;
  bool _arrivedShown = false;

  double get _tLat => widget.grave.grave.lat!;
  double get _tLng => widget.grave.grave.lng!;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final err = await LocationService.ensurePermission();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _posSub = LocationService.stream().listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      if (_follow) _fit();
      if (_distance != null && _distance! <= _arriveRadius && !_arrivedShown) {
        _arrivedShown = true;
      }
    }, onError: (e) => setState(() => _error = 'Błąd GPS: $e'));
    final events = FlutterCompass.events;
    if (events == null) {
      setState(() => _noCompass = true);
    } else {
      _compSub = events.listen((e) {
        if (!mounted || e.heading == null) return;
        final h = (e.heading! + 360) % 360;
        // wygładzanie (bez skoku przez 0/360)
        _smoothHeading = (_smoothHeading + angleDiff(h, _smoothHeading) * 0.25 + 360) % 360;
        setState(() => _heading = _smoothHeading);
      });
    }
  }

  void _fit() {
    final p = _pos;
    if (p == null) return;
    try {
      final b = LatLngBounds.fromPoints([LatLng(p.latitude, p.longitude), LatLng(_tLat, _tLng)]);
      _map.fitCamera(CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(48), maxZoom: 20));
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compSub?.cancel();
    super.dispose();
  }

  double? get _distance => _pos == null ? null : distanceM(_pos!.latitude, _pos!.longitude, _tLat, _tLng);
  double? get _bearing => _pos == null ? null : bearingDeg(_pos!.latitude, _pos!.longitude, _tLat, _tLng);

  /// Promień „jesteś na miejscu”: zależy od dokładności GPS w tej chwili i przy zapisie grobu.
  double get _arriveRadius => max(5, min(15, ((_pos?.accuracy ?? 8) + (widget.grave.grave.accuracy ?? 5)) * 0.8));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = widget.grave;
    final d = _distance;
    final b = _bearing;
    final arrived = d != null && d <= _arriveRadius;
    final heading = _heading ?? (_pos != null && _pos!.speed > 0.7 ? _pos!.heading : null);
    final rel = (b != null && heading != null) ? angleDiff(b, heading) : null;

    Widget top;
    if (_error != null) {
      top = Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error)));
    } else if (_pos == null) {
      top = const Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Szukam sygnału GPS…')]);
    } else if (arrived) {
      top = Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department, size: 72, color: cs.primary),
        const SizedBox(height: 8),
        Text('Jesteś przy grobie', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('w promieniu ok. ${d.round()} m – rozejrzyj się', style: TextStyle(color: cs.onSurfaceVariant)),
      ]);
    } else {
      top = Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 190,
          height: 190,
          child: Stack(alignment: Alignment.center, children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, color: cs.surfaceContainerHighest)),
            if (rel != null)
              AnimatedRotation(
                turns: rel / 360,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.navigation, size: 130, color: rel.abs() < 15 ? Colors.green.shade600 : cs.primary),
              )
            else
              Icon(Icons.explore_outlined, size: 96, color: cs.onSurfaceVariant),
          ]),
        ),
        const SizedBox(height: 12),
        Text(formatDistance(d!), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          rel == null
              ? 'Idź na ${compassWord(b!)}${_noCompass ? ' (brak kompasu w telefonie)' : ' – obróć telefon płasko'}'
              : (rel.abs() < 15 ? 'Prosto przed Tobą' : (rel > 0 ? 'Skręć w prawo' : 'Skręć w lewo')),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text('dokładność GPS ±${_pos!.accuracy.round()} m', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]);
    }

    final me = _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);
    return Scaffold(
      appBar: AppBar(title: Text(g.title, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(
          flex: 5,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(child: top),
            const SizedBox(height: 16),
            if (d != null && d > 1500)
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => openExternalNavigation(context, _tLat, _tLng, label: g.title),
                  icon: const Icon(Icons.directions_car_outlined),
                  label: const Text('To daleko – nawiguj samochodem'),
                ),
              ),
            if (arrived || (d != null && d < 40)) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PhotoThumb(g.cover, size: 96),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (g.grave.placeLabel.isNotEmpty) Text(g.grave.placeLabel),
                        if ((g.grave.directions ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(g.grave.directions!, style: TextStyle(color: cs.onSurfaceVariant))),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (arrived)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => VisitEditScreen(graveId: g.grave.id!))),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Zapisz wizytę'),
                  ),
                ),
            ] else if ((g.grave.directions ?? '').isNotEmpty)
              ListTile(leading: const Icon(Icons.signpost_outlined), title: Text(g.grave.directions!)),
          ]),
        ),
        Expanded(
          flex: 4,
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: LatLng(_tLat, _tLng),
                initialZoom: 18,
                maxZoom: 22,
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                ...MapLayers.tiles(),
                if (g.cemetery != null) cemeteryPolygons([g.cemetery!.outline], cs.tertiary),
                if (me != null)
                  PolylineLayer(polylines: [
                    Polyline(points: [me, LatLng(_tLat, _tLng)], strokeWidth: 3, color: cs.primary.withValues(alpha: 0.7), pattern: StrokePattern.dashed(segments: const [8, 6])),
                  ]),
                if (me != null && _pos != null)
                  CircleLayer(circles: [
                    CircleMarker(point: me, radius: _pos!.accuracy, useRadiusInMeter: true, color: const Color(0x221E88E5), borderColor: const Color(0x661E88E5), borderStrokeWidth: 1),
                  ]),
                MarkerLayer(markers: [
                  Marker(point: LatLng(_tLat, _tLng), width: 40, height: 46, alignment: Alignment.topCenter, child: GravePin(color: cs.primary)),
                  if (me != null) myLocationMarker(me),
                ]),
                MapLayers.attribution(),
              ],
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Column(children: [
                FloatingActionButton.small(
                  heroTag: 'c_layer',
                  onPressed: () async {
                    await MapLayers.toggle();
                    setState(() {});
                  },
                  child: Icon(MapLayers.satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
                ),
                if (!_follow) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'c_follow',
                    onPressed: () {
                      setState(() => _follow = true);
                      _fit();
                    },
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
