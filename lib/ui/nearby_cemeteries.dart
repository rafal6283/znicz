import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../data/db.dart';
import '../data/models.dart';
import '../logic/geo.dart';
import '../services/location.dart';
import '../services/osm.dart';
import 'cemetery.dart';
import 'common.dart';
import 'map_screen.dart';

/// Obrysy cmentarzy na mapie (z OpenStreetMap).
PolygonLayer cemeteryPolygons(Iterable<List<(double, double)>> outlines, Color color) => PolygonLayer(polygons: [
      for (final o in outlines)
        if (o.length >= 3)
          Polygon(
            points: [for (final p in o) LatLng(p.$1, p.$2)],
            color: color.withValues(alpha: 0.12),
            borderColor: color.withValues(alpha: 0.8),
            borderStrokeWidth: 2,
          ),
    ]);

/// Wyszukiwanie cmentarzy w okolicy w OpenStreetMap i dodawanie ich jednym dotknięciem.
class NearbyCemeteriesScreen extends StatefulWidget {
  final double? lat;
  final double? lng;
  const NearbyCemeteriesScreen({super.key, this.lat, this.lng});
  @override
  State<NearbyCemeteriesScreen> createState() => _NearbyCemeteriesScreenState();
}

class _NearbyCemeteriesScreenState extends State<NearbyCemeteriesScreen> {
  final _map = MapController();
  double? _lat, _lng;
  int _radius = 5000;
  bool _loading = false;
  String? _error;
  List<OsmCemetery> _found = [];
  Map<String, Cemetery> _added = {}; // osmId → cmentarz w aplikacji
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.lat;
    _lng = widget.lng;
    _start();
  }

  Future<void> _start() async {
    await _loadAdded();
    if (_lat == null) {
      final err = await LocationService.ensurePermission();
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      final p = await LocationService.last() ?? await LocationService.current(timeout: const Duration(seconds: 12));
      if (p == null) {
        setState(() => _error = 'Nie udało się ustalić pozycji');
        return;
      }
      _lat = p.latitude;
      _lng = p.longitude;
    }
    await _search();
  }

  Future<void> _loadAdded() async {
    final cems = await AppDb.I.cemeteries();
    _added = {for (final c in cems) if (c.osmId != null) c.osmId!: c};
  }

  Future<void> _search() async {
    if (_lat == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Osm.cemeteriesNear(_lat!, _lng!, radiusM: _radius);
      if (!mounted) return;
      setState(() => _found = r);
      _fit();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fit() {
    if (!_mapReady) return;
    final pts = <LatLng>[LatLng(_lat!, _lng!), for (final c in _found.take(8)) LatLng(c.lat, c.lng)];
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 14);
      } else {
        _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(32), maxZoom: 17));
      }
    } catch (_) {}
  }

  Future<void> _add(OsmCemetery o) async {
    final c = Cemetery(
      name: o.label,
      town: o.town,
      kind: o.kind,
      lat: o.lat,
      lng: o.lng,
      osmId: o.osmId,
      outline: o.outline,
      address: [o.tags['addr:street'], o.tags['addr:housenumber']].whereType<String>().join(' ').trim().isEmpty
          ? null
          : [o.tags['addr:street'], o.tags['addr:housenumber']].whereType<String>().join(' '),
      phone: o.tags['phone'] ?? o.tags['contact:phone'],
      hours: o.tags['opening_hours'],
      searchUrl: o.tags['website'] ?? o.tags['contact:website'],
    );
    await AppDb.I.saveCemetery(c);
    await _loadAdded();
    if (!mounted) return;
    setState(() {});
    final edit = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Dodano: ${c.name}'),
        content: Text(o.name == null
            ? 'W OpenStreetMap ten cmentarz nie ma nazwy – warto ją wpisać (np. „Cmentarz parafialny”) i uzupełnić miejscowość.'
            : 'Możesz od razu sprawdzić, czy ktoś opisał na mapie groby na tym cmentarzu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Gotowe')),
          if (o.name == null) TextButton(onPressed: () => Navigator.pop(d, 'edit'), child: const Text('Popraw nazwę')),
          FilledButton(onPressed: () => Navigator.pop(d, 'graves'), child: const Text('Groby z mapy')),
        ],
      ),
    );
    if (!mounted) return;
    if (edit == 'edit') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryEditScreen(cemetery: c)));
    } else if (edit == 'graves') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => OsmGravesScreen(cemetery: c)));
    }
    await _loadAdded();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cmentarze w pobliżu')),
      body: Column(children: [
        SizedBox(
          height: 230,
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _lat == null ? const LatLng(52.07, 19.48) : LatLng(_lat!, _lng!),
                initialZoom: _lat == null ? 6 : 13,
                onMapReady: () {
                  _mapReady = true;
                  if (_found.isNotEmpty) _fit();
                },
              ),
              children: [
                ...MapLayers.tiles(),
                cemeteryPolygons(_found.map((c) => c.outline), cs.tertiary),
                MarkerLayer(markers: [
                  for (final c in _found)
                    Marker(
                      point: LatLng(c.lat, c.lng),
                      width: 40,
                      height: 46,
                      alignment: Alignment.topCenter,
                      child: GravePin(color: _added.containsKey(c.osmId) ? cs.primary : cs.tertiary, icon: Icons.park_outlined),
                    ),
                  if (_lat != null) myLocationMarker(LatLng(_lat!, _lng!)),
                ]),
                MapLayers.attribution(),
              ],
            ),
            if (_loading) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator()),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(spacing: 8, children: [
            for (final r in [2000, 5000, 10000, 25000])
              ChoiceChip(
                label: Text('${r ~/ 1000} km'),
                selected: _radius == r,
                onSelected: (_) {
                  setState(() => _radius = r);
                  _search();
                },
              ),
          ]),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: cs.error))))
              : _found.isEmpty
                  ? Center(child: Text(_loading ? 'Szukam w OpenStreetMap…' : 'Nie znaleziono cmentarzy w tym promieniu'))
                  : ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                      for (final c in _found)
                        ListTile(
                          leading: Icon(Icons.park_outlined, color: _added.containsKey(c.osmId) ? cs.primary : null),
                          title: Text(c.label),
                          subtitle: Text([
                            c.distance == 0 ? 'jesteś na terenie cmentarza' : formatDistance(c.distance),
                            if (c.town != null) c.town!,
                            if (c.areaHa >= 0.05) '${c.areaHa.toStringAsFixed(1).replaceAll('.', ',')} ha',
                          ].join(' · ')),
                          trailing: _added.containsKey(c.osmId)
                              ? TextButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: _added[c.osmId]!.id!))),
                                  child: const Text('Dodany'),
                                )
                              : FilledButton.tonal(onPressed: () => _add(c), child: const Text('Dodaj')),
                          onTap: () {
                            try {
                              if (c.outline.length >= 3) {
                                _map.fitCamera(CameraFit.bounds(
                                    bounds: LatLngBounds.fromPoints([for (final p in c.outline) LatLng(p.$1, p.$2)]), padding: const EdgeInsets.all(24)));
                              } else {
                                _map.move(LatLng(c.lat, c.lng), 17);
                              }
                            } catch (_) {}
                          },
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Dane: © współtwórcy OpenStreetMap (ODbL). Brakuje cmentarza? Dodaj go ręcznie w „Cmentarze”.',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ),
                    ]),
        ),
      ]),
    );
  }
}

/// Groby na cmentarzu opisane przez społeczność OpenStreetMap – do zaimportowania.
class OsmGravesScreen extends StatefulWidget {
  final Cemetery cemetery;
  const OsmGravesScreen({super.key, required this.cemetery});
  @override
  State<OsmGravesScreen> createState() => _OsmGravesScreenState();
}

class _OsmGravesScreenState extends State<OsmGravesScreen> {
  List<OsmGrave>? _graves;
  Set<String> _existing = {};
  final Set<String> _selected = {};
  String? _error;
  bool _importing = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.cemetery;
    try {
      final ex = await AppDb.I.db.query('graves', columns: ['osm_id'], where: 'osm_id IS NOT NULL AND deleted=0');
      _existing = ex.map((r) => r['osm_id'] as String).toSet();
      final g = await Osm.gravesIn(c.outline, c.lat ?? 0, c.lng ?? 0);
      g.sort((a, b) => a.title.compareTo(b.title));
      if (mounted) setState(() => _graves = g);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    final db = AppDb.I;
    var n = 0;
    for (final g in _graves!.where((g) => _selected.contains(g.osmId))) {
      final grave = Grave(cemeteryId: widget.cemetery.id, lat: g.lat, lng: g.lng, osmId: g.osmId, notes: 'Zaimportowano z OpenStreetMap (${g.osmId})', allSaints: false);
      final gid = await db.saveGrave(grave, notify: false);
      var i = 0;
      for (final p in g.people) {
        await db.savePerson(
            Person(
              graveId: gid,
              firstName: p.firstName,
              lastName: p.lastName,
              maidenName: p.maidenName,
              birth: p.birth,
              death: p.death,
              inscription: i == 0 ? g.inscription : null,
              remindDeath: false,
              sort: i++,
            ),
            notify: false);
      }
      n++;
    }
    db.changed();
    if (!mounted) return;
    snack(context, 'Zaimportowano grobów: $n');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _graves;
    final list = all?.where((g) => _q.isEmpty || g.title.toLowerCase().contains(_q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Groby z mapy – ${widget.cemetery.name}', overflow: TextOverflow.ellipsis)),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _importing ? null : _import,
              icon: const Icon(Icons.download),
              label: Text('Dodaj ${_selected.length}'),
            ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: cs.error))))
          : all == null
              ? const Center(child: CircularProgressIndicator())
              : all.isEmpty
                  ? const EmptyState(
                      icon: Icons.map_outlined,
                      title: 'Brak opisanych grobów',
                      body: 'Na tym cmentarzu nikt jeszcze nie oznaczył grobów w OpenStreetMap. '
                          'To normalne – opisanych jest niewiele cmentarzy, głównie zabytkowe. Groby bliskich dodasz sam, stojąc przy nich.',
                    )
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: TextField(
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Szukaj nazwiska'),
                          onChanged: (v) => setState(() => _q = v.trim()),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Opisanych grobów: ${all.length}. Zaznacz tylko groby swoich bliskich.', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      Expanded(
                        child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                          for (final g in list!)
                            CheckboxListTile(
                              value: _existing.contains(g.osmId) || _selected.contains(g.osmId),
                              onChanged: _existing.contains(g.osmId)
                                  ? null
                                  : (v) => setState(() => v == true ? _selected.add(g.osmId) : _selected.remove(g.osmId)),
                              title: Text(g.title),
                              subtitle: Text([
                                for (final p in g.people)
                                  if (p.birth != null || p.death != null) '${p.birth?.format() ?? '?'} – ${p.death?.format() ?? '?'}',
                                if (_existing.contains(g.osmId)) 'już w aplikacji',
                              ].join(' · ')),
                            ),
                        ]),
                      ),
                    ]),
    );
  }
}
