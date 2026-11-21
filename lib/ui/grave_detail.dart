import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import 'cemetery.dart';
import 'common.dart';
import 'compass_screen.dart';
import 'grave_edit.dart';
import 'grave_years.dart';
import 'photo_viewer.dart';
import 'visit_edit.dart';
import 'cemetery_icon.dart';
import 'expenses.dart';
import 'family_tree.dart';
import 'grave_qr.dart';
import 'memories.dart';
import 'route_record.dart';
import '../logic/geo.dart';

class GraveDetailScreen extends StatefulWidget {
  final int graveId;
  const GraveDetailScreen({super.key, required this.graveId});
  @override
  State<GraveDetailScreen> createState() => _GraveDetailScreenState();
}

class _GraveDetailScreenState extends State<GraveDetailScreen> {
  GraveView? _g;
  List<GravePhoto> _photos = [];
  List<Visit> _visits = [];
  bool _gone = false;
  Map<String, int> _memCounts = {};
  double _expTotal = 0;

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
    final g = await AppDb.I.graveView(widget.graveId);
    if (!mounted) return;
    if (g == null) {
      setState(() => _gone = true);
      return;
    }
    final ph = await AppDb.I.photos(widget.graveId);
    final v = await AppDb.I.visits(widget.graveId);
    final mem = await AppDb.I.memoryCounts();
    final exp = await AppDb.I.expenses(graveId: widget.graveId);
    if (mounted) {
      setState(() {
        _g = g;
        _photos = ph;
        _visits = v;
        _memCounts = mem;
        _expTotal = exp.fold<double>(0, (a, e) => a + e.amount);
      });
    }
  }

  Future<void> _addPhoto(ImageSource src) async {
    // z galerii można zaznaczyć od razu kilka zdjęć
    final xs = src == ImageSource.gallery
        ? await ImagePicker().pickMultiImage(maxWidth: 2600, imageQuality: 88)
        : await _one(src);
    for (final x in xs) {
      await Storage.addPhoto(widget.graveId, x.path);
    }
    if (xs.length > 1 && mounted) snack(context, 'Dodano ${xs.length} zdjęcia – przytrzymaj zdjęcie, aby ustawić je jako główne');
  }

  /// Menu zdjęcia (przytrzymanie miniatury): zdjęcie główne, podgląd, usunięcie.
  Future<void> _photoMenu(int i) async {
    final ph = _photos[i];
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(ph.cover ? Icons.star : Icons.star_outline, color: Colors.amber),
            title: Text(ph.cover ? 'To jest zdjęcie główne' : 'Ustaw jako zdjęcie główne'),
            subtitle: const Text('Pokazywane na liście grobów, na mapie i jako pierwsze w galerii'),
            enabled: !ph.cover,
            onTap: () => Navigator.pop(c, 'cover'),
          ),
          ListTile(leading: const Icon(Icons.fullscreen), title: const Text('Otwórz'), onTap: () => Navigator.pop(c, 'open')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Usuń zdjęcie'), onTap: () => Navigator.pop(c, 'del')),
        ]),
      ),
    );
    if (!mounted) return;
    switch (v) {
      case 'cover':
        await AppDb.I.setCover(ph);
        if (mounted) snack(context, 'Ustawiono zdjęcie główne');
      case 'open':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(photos: _photos, initial: i)));
      case 'del':
        if (await confirm(context, 'Usunąć zdjęcie?', 'Zdjęcie zostanie usunięte.')) await AppDb.I.deletePhoto(ph);
    }
  }

  String _shareText(GraveView g) {
    final b = StringBuffer();
    for (final p in g.people) {
      b.write(p.fullName);
      if (p.birth != null || p.death != null) b.write(' (${p.birth?.format() ?? '?'} – ${p.death?.format() ?? '?'})');
      b.writeln();
    }
    if (g.cemetery != null) b.writeln(g.cemetery!.label);
    if (g.grave.placeLabel.isNotEmpty) b.writeln(g.grave.placeLabel);
    if ((g.grave.directions ?? '').isNotEmpty) b.writeln('Jak dojść: ${g.grave.directions}');
    final lat = g.grave.lat ?? g.cemetery?.lat;
    final lng = g.grave.lng ?? g.cemetery?.lng;
    if (lat != null && lng != null) {
      b.writeln('Mapa: https://www.google.com/maps/search/?api=1&query=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}');
    }
    return b.toString().trim();
  }

  Future<void> _share(String how) async {
    final g = _g!;
    if (how == 'text') {
      final files = <XFile>[];
      if (g.cover != null && File(AppDb.I.absPath(g.cover!.path)).existsSync()) files.add(XFile(AppDb.I.absPath(g.cover!.path)));
      await SharePlus.instance.share(ShareParams(text: _shareText(g), files: files.isEmpty ? null : files, subject: g.title));
    } else {
      final dir = await getTemporaryDirectory();
      final f = await Storage.exportGraveFile(widget.graveId, tempDir: dir.path);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'application/zip')],
        text: 'Grób: ${g.title}. Otwórz w aplikacji Znicz (Więcej → Importuj grób z pliku).',
        subject: g.title,
      ));
    }
  }

  Future<void> _grobonet() async {
    final g = _g!;
    final name = g.people.isEmpty ? '' : '${g.people.first.firstName} ${g.people.first.lastName}'.trim();
    if (name.isNotEmpty) await Clipboard.setData(ClipboardData(text: name));
    final own = g.cemetery?.searchUrl;
    final url = (own != null && own.isNotEmpty) ? (own.startsWith('http') ? own : 'https://$own') : 'https://www.grobonet.com/';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (mounted && name.isNotEmpty) snack(context, 'Skopiowano „$name” – wklej w wyszukiwarkę');
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Ten grób został usunięty')));
    final g = _g;
    if (g == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasLoc = g.grave.hasLocation;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: _photos.isEmpty ? null : 260,
          flexibleSpace: _photos.isEmpty
              ? null
              : FlexibleSpaceBar(
                  background: PageView(children: [
                    for (var i = 0; i < _photos.length; i++)
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(photos: _photos, initial: i))),
                        child: Image.file(File(AppDb.I.absPath(_photos[i].path)), fit: BoxFit.cover, cacheWidth: 1200,
                            errorBuilder: (_, __, ___) => Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.cloud_download_outlined))),
                      ),
                  ]),
                ),
          actions: [
            IconButton(
              tooltip: g.grave.favorite ? 'Usuń z ulubionych' : 'Ulubiony',
              icon: Icon(g.grave.favorite ? Icons.star : Icons.star_border),
              onPressed: () async {
                g.grave.favorite = !g.grave.favorite;
                await AppDb.I.saveGrave(g.grave);
              },
            ),
            IconButton(
              tooltip: 'Edytuj',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GraveEditScreen(graveId: widget.graveId))),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'text':
                  case 'file':
                    await _share(v);
                  case 'grobonet':
                    await _grobonet();
                  case 'qr':
                    Navigator.push(context, MaterialPageRoute(builder: (_) => GraveQrScreen(grave: g)));
                  case 'del':
                    if (await confirm(context, 'Usunąć grób?', 'Zostaną usunięte osoby, zdjęcia i dziennik wizyt tego grobu – także u rodziny, jeśli synchronizujecie dane.')) {
                      await AppDb.I.deleteGrave(widget.graveId);
                      if (context.mounted) Navigator.pop(context);
                    }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Wyślij opis i mapę'))),
                PopupMenuItem(value: 'file', child: ListTile(leading: Icon(Icons.file_present_outlined), title: Text('Wyślij plik grobu'))),
                PopupMenuItem(value: 'qr', child: ListTile(leading: Icon(Icons.qr_code_2), title: Text('Kod QR do grobu'))),
                PopupMenuItem(value: 'grobonet', child: ListTile(leading: Icon(Icons.travel_explore), title: Text('Szukaj w Grobonet'))),
                PopupMenuItem(value: 'del', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Usuń grób'))),
              ],
            ),
          ],
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(g.title, style: tt.headlineSmall),
            ),
            if (g.subtitle.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(g.subtitle, style: TextStyle(color: cs.onSurfaceVariant))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (hasLoc)
                  FilledButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompassScreen(grave: g))),
                    icon: const Icon(Icons.explore_outlined),
                    label: const Text('Prowadź do grobu'),
                  ),
                if (hasLoc || (g.cemetery?.hasLocation ?? false))
                  FilledButton.tonalIcon(
                    onPressed: () => openExternalNavigation(context, g.grave.lat ?? g.cemetery!.lat!, g.grave.lng ?? g.cemetery!.lng!, label: g.title),
                    icon: const Icon(Icons.directions_car_outlined),
                    label: const Text('Dojazd'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitEditScreen(graveId: widget.graveId))),
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: const Text('Wizyta'),
                ),
              ]),
            ),
            if (!hasLoc)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Brak dokładnego położenia – dodaj je w edycji, gdy będziesz przy grobie.', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            const SectionTitle('Osoby'),
            for (final p in g.people) _PersonCard(p, memories: _memCounts[p.uid] ?? 0),
            const SectionTitle('Miejsce'),
            if (g.cemetery != null)
              ListTile(
                leading: CemeteryIcon(kind: g.cemetery!.kind),
                title: Text(g.cemetery!.label),
                subtitle: (g.cemetery!.kind ?? '').isEmpty ? null : Text(g.cemetery!.kind!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: g.cemetery!.id!))),
              ),
            if (g.grave.placeLabel.isNotEmpty) ListTile(leading: const Icon(Icons.grid_on), title: Text(g.grave.placeLabel), subtitle: g.grave.type == null ? null : Text(g.grave.type!)),
            if ((g.grave.directions ?? '').isNotEmpty) ListTile(leading: const Icon(Icons.signpost_outlined), title: Text(g.grave.directions!)),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(g.grave.route.length >= 2 ? 'Droga od bramy: ${formatDistance(routeLength(g.grave.route))}' : 'Nagraj drogę od bramy'),
              subtitle: Text(g.grave.route.length >= 2
                  ? '„Prowadź do grobu” poprowadzi tą ścieżką'
                  : 'Przejdź raz od bramy do grobu – rodzina trafi tą samą ścieżką'),
              trailing: g.grave.route.length >= 2
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'again') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => RouteRecordScreen(graveId: widget.graveId)));
                        } else if (v == 'del' && await confirm(context, 'Usunąć nagraną drogę?', 'Prowadzenie wróci do linii prostej.')) {
                          g.grave.route = const [];
                          await AppDb.I.saveGrave(g.grave);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'again', child: Text('Nagraj ponownie')),
                        PopupMenuItem(value: 'del', child: Text('Usuń drogę')),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
              onTap: g.grave.route.length >= 2
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(builder: (_) => RouteRecordScreen(graveId: widget.graveId))),
            ),
            if (g.grave.feePaidUntil != null) _FeeTile(g.grave.feePaidUntil!),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(_expTotal > 0 ? 'Wydatki: ${zl(_expTotal)}' : 'Wydatki'),
              subtitle: const Text('Opłaty, kamieniarz, znicze – z rozliczeniem w rodzinie'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpensesScreen(graveId: widget.graveId, title: 'Wydatki – ${g.title}'))),
            ),
            if ((g.grave.notes ?? '').isNotEmpty) ...[
              const SectionTitle('Notatki'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(g.grave.notes!)),
            ],
            SectionTitle(
              'Zdjęcia (${_photos.length})',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_photos.isNotEmpty)
                  IconButton(
                    tooltip: 'Stan grobu rok po roku',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GraveYearsScreen(title: g.title, photos: _photos))),
                    icon: const Icon(Icons.compare_outlined),
                  ),
                IconButton(tooltip: 'Zrób zdjęcie', onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(tooltip: 'Z galerii (kilka naraz)', onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined)),
              ]),
            ),
            if (_photos.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('★ zdjęcie główne – stuknij gwiazdkę przy innym zdjęciu, aby je zmienić',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
            if (_photos.isNotEmpty)
              SizedBox(
                height: 96,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (var i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(photos: _photos, initial: i))),
                        onLongPress: () => _photoMenu(i),
                        child: Stack(children: [
                          PhotoThumb(_photos[i], size: 92),
                          // gwiazdka: główne (pełna) / stuknij, aby ustawić (kontur)
                          if (_photos.length > 1 || _photos[i].cover)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: _photos[i].cover ? null : () => AppDb.I.setCover(_photos[i]),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(_photos[i].cover ? Icons.star : Icons.star_outline,
                                      color: Colors.amber, size: 20, shadows: const [Shadow(blurRadius: 4)]),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                ]),
              ),
            SectionTitle(
              'Dziennik wizyt (${_visits.length})',
              trailing: TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitEditScreen(graveId: widget.graveId))),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj'),
              ),
            ),
            if (_visits.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Brak wpisów', style: TextStyle(color: cs.onSurfaceVariant))),
            for (final v in _visits)
              ListTile(
                leading: Icon(visitIcon(v.actions.isEmpty ? '' : v.actions.first)),
                title: Text('${fmtLong(v.dateTime)}${v.by == null || v.by!.isEmpty ? '' : ' · ${v.by}'}'),
                subtitle: Text([if (v.actions.isNotEmpty) v.actions.join(', '), if ((v.note ?? '').isNotEmpty) v.note!].join('\n')),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitEditScreen(graveId: widget.graveId, visit: v))),
              ),
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final Person p;
  final int memories;
  const _PersonCard(this.p, {this.memories = 0});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = <String>[];
    if (p.birth != null) lines.add('ur. ${fmtPartialLong(p.birth!)}');
    if (p.death != null) lines.add('zm. ${fmtPartialLong(p.death!)}${p.age != null ? ' (${p.age} ${yearsWord(p.age!)})' : ''}');
    if (p.burial != null) lines.add('pogrzeb ${fmtPartialLong(p.burial!)}');
    if (p.death?.isFull == true) {
      final yearsAgo = DateTime.now().year - p.death!.year;
      if (yearsAgo > 0) lines.add('od śmierci: $yearsAgo ${yearsWord(yearsAgo)}');
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.fullName, style: Theme.of(context).textTheme.titleMedium)),
            if ((p.relation ?? '').isNotEmpty) Chip(label: Text(p.relation!), visualDensity: VisualDensity.compact),
          ]),
          if (lines.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(lines.join('\n'), style: TextStyle(color: cs.onSurfaceVariant))),
          if ((p.inscription ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(p.inscription!, style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          if ((p.notes ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(p.notes!)),
          const SizedBox(height: 6),
          Wrap(spacing: 4, children: [
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MemoriesScreen(person: p))),
              icon: const Icon(Icons.auto_stories_outlined, size: 18),
              label: Text(memories > 0 ? 'Wspomnienia ($memories)' : 'Wspomnienia'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FamilyTreeScreen(person: p))),
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Drzewo'),
            ),
            TextButton.icon(
              onPressed: () => showGeneteka(context, p),
              icon: const Icon(Icons.manage_search, size: 18),
              label: const Text('Geneteka'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _FeeTile extends StatelessWidget {
  final PartialDate fee;
  const _FeeTile(this.fee);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final end = DateTime(fee.year, fee.month ?? 12, fee.day ?? 28);
    final days = end.difference(DateTime.now()).inDays;
    final warn = days < 180;
    return ListTile(
      leading: Icon(Icons.receipt_long_outlined, color: warn ? cs.error : null),
      title: Text('Opłata za miejsce do ${fee.format()}'),
      subtitle: Text(days < 0 ? 'Opłata wygasła – skontaktuj się z zarządcą cmentarza' : (warn ? 'Kończy się za $days dni' : 'Jeszcze ${(days / 365).floor()} ${yearsWord((days / 365).floor())}'),
          style: TextStyle(color: warn ? cs.error : null)),
    );
  }
}

Future<List<XFile>> _one(ImageSource src) async {
  final x = await ImagePicker().pickImage(source: src, maxWidth: 2600, imageQuality: 88);
  return x == null ? const [] : [x];
}
