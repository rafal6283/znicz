import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../sync/sync_service.dart';
import 'common.dart';
import 'photo_viewer.dart';

/// Wspomnienia o osobie: zdjęcia za życia i nagrania głosowe (historie opowiadane przez rodzinę).
class MemoriesScreen extends StatefulWidget {
  final Person person;
  const MemoriesScreen({super.key, required this.person});
  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<GravePhoto> _items = [];
  final _player = AudioPlayer();
  String? _playing; // uid nagrania
  Duration _pos = Duration.zero, _dur = Duration.zero;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    _load();
    _subs
      ..add(_player.onPositionChanged.listen((d) => mounted ? setState(() => _pos = d) : null))
      ..add(_player.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null))
      ..add(_player.onPlayerComplete.listen((_) => mounted ? setState(() => _playing = null) : null));
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = await AppDb.I.memories(widget.person.uid);
    if (mounted) setState(() => _items = m);
  }

  Future<String?> _myName() async {
    final n = (await SyncConfig.load()).myName;
    return n.isEmpty ? null : n;
  }

  Future<String?> _askCaption(String title, {String hint = ''}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: VoiceField(controller: c, label: 'Opis', hint: hint, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, ''), child: const Text('Pomiń')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Zapisz')),
        ],
      ),
    );
    return r;
  }

  Future<void> _addPhoto(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2400, imageQuality: 88);
    if (x == null || !mounted) return;
    final caption = await _askCaption('Zdjęcie – opis', hint: 'np. ślub dziadków, 1956');
    final rel = await Storage.importPhoto(x.path);
    await AppDb.I.savePhoto(GravePhoto(
      graveId: widget.person.graveId,
      path: rel,
      caption: (caption ?? '').isEmpty ? null : caption,
      kind: 'portrait',
      personUid: widget.person.uid,
      by: await _myName(),
    ));
  }

  Future<void> _record() async {
    final path = await showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _RecorderSheet(),
    );
    if (path == null || !mounted) return;
    final caption = await _askCaption('Nagranie – o czym jest?', hint: 'np. babcia o wojnie, opowiada mama');
    final rel = await Storage.importPhoto(path);
    try {
      await File(path).delete();
    } catch (_) {}
    await AppDb.I.savePhoto(GravePhoto(
      graveId: widget.person.graveId,
      path: rel,
      caption: (caption ?? '').isEmpty ? null : caption,
      kind: 'audio',
      personUid: widget.person.uid,
      by: await _myName(),
    ));
  }

  Future<void> _toggle(GravePhoto a) async {
    if (_playing == a.uid) {
      await _player.pause();
      setState(() => _playing = null);
      return;
    }
    final f = File(AppDb.I.absPath(a.path));
    if (!await f.exists()) {
      if (mounted) snack(context, 'Nagranie jeszcze się pobiera – zsynchronizuj i spróbuj za chwilę');
      return;
    }
    await _player.stop();
    setState(() {
      _playing = a.uid;
      _pos = Duration.zero;
      _dur = Duration.zero;
    });
    await _player.play(DeviceFileSource(f.path));
  }

  String _t(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photos = _items.where((m) => !m.isAudio).toList();
    final audio = _items.where((m) => m.isAudio).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Wspomnienia – ${widget.person.firstName.isEmpty ? widget.person.fullName : widget.person.firstName}')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _record, icon: const Icon(Icons.mic), label: const Text('Nagraj wspomnienie')),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Zbierz to, czego nie ma na nagrobku: zdjęcia z życia i opowieści rodziny nagrane głosem. '
              'Przy synchronizacji rodzinnej wszyscy je zobaczą i usłyszą.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        SectionTitle(
          'Zdjęcia za życia (${photos.length})',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Zrób zdjęcie (np. starej fotografii)', onPressed: () => _addPhoto(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined)),
            IconButton(tooltip: 'Z galerii', onPressed: () => _addPhoto(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined)),
          ]),
        ),
        if (photos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < photos.length; i++)
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhotoViewer(photos: photos, initial: i))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    PhotoThumb(photos[i], size: 104, fallback: Icons.person_outline),
                    if (photos[i].caption != null)
                      SizedBox(width: 104, child: Text(photos[i].caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  ]),
                ),
            ]),
          ),
        SectionTitle('Nagrania (${audio.length})'),
        for (final a in audio)
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              ListTile(
                leading: IconButton.filledTonal(
                  icon: Icon(_playing == a.uid ? Icons.pause : Icons.play_arrow),
                  onPressed: () => _toggle(a),
                ),
                title: Text(a.caption ?? 'Nagranie z ${fmtDate(DateTime.fromMillisecondsSinceEpoch(a.taken))}'),
                subtitle: Text([fmtDate(DateTime.fromMillisecondsSinceEpoch(a.taken)), if (a.by != null) a.by!].join(' · ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'del' && await confirm(context, 'Usunąć nagranie?', 'Nagranie zniknie też u rodziny.')) {
                      if (_playing == a.uid) await _player.stop();
                      await AppDb.I.deletePhoto(a);
                    }
                  },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Usuń'))],
                ),
              ),
              if (_playing == a.uid)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(children: [
                    Text(_t(_pos), style: const TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: _dur.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0, 1).toDouble(),
                        onChanged: (v) => _player.seek(Duration(milliseconds: (v * _dur.inMilliseconds).round())),
                      ),
                    ),
                    Text(_t(_dur), style: const TextStyle(fontSize: 12)),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Arkusz nagrywania: start od razu, licznik czasu, „Zakończ”.
class _RecorderSheet extends StatefulWidget {
  const _RecorderSheet();
  @override
  State<_RecorderSheet> createState() => _RecorderSheetState();
}

class _RecorderSheetState extends State<_RecorderSheet> {
  final _rec = AudioRecorder();
  Timer? _timer;
  int _secs = 0;
  String? _error;
  String? _path;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'Brak dostępu do mikrofonu – zezwól w ustawieniach telefonu.');
        return;
      }
      final dir = Directory(AppDb.I.absPath('tmp'));
      await dir.create(recursive: true);
      _path = p.join(dir.path, 'nagranie_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050, numChannels: 1), path: _path!);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _secs++);
      });
    } catch (e) {
      setState(() => _error = 'Nie udało się rozpocząć nagrywania ($e)');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.mic, size: 56, color: _error == null ? cs.error : cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(_error ?? 'Nagrywam ${_secs ~/ 60}:${(_secs % 60).toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          if (_error == null) Text('Opowiadaj spokojnie – nagranie trwa, aż dotkniesz „Zakończ”.', style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await _rec.cancel();
                  } catch (_) {}
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Anuluj'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _error != null
                    ? null
                    : () async {
                        final path = await _rec.stop();
                        if (context.mounted) Navigator.pop(context, _secs >= 1 ? (path ?? _path) : null);
                      },
                icon: const Icon(Icons.stop),
                label: const Text('Zakończ'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
