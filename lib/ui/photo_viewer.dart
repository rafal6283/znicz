import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/ocr.dart';
import 'common.dart';

class PhotoViewer extends StatefulWidget {
  final List<GravePhoto> photos;
  final int initial;
  const PhotoViewer({super.key, required this.photos, this.initial = 0});
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;
  late final List<GravePhoto> _photos = [...widget.photos];

  GravePhoto get _cur => _photos[_i];

  Future<void> _readText() async {
    final path = AppDb.I.absPath(_cur.path);
    String text;
    try {
      text = await Ocr.readImage(path);
    } catch (e) {
      text = '';
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SelectableText(text.trim().isEmpty ? 'Nie znaleziono tekstu na zdjęciu.' : text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_i + 1} / ${_photos.length}'),
        actions: [
          IconButton(tooltip: 'Odczytaj napis', icon: const Icon(Icons.text_snippet_outlined), onPressed: _readText),
          IconButton(
            tooltip: 'Udostępnij',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(AppDb.I.absPath(_cur.path))])),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            onSelected: (v) async {
              if (v == 'cover') {
                await AppDb.I.setCover(_cur);
                if (context.mounted) snack(context, 'Ustawiono jako zdjęcie główne');
              } else if (v == 'del') {
                if (await confirm(context, 'Usunąć zdjęcie?', 'Zdjęcie zostanie usunięte.')) {
                  await AppDb.I.deletePhoto(_cur);
                  setState(() {
                    _photos.removeAt(_i);
                    if (_i >= _photos.length) _i = _photos.length - 1;
                  });
                  if (_photos.isEmpty && context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'cover', child: Text('Ustaw jako główne')),
              PopupMenuItem(value: 'del', child: Text('Usuń zdjęcie')),
            ],
          ),
        ],
      ),
      body: _photos.isEmpty
          ? const SizedBox()
          : PageView.builder(
              controller: _pc,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    File(AppDb.I.absPath(_photos[i].path)),
                    errorBuilder: (_, __, ___) => const Text('Zdjęcie jeszcze się pobiera (synchronizacja)', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
    );
  }
}
