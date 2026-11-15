import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../data/db.dart';
import '../logic/geo.dart';
import '../services/location.dart';
import 'common.dart';
import 'map_screen.dart';

/// Nagrywanie drogi od bramy cmentarza do grobu – rodzina potem idzie tą samą ścieżką.
class RouteRecordScreen extends StatefulWidget {
  final int graveId;
  const RouteRecordScreen({super.key, required this.graveId});
  @override
  State<RouteRecordScreen> createState() => _RouteRecordScreenState();
}

class _RouteRecordScreenState extends State<RouteRecordScreen> {
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  final _pts = <(double, double)>[];
  Position? _pos;
  bool _recording = false;
  String? _error;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _startGps();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    final err = await LocationService.ensurePermission();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _sub = LocationService.stream().listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      if (_recording && p.accuracy > 0 && p.accuracy <= 25) {
        final last = _pts.isEmpty ? null : _pts.last;
        if (last == null || distanceM(last.$1, last.$2, p.latitude, p.longitude) >= 2.5) {
          setState(() => _pts.add((p.latitude, p.longitude)));
        }
      }
      if (_follow) {
        try {
          _map.move(LatLng(p.latitude, p.longitude), _map.camera.zoom < 17 ? 18 : _map.camera.zoom);
        } catch (_) {}
      }
    }, onError: (e) => setState(() => _error = 'Błąd GPS: $e'));
  }

  void _start() {
    setState(() {
      _pts.clear();
      if (_pos != null && _pos!.accuracy <= 25) _pts.add((_pos!.latitude, _pos!.longitude));
      _recording = true;
    });
  }

  Future<void> _finish() async {
    if (_pts.length < 2) {
      snack(context, 'Za krótka trasa – przejdź kawałek, żeby GPS zapisał drogę');
      return;
    }
    final g = await AppDb.I.grave(widget.graveId);
    if (g == null || !mounted) return;
    final route = thinRoute(_pts);
    final end = route.last;
    var setLoc = !g.hasLocation;
    if (g.hasLocation) {
      final d = distanceM(g.lat!, g.lng!, end.$1, end.$2);
      if (d > 12) {
        setLoc = await confirm(context, 'Zaktualizować miejsce grobu?',
            'Trasa kończy się ${formatDistance(d)} od zapisanego miejsca grobu. Ustawić miejsce grobu na koniec trasy?',
            ok: 'Ustaw', destructive: false);
      }
    }
    g.route = route;
    if (setLoc) {
      g
        ..lat = end.$1
        ..lng = end.$2
        ..accuracy = _pos?.accuracy;
    }
    await AppDb.I.saveGrave(g);
    if (!mounted) return;
    snack(context, 'Zapisano drogę do grobu (${formatDistance(routeLength(route))})');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);
    final len = routeLength(_pts);
    return Scaffold(
      appBar: AppBar(title: const Text('Nagraj drogę do grobu')),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: me ?? const LatLng(52.07, 19.48),
                initialZoom: me == null ? 6 : 18,
                maxZoom: 22,
                onPositionChanged: (_, g) {
                  if (g && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                ...MapLayers.tiles(),
                if (_pts.length >= 2)
                  PolylineLayer(polylines: [
                    Polyline(points: [for (final p in _pts) LatLng(p.$1, p.$2)], strokeWidth: 5, color: cs.primary),
                  ]),
                MarkerLayer(markers: [
                  if (_pts.isNotEmpty)
                    Marker(
                      point: LatLng(_pts.first.$1, _pts.first.$2),
                      width: 26,
                      height: 26,
                      child: CircleAvatar(backgroundColor: cs.tertiary, child: const Icon(Icons.flag, size: 14, color: Colors.white)),
                    ),
                  if (me != null) myLocationMarker(me),
                ]),
                MapLayers.attribution(),
              ],
            ),
            if (!_follow)
              Positioned(
                right: 12,
                top: 12,
                child: FloatingActionButton.small(
                  heroTag: 'r_follow',
                  onPressed: () => setState(() => _follow = true),
                  child: const Icon(Icons.my_location),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_error != null)
                Text(_error!, style: TextStyle(color: cs.error))
              else if (!_recording)
                Text(
                  'Stań przy bramie (albo parkingu), od której zwykle idziecie, i dotknij „Start”. Idź do grobu – aplikacja zapisze drogę. '
                  'Przy grobie dotknij „Jestem przy grobie”.${_pos != null ? '\nDokładność GPS teraz: ±${_pos!.accuracy.round()} m' : '\nCzekam na GPS…'}',
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
              else
                Text('Nagrywam: ${formatDistance(len)} · ${_pts.length} punktów · GPS ±${_pos?.accuracy.round() ?? '?'} m',
                    style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (!_recording)
                FilledButton.icon(onPressed: _pos == null ? null : _start, icon: const Icon(Icons.fiber_manual_record), label: const Text('Start – jestem przy bramie'))
              else
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => setState(() => _recording = false), child: const Text('Przerwij'))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: FilledButton.icon(onPressed: _finish, icon: const Icon(Icons.flag), label: const Text('Jestem przy grobie'))),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
