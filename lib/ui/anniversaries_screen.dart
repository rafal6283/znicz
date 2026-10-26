import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/anniversaries.dart';
import '../logic/geo.dart';
import '../services/location.dart';
import '../sync/sync_service.dart';
import 'common.dart';
import 'grave_detail.dart';
import 'graves_list.dart';

class AnniversariesScreen extends StatefulWidget {
  const AnniversariesScreen({super.key});
  @override
  State<AnniversariesScreen> createState() => _AnniversariesScreenState();
}

class _AnniversariesScreenState extends State<AnniversariesScreen> {
  List<UpcomingEvent> _events = [];
  Map<int, GraveView> _graves = {};
  int _asTotal = 0, _asDone = 0;

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final views = await AppDb.I.graveViews();
    final people = await AppDb.I.allPeople();
    final now = DateTime.now();
    final ev = upcomingEvents(people, views.map((v) => v.grave).toList(), now);
    final (from, to) = allSaintsWindow(now);
    final visited = (await AppDb.I.visitsBetween(from, to)).map((v) => v.graveId).toSet();
    final list = views.where((v) => v.grave.allSaints).toList();
    if (!mounted) return;
    setState(() {
      _graves = {for (final v in views) v.grave.id!: v};
      _events = ev.where((e) => _graves.containsKey(e.graveId)).toList();
      _asTotal = list.length;
      _asDone = list.where((v) => visited.contains(v.grave.id)).length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final allSaints = nextOccurrence(11, 1, now);
    final daysToAS = DateTime(allSaints.year, allSaints.month, allSaints.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    final today = _events.where((e) => e.daysFrom(now) == 0).toList();
    final soon = _events.where((e) => e.daysFrom(now) > 0).take(40).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Pamięć')),
      body: RefreshIndicator(
        onRefresh: () async {
          await SyncService.I.syncNow(quiet: true);
          await _load();
        },
        child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: cs.primaryContainer,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllSaintsScreen())),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.local_fire_department, size: 40, color: cs.onPrimaryContainer),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Wszystkich Świętych', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: cs.onPrimaryContainer)),
                      Text(
                        daysToAS == 0 ? 'Dziś' : 'Za $daysToAS dni (${weekday(allSaints)})',
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      if (_asTotal > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _asTotal == 0 ? 0 : _asDone / _asTotal, borderRadius: BorderRadius.circular(4)),
                        const SizedBox(height: 4),
                        Text('Odwiedzone: $_asDone z $_asTotal grobów', style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
                      ],
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: cs.onPrimaryContainer),
                ]),
              ),
            ),
          ),
          if (today.isNotEmpty) ...[
            const SectionTitle('Dziś'),
            for (final e in today) _EventTile(e, _graves[e.graveId]!, highlight: true),
          ],
          const SectionTitle('Najbliższe rocznice'),
          if (soon.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Rocznice pojawią się tu, gdy osoby będą miały pełne daty urodzenia lub śmierci.', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
          for (final e in soon) _EventTile(e, _graves[e.graveId]!),
        ]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final UpcomingEvent e;
  final GraveView g;
  final bool highlight;
  const _EventTile(this.e, this.g, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = e.daysFrom(DateTime.now());
    final icon = switch (e.kind) {
      EventKind.death => Icons.local_fire_department_outlined,
      EventKind.birth => Icons.cake_outlined,
      EventKind.fee => Icons.receipt_long_outlined,
      EventKind.allSaints => Icons.event,
    };
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: highlight ? cs.primary : cs.secondaryContainer,
        child: Icon(icon, color: highlight ? cs.onPrimary : cs.onSecondaryContainer),
      ),
      title: Text(e.kind == EventKind.fee ? '${e.title}: ${g.title}' : e.title),
      subtitle: Text('${fmtDayMonth(e.date)} · ${relativeDays(days)}${g.cemetery != null ? ' · ${g.cemetery!.label}' : ''}'),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GraveDetailScreen(graveId: e.graveId))),
    );
  }
}

/// Plan na Wszystkich Świętych: lista grobów z odhaczaniem i kolejnością trasy.
class AllSaintsScreen extends StatefulWidget {
  const AllSaintsScreen({super.key});
  @override
  State<AllSaintsScreen> createState() => _AllSaintsScreenState();
}

class _AllSaintsScreenState extends State<AllSaintsScreen> {
  List<GraveView> _list = [];
  Map<int, Visit> _visited = {};
  bool _route = false;
  (double, double)? _start;

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final views = (await AppDb.I.graveViews()).where((v) => v.grave.allSaints).toList();
    final (from, to) = allSaintsWindow(DateTime.now());
    final visits = await AppDb.I.visitsBetween(from, to);
    if (!mounted) return;
    setState(() {
      _list = views;
      _visited = {for (final v in visits.reversed) v.graveId: v};
      _order();
    });
  }

  void _order() {
    (double, double)? pt(GraveView g) {
      final lat = g.grave.lat ?? g.cemetery?.lat;
      final lng = g.grave.lng ?? g.cemetery?.lng;
      return lat == null || lng == null ? null : (lat, lng);
    }

    if (_route) {
      final withLoc = _list.where((g) => pt(g) != null).toList();
      final without = _list.where((g) => pt(g) == null).toList();
      final order = visitOrder(withLoc.map((g) => pt(g)!).toList(), start: _start);
      _list = [for (final i in order) withLoc[i], ...without];
    } else {
      _list.sort((a, b) {
        final c = (a.cemetery?.label ?? '~').compareTo(b.cemetery?.label ?? '~');
        return c != 0 ? c : a.title.compareTo(b.title);
      });
    }
  }

  Future<void> _planRoute() async {
    final err = await LocationService.ensurePermission();
    if (err == null) {
      final p = await LocationService.current(timeout: const Duration(seconds: 10)) ?? await LocationService.last();
      if (p != null) _start = (p.latitude, p.longitude);
    }
    setState(() {
      _route = true;
      _order();
    });
  }

  Future<void> _toggle(GraveView g) async {
    final v = _visited[g.grave.id];
    if (v != null) {
      await AppDb.I.deleteVisit(v.id!);
    } else {
      final cfg = await SyncConfig.load();
      await AppDb.I.saveVisit(Visit(graveId: g.grave.id!, actions: {'znicz'}, note: 'Wszystkich Świętych', by: cfg.myName.isEmpty ? null : cfg.myName));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = _list.where((g) => _visited.containsKey(g.grave.id)).length;
    final children = <Widget>[];
    String? header;
    for (var i = 0; i < _list.length; i++) {
      final g = _list[i];
      if (!_route) {
        final h = g.cemetery?.label ?? 'Bez cmentarza';
        if (h != header) {
          children.add(SectionTitle(h));
          header = h;
        }
      }
      final v = _visited[g.grave.id];
      children.add(GraveTile(
        g,
        trailing: Checkbox(value: v != null, onChanged: (_) => _toggle(g)),
      ));
      if (v != null && (v.by ?? '').isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 88, bottom: 4),
          child: Text('odwiedził(a): ${v.by}', style: TextStyle(color: cs.primary, fontSize: 12)),
        ));
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Wszystkich Świętych')),
      body: _list.isEmpty
          ? const EmptyState(icon: Icons.local_fire_department_outlined, title: 'Brak grobów na liście', body: 'W edycji grobu włącz „Na liście na Wszystkich Świętych”.')
          : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Odwiedzone $done z ${_list.length} · zniczy potrzeba co najmniej ${_list.length - done}', style: Theme.of(context).textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('Wg cmentarzy'), selected: !_route, onSelected: (_) => setState(() {
                    _route = false;
                    _order();
                  })),
                  ChoiceChip(label: const Text('Trasa od mojej pozycji'), selected: _route, onSelected: (_) => _planRoute()),
                ]),
              ),
              if (_route)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Kolejność ułożona tak, by przejść jak najkrótszą drogą.', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ...children,
            ]),
    );
  }
}
