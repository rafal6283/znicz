import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import 'photo_viewer.dart';

/// Stan grobu rok po roku: zdjęcia pogrupowane według lat i porównanie dwóch lat obok siebie –
/// łatwo zauważyć pękniętą płytę, zatarty napis czy przechylony pomnik.
class GraveYearsScreen extends StatefulWidget {
  final String title;
  final List<GravePhoto> photos;
  const GraveYearsScreen({super.key, required this.title, required this.photos});

  @override
  State<GraveYearsScreen> createState() => _GraveYearsScreenState();
}

/// Zdjęcia według roku wykonania (najnowsze lata pierwsze, w roku najnowsze zdjęcie pierwsze).
Map<int, List<GravePhoto>> photosByYear(List<GravePhoto> photos) {
  final m = <int, List<GravePhoto>>{};
  for (final p in [...photos]..sort((a, b) => b.taken.compareTo(a.taken))) {
    m.putIfAbsent(DateTime.fromMillisecondsSinceEpoch(p.taken).year, () => []).add(p);
  }
  return Map.fromEntries(m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
}

class _GraveYearsScreenState extends State<GraveYearsScreen> {
  late final Map<int, List<GravePhoto>> _years = photosByYear(widget.photos);
  late int _a = _years.keys.last; // najstarszy
  late int _b = _years.keys.first; // najnowszy

  Widget _img(GravePhoto p, {double? height}) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(photos: widget.photos, initial: widget.photos.indexOf(p)))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(AppDb.I.absPath(p.path)), height: height, fit: BoxFit.cover, cacheWidth: 900,
              errorBuilder: (_, __, ___) => Container(height: height ?? 120, color: Colors.black12, child: const Icon(Icons.broken_image_outlined))),
        ),
      );

  Widget _pick(int value, ValueChanged<int> on) => DropdownButton<int>(
        value: value,
        isExpanded: true,
        items: [for (final y in _years.keys) DropdownMenuItem(value: y, child: Text('$y'))],
        onChanged: (v) => v == null ? null : on(v),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now().year;
    return Scaffold(
      appBar: AppBar(title: Text('Rok po roku · ${widget.title}')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (!_years.containsKey(now))
          Card(
            color: cs.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: Text('Brak zdjęcia z $now'),
              subtitle: const Text('Zrób zdjęcie przy najbliższej wizycie – z tego samego miejsca co poprzednio, łatwiej porównać.'),
            ),
          ),
        if (_years.length >= 2) ...[
          Text('Porównanie', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: [_pick(_a, (v) => setState(() => _a = v)), _img(_years[_a]!.first, height: 220)])),
            const SizedBox(width: 8),
            Expanded(child: Column(children: [_pick(_b, (v) => setState(() => _b = v)), _img(_years[_b]!.first, height: 220)])),
          ]),
          const SizedBox(height: 20),
        ],
        for (final e in _years.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text('${e.key} · ${e.value.length} ${e.value.length == 1 ? 'zdjęcie' : 'zdjęć'}', style: Theme.of(context).textTheme.titleSmall),
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: e.value.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(width: 120, child: _img(e.value[i], height: 120)),
            ),
          ),
        ],
      ]),
    );
  }
}
