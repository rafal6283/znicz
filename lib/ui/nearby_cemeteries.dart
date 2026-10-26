import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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

/// Cmentarze na mapie: wyszukiwanie w widocznym obszarze (OpenStreetMap), dodawanie dotknięciem
/// cmentarza na mapie albo przytrzymaniem palca w dowolnym miejscu.
class NearbyCemeteriesScreen extends StatefulWidget {
  final double? lat;
  final double? lng;
  final double? zoom;
  const NearbyCemeteriesScreen({super.key, this.lat, this.lng, this.zoom});
  @override
  State<NearbyCemeteriesScreen> createState() => _NearbyCemeteriesScreenState();
}

class _NearbyCemeteriesScreenState extends State<NearbyCemeteriesScreen> {
  final _map = MapController();
  LatLng? _me;
  bool _loading = false;
  String? _error;
  List<OsmCemetery> _found = [];
  List<Cemetery> _mine = [];
  Map<String, Cemetery> _added = {}; // osmId → cmentarz w aplikacji
  bool _mapReady = false;
  bool _moved = false; // mapa przesunięta od ostatniego wyszukiwania
  bool _searchedOnce = false;
  bool _pendingMove = false;
  final _sheet = DraggableScrollableController();

  /// Największy obszar przeszukiwany naraz (km po przekątnej) – Overpass i tak by się zadławił.
  static const _maxDiagKm = 45.0;

  @override
  void initState() {
    super.initState();
    _loadMine();
    _locateMe(move: widget.lat == null);
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    final cems = await AppDb.I.cemeteries();
    if (!mounted) return;
    setState(() {
      _mine = cems;
      _added = {for (final c in cems) if (c.osmId != null) c.osmId!: c};
    });
  }

  Future<void> _locateMe({required bool move}) async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (!move) return;
      final err = await LocationService.ensurePermission();
      if (err != null) {
        if (mounted) setState(() => _error = '$err\nPrzesuń mapę ręcznie i dotknij „Szukaj w tym obszarze”.');
        return;
      }
    }
    final p = await LocationService.last() ?? await LocationService.current(timeout: const Duration(seconds: 12));
    if (p == null || !mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    if (move && !_mapReady) _pendingMove = true;
    if (move && _mapReady) {
      _map.move(_me!, 13);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _searchVisible();
    }
  }

  Future<void> _searchVisible() async {
    if (!_mapReady) return;
    final b = _map.camera.visibleBounds;
    final diag = distanceM(b.south, b.west, b.north, b.east) / 1000;
    if (diag > _maxDiagKm) {
      setState(() => _error = 'Za duży obszar (${diag.round()} km). Przybliż mapę, żeby obejmowała najwyżej kilka miejscowości.');
      return;
    }
    final ref = _me ?? _map.camera.center;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Osm.cemeteriesInBox(b.south, b.west, b.north, b.east, ref.latitude, ref.longitude);
      if (!mounted) return;
      setState(() {
        _found = r;
        _moved = false;
        _searchedOnce = true;
      });
      if (r.isNotEmpty && _sheet.isAttached && _sheet.size < 0.3) {
        _sheet.animateTo(0.35, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  OsmCemetery? _osmAt(LatLng p) {
    for (final c in _found) {
      if (pointInPolygon(p.latitude, p.longitude, c.outline)) return c;
    }
    return null;
  }

  Cemetery? _mineAt(LatLng p) {
    for (final c in _mine) {
      if (pointInPolygon(p.latitude, p.longitude, c.outline)) return c;
    }
    return null;
  }

  void _focus(OsmCemetery c) {
    try {
      if (c.outline.length >= 3) {
        _map.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([for (final p in c.outline) LatLng(p.$1, p.$2)]),
            padding: EdgeInsets.fromLTRB(32, 32, 32, MediaQuery.of(context).size.height * 0.4)));
      } else {
        _map.move(LatLng(c.lat, c.lng), 17);
      }
    } catch (_) {}
  }

  /// Dotknięcie cmentarza z OpenStreetMap → szybkie dodanie.
  Future<void> _addOsm(OsmCemetery o) async {
    if (_added.containsKey(o.osmId)) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: _added[o.osmId]!.id!)));
      return;
    }
    final street = [o.tags['addr:street'], o.tags['addr:housenumber']].whereType<String>().join(' ').trim();
    final draft = Cemetery(
      name: o.name ?? '',
      town: o.town,
      kind: o.kind,
      lat: o.lat,
      lng: o.lng,
      osmId: o.osmId,
      outline: o.outline,
      address: street.isEmpty ? null : street,
      phone: o.tags['phone'] ?? o.tags['contact:phone'],
      hours: o.tags['opening_hours'],
      searchUrl: o.tags['website'] ?? o.tags['contact:website'],
    );
    await _quickAdd(draft, fromOsm: true);
  }

  /// Przytrzymanie palca na mapie → nowy cmentarz w tym miejscu (albo ten z OSM, jeśli tu jest).
  Future<void> _longPress(LatLng p) async {
    final osm = _osmAt(p);
    if (osm != null) return _addOsm(osm);
    final mine = _mineAt(p);
    if (mine != null) {
      snack(context, 'Tu jest już „${mine.label}”');
      return;
    }
    await _quickAdd(Cemetery(name: '', lat: p.latitude, lng: p.longitude), fromOsm: false);
  }

  Future<void> _quickAdd(Cemetery draft, {required bool fromOsm}) async {
    final saved = await showModalBottomSheet<Cemetery>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: QuickCemeterySheet(draft: draft, fromOsm: fromOsm),
      ),
    );
    if (saved == null) return;
    await _loadMine();
    if (!mounted) return;
    snack(context, 'Dodano: ${saved.label}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mineOutlines = _mine.map((c) => c.outline).where((o) => o.length >= 3);
    final foundNew = _found.where((c) => !_added.containsKey(c.osmId)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Cmentarze na mapie')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.lat != null ? LatLng(widget.lat!, widget.lng!) : const LatLng(52.07, 19.48),
            initialZoom: widget.lat != null ? (widget.zoom ?? 14) : 6,
            maxZoom: 22,
            onMapReady: () {
              _mapReady = true;
              if (widget.lat != null) {
                _searchVisible();
              } else if (_pendingMove && _me != null) {
                _pendingMove = false;
                _map.move(_me!, 13);
                Future<void>.delayed(const Duration(milliseconds: 300), _searchVisible);
              }
            },
            onPositionChanged: (_, hasGesture) {
              if (hasGesture && !_moved) setState(() => _moved = true);
            },
            onTap: (_, p) {
              final o = _osmAt(p);
              if (o != null) {
                _addOsm(o);
                return;
              }
              final m = _mineAt(p);
              if (m != null) Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: m.id!)));
            },
            onLongPress: (_, p) => _longPress(p),
          ),
          children: [
            ...MapLayers.tiles(),
            cemeteryPolygons(foundNew.map((c) => c.outline), cs.tertiary),
            cemeteryPolygons(mineOutlines, cs.primary),
            MarkerLayer(markers: [
              for (final c in foundNew)
                Marker(
                  point: LatLng(c.lat, c.lng),
                  width: 40,
                  height: 46,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(onTap: () => _addOsm(c), child: GravePin(color: cs.tertiary, icon: Icons.add)),
                ),
              for (final c in _mine)
                if (c.hasLocation)
                  Marker(
                    point: LatLng(c.lat!, c.lng!),
                    width: 40,
                    height: 46,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: c.id!))),
                      child: GravePin(color: cs.primary, icon: Icons.park_outlined),
                    ),
                  ),
              if (_me != null) myLocationMarker(_me!),
            ]),
            MapLayers.attribution(),
          ],
        ),
        // przycisk wyszukiwania w widocznym obszarze
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: _loading
                ? const Card(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Szukam w tym obszarze…'),
                  ])))
                : (_moved || !_searchedOnce)
                    ? FilledButton.icon(onPressed: _searchVisible, icon: const Icon(Icons.search), label: const Text('Szukaj w tym obszarze'))
                    : const SizedBox(),
          ),
        ),
        Positioned(
          right: 12,
          top: 64,
          child: Column(children: [
            FloatingActionButton.small(
              heroTag: 'n_layer',
              tooltip: MapLayers.satellite ? 'Mapa' : 'Satelita',
              onPressed: () async {
                await MapLayers.toggle();
                setState(() {});
              },
              child: Icon(MapLayers.satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'n_me', tooltip: 'Moja pozycja', onPressed: () => _locateMe(move: true), child: const Icon(Icons.my_location)),
          ]),
        ),
        DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: 0.22,
          minChildSize: 0.1,
          maxChildSize: 0.8,
          snap: true,
          builder: (context, scroll) => Material(
            elevation: 6,
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: ListView(controller: scroll, padding: const EdgeInsets.only(bottom: 24), children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _error ??
                      (!_searchedOnce
                          ? 'Ustaw mapę na okolicę i dotknij „Szukaj w tym obszarze”. Przytrzymaj palec na mapie, by dodać cmentarz w dowolnym miejscu.'
                          : _found.isEmpty
                              ? 'W tym obszarze mapa nie zna cmentarzy. Przytrzymaj palec w miejscu cmentarza, by dodać go ręcznie.'
                              : 'Znaleziono: ${_found.length}. Dotknij cmentarza na mapie lub na liście, by go dodać. Przytrzymaj palec, by dodać inny.'),
                  style: TextStyle(color: _error != null ? cs.error : cs.onSurfaceVariant),
                ),
              ),
              for (final c in _found)
                ListTile(
                  leading: Icon(_added.containsKey(c.osmId) ? Icons.check_circle : Icons.park_outlined, color: _added.containsKey(c.osmId) ? cs.primary : cs.tertiary),
                  title: Text(_added[c.osmId]?.label ?? c.label),
                  subtitle: Text([
                    c.distance == 0 ? (_me != null ? 'jesteś na terenie' : 'środek mapy') : formatDistance(c.distance),
                    if (c.town != null) c.town!,
                    if (c.areaHa >= 0.05) '${c.areaHa.toStringAsFixed(1).replaceAll('.', ',')} ha',
                    if (c.name == null && !_added.containsKey(c.osmId)) 'bez nazwy w mapie',
                  ].join(' · ')),
                  trailing: _added.containsKey(c.osmId)
                      ? const Text('Dodany')
                      : FilledButton.tonal(onPressed: () => _addOsm(c), child: const Text('Dodaj')),
                  onTap: () => _focus(c),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text('Dane: © współtwórcy OpenStreetMap (ODbL).', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Szybki formularz cmentarza w arkuszu na mapie: nazwa z podpowiedziami, miejscowość uzupełniana sama.
class QuickCemeterySheet extends StatefulWidget {
  final Cemetery draft;
  final bool fromOsm;
  const QuickCemeterySheet({super.key, required this.draft, required this.fromOsm});
  @override
  State<QuickCemeterySheet> createState() => _QuickCemeterySheetState();
}

class _QuickCemeterySheetState extends State<QuickCemeterySheet> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _town = TextEditingController(text: widget.draft.town ?? '');
  late String? _kind = widget.draft.kind;
  bool _townLoading = false;
  bool _saving = false;
  bool _autoName = true; // nazwa ustawiona automatycznie – można ją nadpisać podpowiedzią

  @override
  void initState() {
    super.initState();
    if ((widget.draft.town ?? '').isEmpty && widget.draft.hasLocation) _lookupTown();
    if (_name.text.isEmpty) {
      _suggestName();
    } else {
      _autoName = false;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _town.dispose();
    super.dispose();
  }

  Future<void> _lookupTown() async {
    setState(() => _townLoading = true);
    final t = await Osm.townAt(widget.draft.lat!, widget.draft.lng!);
    if (!mounted) return;
    setState(() {
      _townLoading = false;
      if (t != null && _town.text.trim().isEmpty) _town.text = t;
    });
    if (_name.text.trim().isEmpty || _autoName) setState(_suggestName);
  }

  void _suggestName() {
    final k = _kind ?? 'parafialny';
    _name.text = 'Cmentarz $k';
    _autoName = true;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      snack(context, 'Wpisz nazwę cmentarza');
      return;
    }
    setState(() => _saving = true);
    final c = widget.draft
      ..name = _name.text.trim()
      ..town = _town.text.trim().isEmpty ? null : _town.text.trim()
      ..kind = _kind;
    await AppDb.I.saveCemetery(c);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(widget.fromOsm ? 'Cmentarz z mapy' : 'Nowy cmentarz w tym miejscu', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.fromOsm
                ? 'Położenie i obrys są już z mapy${widget.draft.name.isEmpty ? ' – brakuje tylko nazwy' : ''}.'
                : 'Położenie: ${widget.draft.lat!.toStringAsFixed(5)}, ${widget.draft.lng!.toStringAsFixed(5)}',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          VoiceField(
            controller: _name,
            label: 'Nazwa',
            caps: TextCapitalization.sentences,
            onChanged: (_) => _autoName = false,
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: -6, children: [
            for (final k in cemeteryKinds.where((k) => k != 'inny'))
              ChoiceChip(
                label: Text(k),
                visualDensity: VisualDensity.compact,
                selected: _kind == k,
                onSelected: (_) => setState(() {
                  _kind = k;
                  if (_autoName || _name.text.trim().isEmpty) _suggestName();
                }),
              ),
          ]),
          const SizedBox(height: 12),
          VoiceField(
            controller: _town,
            label: 'Miejscowość',
            caps: TextCapitalization.words,
            prefixIcon: _townLoading ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _saving ? null : _save, child: const Text('Dodaj cmentarz')),
          ]),
        ]),
      ),
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
