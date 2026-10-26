import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/dates_pl.dart';
import '../logic/geo.dart';
import '../services/location.dart';
import 'common.dart';
import 'grave_detail.dart';
import 'grave_edit.dart';

enum _Sort { cemetery, name, nearest, recent }

class GravesListScreen extends StatefulWidget {
  const GravesListScreen({super.key});
  @override
  State<GravesListScreen> createState() => _GravesListScreenState();
}

class _GravesListScreenState extends State<GravesListScreen> {
  List<GraveView> _all = [];
  bool _loaded = false;
  String _q = '';
  _Sort _sort = _Sort.cemetery;
  Position? _pos;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    _load();
    _quietPosition();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final v = await AppDb.I.graveViews();
    if (!mounted) return;
    setState(() {
      _all = v;
      _loaded = true;
    });
  }

  /// Ostatnia znana pozycja bez pytania o uprawnienia – do pokazywania odległości.
  Future<void> _quietPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final p = await LocationService.last();
        if (mounted && p != null) setState(() => _pos = p);
      }
    } catch (_) {}
  }

  Future<void> _sortNearest() async {
    final err = await LocationService.ensurePermission();
    if (err != null) {
      if (mounted) snack(context, err);
      return;
    }
    final p = await LocationService.current(timeout: const Duration(seconds: 10)) ?? await LocationService.last();
    if (!mounted) return;
    if (p == null) {
      snack(context, 'Nie udało się ustalić pozycji');
      return;
    }
    setState(() {
      _pos = p;
      _sort = _Sort.nearest;
    });
  }

  double? _dist(GraveView g) {
    if (_pos == null) return null;
    final lat = g.grave.lat ?? g.cemetery?.lat;
    final lng = g.grave.lng ?? g.cemetery?.lng;
    if (lat == null || lng == null) return null;
    return distanceM(_pos!.latitude, _pos!.longitude, lat, lng);
  }

  bool _matches(GraveView g) {
    if (_q.isEmpty) return true;
    final q = fold(_q);
    final hay = StringBuffer()
      ..write(g.cemetery?.label ?? '')
      ..write(' ')
      ..write(g.grave.placeLabel)
      ..write(' ')
      ..write(g.grave.notes ?? '');
    for (final p in g.people) {
      hay
        ..write(' ${p.fullName} ${p.relation ?? ''} ${p.birth?.year ?? ''} ${p.death?.year ?? ''}');
    }
    final h = fold(hay.toString());
    return q.split(RegExp(r'\s+')).every(h.contains);
  }

  String _sortKey(GraveView g) {
    final p = g.people.isEmpty ? null : g.people.first;
    return fold('${p?.lastName ?? ''} ${p?.firstName ?? ''}');
  }

  @override
  Widget build(BuildContext context) {
    final list = _all.where(_matches).toList();
    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => _sortKey(a).compareTo(_sortKey(b)));
      case _Sort.nearest:
        list.sort((a, b) => (_dist(a) ?? double.infinity).compareTo(_dist(b) ?? double.infinity));
      case _Sort.recent:
        list.sort((a, b) => (b.lastVisit?.date ?? 0).compareTo(a.lastVisit?.date ?? 0));
      case _Sort.cemetery:
        list.sort((a, b) {
          final c = fold(a.cemetery?.label ?? '~').compareTo(fold(b.cemetery?.label ?? '~'));
          return c != 0 ? c : _sortKey(a).compareTo(_sortKey(b));
        });
    }

    final children = <Widget>[];
    String? lastHeader;
    for (final g in list) {
      if (_sort == _Sort.cemetery) {
        final h = g.cemetery?.label ?? 'Bez cmentarza';
        if (h != lastHeader) {
          children.add(SectionTitle(h));
          lastHeader = h;
        }
      }
      children.add(GraveTile(g, distance: _dist(g)));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Znicz'),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: 'Sortowanie',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => s == _Sort.nearest ? _sortNearest() : setState(() => _sort = s),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.cemetery, child: Text('Wg cmentarzy')),
              PopupMenuItem(value: _Sort.name, child: Text('Alfabetycznie')),
              PopupMenuItem(value: _Sort.nearest, child: Text('Najbliżej mnie')),
              PopupMenuItem(value: _Sort.recent, child: Text('Ostatnio odwiedzane')),
            ],
          ),
        ],
      ),
      floatingActionButton: _all.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openNewGrave(context),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Dodaj grób'),
            ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _all.isEmpty
              ? EmptyState(
                  icon: Icons.local_fire_department_outlined,
                  title: 'Miejsca pamięci Twoich bliskich',
                  body: 'Zapisz grób stojąc przy nim: aplikacja zapamięta dokładne miejsce, odczyta napis z nagrobka ze zdjęcia, a dane możesz też podyktować.',
                  action: FilledButton.icon(onPressed: () => openNewGrave(context), icon: const Icon(Icons.add), label: const Text('Dodaj pierwszy grób')),
                )
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: SearchBar(
                      controller: _search,
                      hintText: 'Szukaj: nazwisko, cmentarz, rok…',
                      leading: const Icon(Icons.search),
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: (v) => setState(() => _q = v.trim()),
                      trailing: [
                        if (_q.isNotEmpty)
                          IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                setState(() => _q = '');
                              }),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('Nic nie znaleziono'))
                        : ListView(padding: const EdgeInsets.only(bottom: 96), children: children),
                  ),
                ]),
    );
  }
}

Future<void> openNewGrave(BuildContext context) async {
  final id = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const GraveEditScreen()));
  if (id != null && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => GraveDetailScreen(graveId: id)));
  }
}

class GraveTile extends StatelessWidget {
  final GraveView g;
  final double? distance;
  final Widget? trailing;
  final VoidCallback? onTap;
  const GraveTile(this.g, {super.key, this.distance, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = <String>[];
    final spans = g.people.map((p) {
      final parts = <String>[];
      if (p.lifespan.isNotEmpty) parts.add(p.lifespan);
      if ((p.relation ?? '').isNotEmpty) parts.add(p.relation!);
      return parts.join(', ');
    }).where((s) => s.isNotEmpty).toList();
    if (spans.isNotEmpty) lines.add(spans.join(' · '));
    final where = <String>[];
    if (g.grave.placeLabel.isNotEmpty) where.add(g.grave.placeLabel);
    if (distance != null) where.add(formatDistance(distance!));
    if (g.lastVisit != null) where.add('odwiedzony ${agoText(g.lastVisit!.dateTime)}');
    if (where.isNotEmpty) lines.add(where.join(' · '));
    return ListTile(
      leading: PhotoThumb(g.cover),
      title: Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: lines.isEmpty ? null : Text(lines.join('\n'), style: TextStyle(color: cs.onSurfaceVariant)),
      isThreeLine: lines.length > 1,
      trailing: trailing ?? (g.grave.favorite ? Icon(Icons.star, color: cs.primary, size: 20) : null),
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(builder: (_) => GraveDetailScreen(graveId: g.grave.id!))),
    );
  }
}
