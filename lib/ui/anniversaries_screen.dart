import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../logic/anniversaries.dart';
import '../logic/dates_pl.dart';
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

enum _Who { all, mine, nobody }

class _AllSaintsScreenState extends State<AllSaintsScreen> {
  List<GraveView> _list = [];
  Map<int, Visit> _visited = {};
  Set<int> _photoThisYear = {};
  bool _route = false;
  _Who _who = _Who.all;
  String _me = '';
  Set<String> _family = {};
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
    final cfg = await SyncConfig.load();
    final family = await AppDb.I.familyNames();
    final photos = await AppDb.I.gravesWithPhotoSince(DateTime(DateTime.now().year));
    if (!mounted) return;
    setState(() {
      _me = cfg.myName.trim();
      _family = {...family, if (_me.isNotEmpty) _me};
      _list = views;
      _visited = {for (final v in visits.reversed) v.graveId: v};
      _photoThisYear = photos;
      _order();
    });
  }

  static (double, double)? _pt(GraveView g) {
    final lat = g.grave.lat ?? g.cemetery?.lat;
    final lng = g.grave.lng ?? g.cemetery?.lng;
    return lat == null || lng == null ? null : (lat, lng);
  }

  void _order() {
    if (_route) {
      final withLoc = _list.where((g) => _pt(g) != null).toList();
      final without = _list.where((g) => _pt(g) == null).toList();
      final order = visitOrder(withLoc.map((g) => _pt(g)!).toList(), start: _start);
      _list = [for (final i in order) withLoc[i], ...without];
    } else {
      _list.sort((a, b) {
        final c = (a.cemetery?.label ?? '~').compareTo(b.cemetery?.label ?? '~');
        return c != 0 ? c : a.title.compareTo(b.title);
      });
    }
  }

  bool _shown(GraveView g) => switch (_who) {
        _Who.all => true,
        _Who.mine => _me.isNotEmpty && fold(g.grave.visitor ?? '') == fold(_me),
        _Who.nobody => (g.grave.visitor ?? '').trim().isEmpty,
      };

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

  /// Nawigacja przez cmentarze z nieodwiedzonymi grobami (w kolejności trasy).
  Future<void> _navigate() async {
    if (!_route) await _planRoute();
    final todo = _list.where((g) => _shown(g) && !_visited.containsKey(g.grave.id) && _pt(g) != null).toList();
    final stops = routeStops([for (final g in todo) g.cemetery?.hasLocation == true ? (g.cemetery!.lat!, g.cemetery!.lng!) : _pt(g)!],
        [for (final g in todo) g.cemetery?.id]);
    final url = directionsUrl(stops, origin: _start);
    if (url == null) {
      if (mounted) snack(context, 'Brak nieodwiedzonych grobów z zapisanym miejscem');
      return;
    }
    if (stops.length > 10 && mounted) snack(context, 'Nawigacja obejmuje pierwsze 10 cmentarzy z ${stops.length}');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _toggle(GraveView g) async {
    final v = _visited[g.grave.id];
    if (v != null) {
      await AppDb.I.deleteVisit(v.id!);
      return;
    }
    await AppDb.I.saveVisit(Visit(graveId: g.grave.id!, actions: {'znicz'}, note: 'Wszystkich Świętych', by: _me.isEmpty ? null : _me));
    if (!mounted || _photoThisYear.contains(g.grave.id)) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Brak tegorocznego zdjęcia grobu – ${g.title}'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Zrób zdjęcie', onPressed: () => _yearPhoto(g)),
    ));
  }

  Future<void> _yearPhoto(GraveView g) async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2600, imageQuality: 88);
    if (x == null) return;
    await Storage.addPhoto(g.grave.id!, x.path, caption: 'Stan grobu ${DateTime.now().year}');
  }

  Future<void> _assign(GraveView g) async {
    final ctrl = TextEditingController(text: g.grave.visitor ?? '');
    final names = _family.toList()..sort();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kto odwiedza ten grób?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.title, style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (names.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final n in names) ActionChip(label: Text(n == _me ? '$n (ja)' : n), onPressed: () => Navigator.pop(ctx, n)),
            ]),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Imię'), textCapitalization: TextCapitalization.words),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Nikt')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Zapisz')),
        ],
      ),
    );
    if (r == null) return;
    g.grave.visitor = r.isEmpty ? null : r;
    await AppDb.I.saveGrave(g.grave);
  }

  /// Plan podziału jako tekst – dla rodziny bez aplikacji.
  Future<void> _sharePlan() async {
    final by = <String, List<GraveView>>{};
    for (final g in _list) {
      by.putIfAbsent((g.grave.visitor ?? '').trim().isEmpty ? 'Nieprzydzielone' : g.grave.visitor!.trim(), () => []).add(g);
    }
    final b = StringBuffer('Wszystkich Świętych – kto gdzie jedzie\n');
    for (final e in by.entries) {
      b.writeln('\n${e.key}:');
      for (final g in e.value) {
        b.writeln('• ${g.title}${g.cemetery == null ? '' : ' – ${g.cemetery!.label}'}${g.grave.placeLabel.isEmpty ? '' : ', ${g.grave.placeLabel}'}'
            '${_visited.containsKey(g.grave.id) ? ' ✓' : ''}');
      }
    }
    await SharePlus.instance.share(ShareParams(text: b.toString().trim(), subject: 'Wszystkich Świętych'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _list.where(_shown).toList();
    final done = list.where((g) => _visited.containsKey(g.grave.id)).length;
    final children = <Widget>[];
    String? header;
    for (final g in list) {
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
      final who = (g.grave.visitor ?? '').trim();
      children.add(Padding(
        padding: const EdgeInsets.only(left: 80, bottom: 4, right: 16),
        child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          InkWell(
            onTap: () => _assign(g),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_outline, size: 16, color: who.isEmpty ? cs.outline : cs.primary),
                const SizedBox(width: 4),
                Text(who.isEmpty ? 'przydziel osobę' : who,
                    style: TextStyle(fontSize: 12, color: who.isEmpty ? cs.outline : cs.primary, fontWeight: who.isEmpty ? null : FontWeight.w600)),
              ]),
            ),
          ),
          if (v != null && (v.by ?? '').isNotEmpty) Text('odwiedził(a): ${v.by}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          if (v != null && !_photoThisYear.contains(g.grave.id))
            InkWell(
              onTap: () => _yearPhoto(g),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_a_photo_outlined, size: 14, color: cs.tertiary),
                const SizedBox(width: 3),
                Text('zdjęcie ${DateTime.now().year}', style: TextStyle(fontSize: 12, color: cs.tertiary)),
              ]),
            ),
        ]),
      ));
    }
    final todo = list.where((g) => !_visited.containsKey(g.grave.id) && _pt(g) != null).toList();
    final stops = routeStops([for (final g in todo) _pt(g)!], [for (final g in todo) g.cemetery?.id]);
    final km = _route && stops.isNotEmpty ? routeLength(stops, start: _start) / 1000 : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Wszystkich Świętych'), actions: [
        if (_list.isNotEmpty) IconButton(tooltip: 'Udostępnij podział', onPressed: _sharePlan, icon: const Icon(Icons.share_outlined)),
      ]),
      floatingActionButton: todo.isEmpty
          ? null
          : FloatingActionButton.extended(onPressed: _navigate, icon: const Icon(Icons.navigation_outlined), label: const Text('Nawiguj')),
      body: _list.isEmpty
          ? const EmptyState(icon: Icons.local_fire_department_outlined, title: 'Brak grobów na liście', body: 'W edycji grobu włącz „Na liście na Wszystkich Świętych”.')
          : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Odwiedzone $done z ${list.length} · zniczy potrzeba co najmniej ${list.length - done}', style: Theme.of(context).textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  ChoiceChip(label: const Text('Wg cmentarzy'), selected: !_route, onSelected: (_) => setState(() {
                    _route = false;
                    _order();
                  })),
                  ChoiceChip(label: const Text('Trasa od mojej pozycji'), selected: _route, onSelected: (_) => _planRoute()),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  FilterChip(label: const Text('Wszystkie'), selected: _who == _Who.all, onSelected: (_) => setState(() => _who = _Who.all)),
                  FilterChip(
                      label: Text(_me.isEmpty ? 'Moje' : 'Moje ($_me)'),
                      selected: _who == _Who.mine,
                      onSelected: (_) {
                        if (_me.isEmpty) {
                          snack(context, 'Wpisz swoje imię w Więcej → Synchronizacja rodzinna');
                          return;
                        }
                        setState(() => _who = _Who.mine);
                      }),
                  FilterChip(label: const Text('Nieprzydzielone'), selected: _who == _Who.nobody, onSelected: (_) => setState(() => _who = _Who.nobody)),
                ]),
              ),
              if (_route)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                      'Kolejność ułożona tak, by przejść jak najkrótszą drogą'
                      '${km == null ? '' : ' · pozostało ${stops.length} ${stops.length == 1 ? 'przystanek' : 'przystanków'}, ok. ${km.toStringAsFixed(km < 10 ? 1 : 0)} km w linii prostej'}.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ...children,
            ]),
    );
  }
}
