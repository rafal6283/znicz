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
import 'photo_viewer.dart';
import 'visit_edit.dart';

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
    if (mounted) {
      setState(() {
        _g = g;
        _photos = ph;
        _visits = v;
      });
    }
  }

  Future<void> _addPhoto(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2600, imageQuality: 88);
    if (x == null) return;
    await Storage.addPhoto(widget.graveId, x.path);
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
            for (final p in g.people) _PersonCard(p),
            if (g.cemetery != null || g.grave.placeLabel.isNotEmpty || (g.grave.directions ?? '').isNotEmpty) const SectionTitle('Miejsce'),
            if (g.cemetery != null)
              ListTile(
                leading: const Icon(Icons.park_outlined),
                title: Text(g.cemetery!.label),
                subtitle: (g.cemetery!.kind ?? '').isEmpty ? null : Text(g.cemetery!.kind!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: g.cemetery!.id!))),
              ),
            if (g.grave.placeLabel.isNotEmpty) ListTile(leading: const Icon(Icons.grid_on), title: Text(g.grave.placeLabel), subtitle: g.grave.type == null ? null : Text(g.grave.type!)),
            if ((g.grave.directions ?? '').isNotEmpty) ListTile(leading: const Icon(Icons.signpost_outlined), title: Text(g.grave.directions!)),
            if (g.grave.feePaidUntil != null) _FeeTile(g.grave.feePaidUntil!),
            if ((g.grave.notes ?? '').isNotEmpty) ...[
              const SectionTitle('Notatki'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(g.grave.notes!)),
            ],
            SectionTitle(
              'Zdjęcia (${_photos.length})',
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Zrób zdjęcie', onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined)),
                IconButton(tooltip: 'Z galerii', onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined)),
              ]),
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
                        child: Stack(children: [
                          PhotoThumb(_photos[i], size: 92),
                          if (_photos[i].cover) const Positioned(right: 4, top: 4, child: Icon(Icons.star, color: Colors.amber, size: 18)),
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
  const _PersonCard(this.p);
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
