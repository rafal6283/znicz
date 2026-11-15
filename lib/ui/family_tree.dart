import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/dates_pl.dart';
import '../logic/family.dart';
import 'common.dart';
import 'grave_detail.dart';

/// Wybór osoby z wszystkich zapisanych (do relacji rodzinnych).
Future<Person?> pickPerson(BuildContext context, {required String title, required List<Person> people, String? excludeUid}) {
  return showModalBottomSheet<Person>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _PersonPicker(title: title, people: people.where((p) => p.uid != excludeUid).toList()),
  );
}

class _PersonPicker extends StatefulWidget {
  final String title;
  final List<Person> people;
  const _PersonPicker({required this.title, required this.people});
  @override
  State<_PersonPicker> createState() => _PersonPickerState();
}

class _PersonPickerState extends State<_PersonPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.people.where((p) => _q.isEmpty || fold('${p.fullName} ${p.relation ?? ''}').contains(fold(_q))).toList()
      ..sort((a, b) => fold('${a.lastName} ${a.firstName}').compareTo(fold('${b.lastName} ${b.firstName}')));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Szukaj osoby'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Brak osób – najpierw dodaj je do grobów'))
                : ListView(children: [
                    for (final p in list)
                      ListTile(
                        leading: CircleAvatar(child: Text(p.firstName.isEmpty ? '?' : p.firstName[0])),
                        title: Text(p.fullName),
                        subtitle: Text([if (p.lifespan.isNotEmpty) p.lifespan, if ((p.relation ?? '').isNotEmpty) p.relation!].join(' · ')),
                        onTap: () => Navigator.pop(context, p),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Drzewo rodzinne wokół wybranej osoby: przodkowie u góry, małżonek obok, dzieci na dole.
class FamilyTreeScreen extends StatefulWidget {
  final Person person;
  const FamilyTreeScreen({super.key, required this.person});
  @override
  State<FamilyTreeScreen> createState() => _FamilyTreeScreenState();
}

class _FamilyTreeScreenState extends State<FamilyTreeScreen> {
  FamilyIndex? _idx;
  late Person _center = widget.person;

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
    final all = await AppDb.I.allPeople();
    if (!mounted) return;
    setState(() {
      _idx = FamilyIndex(all);
      _center = _idx!.byUid[_center.uid] ?? _center;
    });
  }

  Future<void> _setRelation(String which) async {
    final idx = _idx!;
    final picked = await pickPerson(context,
        title: switch (which) { 'mother' => 'Matka – ${_center.fullName}', 'father' => 'Ojciec – ${_center.fullName}', _ => 'Małżonek – ${_center.fullName}' },
        people: idx.byUid.values.toList(),
        excludeUid: _center.uid);
    if (picked == null || !mounted) return;
    if (which != 'spouse' && idx.wouldCycle(_center, picked.uid)) {
      snack(context, '${picked.fullName} nie może być rodzicem – byłby własnym przodkiem');
      return;
    }
    final p = _center;
    switch (which) {
      case 'mother':
        p.motherUid = picked.uid;
      case 'father':
        p.fatherUid = picked.uid;
      default:
        p.spouseUid = picked.uid;
    }
    await AppDb.I.savePerson(p);
  }

  Widget _card(Person? p, {String? empty, VoidCallback? onEmpty, bool center = false}) {
    final cs = Theme.of(context).colorScheme;
    if (p == null) {
      return SizedBox(
        width: 150,
        child: OutlinedButton.icon(onPressed: onEmpty, icon: const Icon(Icons.add, size: 16), label: Text(empty ?? '?', style: const TextStyle(fontSize: 12))),
      );
    }
    return SizedBox(
      width: 150,
      child: Card(
        color: center ? cs.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => center
              ? Navigator.push(context, MaterialPageRoute(builder: (_) => GraveDetailScreen(graveId: p.graveId)))
              : setState(() => _center = p),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Text(p.fullName, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (p.lifespan.isNotEmpty) Text(p.lifespan, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              if ((p.relation ?? '').isNotEmpty) Text(p.relation!, style: TextStyle(color: cs.primary, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idx = _idx;
    if (idx == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final p = _center;
    final anc = idx.ancestors(p, generations: 3);
    final spouse = idx.spouse(p);
    final kids = idx.children(p);
    const labels = ['Rodzice', 'Dziadkowie', 'Pradziadkowie'];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drzewo rodzinne'),
        actions: [
          IconButton(tooltip: 'Eksport GEDCOM', icon: const Icon(Icons.ios_share), onPressed: () => exportGedcom(context)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 32), children: [
        for (var g = anc.length - 1; g >= 0; g--) ...[
          SectionTitle(labels[g]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [for (final a in anc[g]) if (a != null) _card(a)]),
          ),
          Center(child: Icon(Icons.arrow_downward, size: 18, color: cs.outline)),
        ],
        if (anc.isEmpty || anc.first.any((e) => e == null))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              if (idx.father(p) == null) _card(null, empty: 'Dodaj ojca', onEmpty: () => _setRelation('father')),
              if (idx.mother(p) == null) _card(null, empty: 'Dodaj matkę', onEmpty: () => _setRelation('mother')),
            ]),
          ),
        Center(
          child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
            _card(p, center: true),
            if (spouse != null) ...[Icon(Icons.favorite, size: 16, color: cs.error), _card(spouse)]
            else
              _card(null, empty: 'Dodaj małżonka', onEmpty: () => _setRelation('spouse')),
          ]),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => showGeneteka(context, p),
            icon: const Icon(Icons.manage_search),
            label: const Text('Szukaj w Genetece'),
          ),
        ),
        if (kids.isNotEmpty) ...[
          Center(child: Icon(Icons.arrow_downward, size: 18, color: cs.outline)),
          const SectionTitle('Dzieci'),
          Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [for (final k in kids) _card(k)]),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Dotknij osoby, by przejść do jej drzewa. Dotknij osoby w środku, by otworzyć jej grób. '
            'Relacje ustawisz też w edycji osoby. Drzewo łączy osoby z różnych grobów.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

/// Eksport wszystkich osób i relacji do pliku GEDCOM (do programów genealogicznych).
Future<void> exportGedcom(BuildContext context) async {
  final people = await AppDb.I.allPeople();
  if (people.isEmpty) {
    if (context.mounted) snack(context, 'Brak osób do eksportu');
    return;
  }
  final views = {for (final v in await AppDb.I.graveViews()) v.grave.id!: v};
  final ged = buildGedcom(people, placeOf: (p) {
    final v = views[p.graveId];
    if (v == null) return '';
    return [v.cemetery?.label, v.grave.placeLabel].whereType<String>().where((e) => e.isNotEmpty).join(', ');
  });
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/znicz-drzewo.ged');
  await f.writeAsString(ged);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'text/plain')],
    text: 'Drzewo rodzinne z aplikacji Znicz (GEDCOM) – otworzysz je w MyHeritage, Ancestry, Gramps i innych.',
  ));
}

/// Wyszukiwanie osoby w Genetece (indeksy metrykalne parafii).
Future<void> showGeneteka(BuildContext context, Person p) async {
  final prefs = await SharedPreferences.getInstance();
  var region = prefs.getString('geneteka_region') ?? '07mz';
  var kind = p.death != null ? 'S' : 'B';
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text('Geneteka – ${p.fullName}'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Szukaj w indeksach aktów:'),
          Wrap(spacing: 6, children: [
            for (final e in {'S': 'zgonów', 'B': 'urodzeń', 'M': 'małżeństw'}.entries)
              ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: region,
            decoration: const InputDecoration(labelText: 'Województwo'),
            items: [for (final e in genetekaRegions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => set(() => region = v ?? region),
          ),
          if ((p.maidenName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Przy urodzeniu szukam nazwiska rodowego: ${p.maidenName}', style: const TextStyle(fontSize: 12)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Szukaj')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await prefs.setString('geneteka_region', region);
  final last = kind == 'B' && (p.maidenName ?? '').isNotEmpty ? p.maidenName! : p.lastName;
  final year = kind == 'S' ? p.death?.year : (kind == 'B' ? p.birth?.year : null);
  await Clipboard.setData(ClipboardData(text: '${p.firstName} $last'.trim()));
  await launchUrl(
    genetekaUri(lastName: last, firstName: p.firstName.split(' ').first, region: region, kind: kind, fromYear: year == null ? null : year - 2, toYear: year == null ? null : year + 2),
    mode: LaunchMode.externalApplication,
  );
}
