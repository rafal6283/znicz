import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'models.dart';

class Storage {
  static final _rnd = Random();

  static String _newName(String ext) => '${DateTime.now().millisecondsSinceEpoch}_${_rnd.nextInt(1 << 30)}$ext';

  /// Kopiuje zdjęcie do katalogu aplikacji; zwraca ścieżkę względną.
  static Future<String> importPhoto(String sourcePath) async {
    var ext = p.extension(sourcePath).toLowerCase();
    if (ext.isEmpty) ext = '.jpg';
    final rel = p.join('zdjecia', _newName(ext));
    final dest = File(AppDb.I.absPath(rel));
    await dest.parent.create(recursive: true);
    await File(sourcePath).copy(dest.path);
    return rel;
  }

  static Future<String> importPhotoBytes(List<int> bytes, String ext) async {
    final rel = p.join('zdjecia', _newName(ext));
    final dest = File(AppDb.I.absPath(rel));
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes, flush: true);
    return rel;
  }

  static Future<GravePhoto> addPhoto(int graveId, String sourcePath, {String? caption, int? taken, bool? cover}) async {
    final rel = await importPhoto(sourcePath);
    final existing = await AppDb.I.photos(graveId);
    final ph = GravePhoto(graveId: graveId, path: rel, caption: caption, taken: taken, cover: cover ?? existing.isEmpty);
    await AppDb.I.savePhoto(ph);
    return ph;
  }

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  // ---------- kopia zapasowa całości ----------

  static Future<Uint8List> buildBackup() async {
    final db = AppDb.I;
    await db.close();
    try {
      final archive = Archive();
      final dbBytes = await File(db.dbPath).readAsBytes();
      archive.addFile(ArchiveFile('znicz.db', dbBytes.length, dbBytes));
      if (await db.photosDir.exists()) {
        await for (final e in db.photosDir.list()) {
          if (e is File) {
            final b = await e.readAsBytes();
            archive.addFile(ArchiveFile('zdjecia/${p.basename(e.path)}', b.length, b));
          }
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(archive));
    } finally {
      await db.reopen();
    }
  }

  static Future<bool> exportBackup() async {
    final bytes = await buildBackup();
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Zapisz kopię zapasową', fileName: 'znicz-kopia-${_stamp()}.zip', bytes: bytes);
    return path != null;
  }

  static Future<Uint8List?> _pickBytes() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    return f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
  }

  /// Przywraca kopię (zastępuje wszystkie dane). Zwraca komunikat błędu albo null.
  static Future<String?> importBackup() async {
    final bytes = await _pickBytes();
    if (bytes == null) return 'Anulowano';
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return 'To nie jest plik kopii zapasowej (.zip)';
    }
    if (!archive.files.any((e) => e.name == 'znicz.db')) {
      if (archive.files.any((e) => e.name == 'grob.json')) return 'To jest plik pojedynczego grobu – użyj „Importuj grób”.';
      return 'W archiwum brakuje bazy danych znicz.db';
    }
    final db = AppDb.I;
    await db.close();
    if (await db.photosDir.exists()) await db.photosDir.delete(recursive: true);
    await db.photosDir.create(recursive: true);
    for (final e in archive.files) {
      if (!e.isFile) continue;
      if (e.name == 'znicz.db') {
        await File(db.dbPath).writeAsBytes(e.content as List<int>, flush: true);
      } else if (e.name.startsWith('zdjecia/') && !e.name.contains('..')) {
        await File(p.join(db.photosDir.path, p.basename(e.name))).writeAsBytes(e.content as List<int>, flush: true);
      }
    }
    await db.reopen();
    return null;
  }

  // ---------- pojedynczy grób (do przekazania rodzinie) ----------

  static Future<File> exportGraveFile(int graveId, {required String tempDir}) async {
    final db = AppDb.I;
    final g = await db.grave(graveId);
    if (g == null) throw StateError('Brak grobu');
    final cem = g.cemeteryId == null ? null : await db.cemetery(g.cemeteryId!);
    final people = await db.people(graveId);
    final photos = await db.photos(graveId);
    final archive = Archive();
    final photoEntries = <Map<String, Object?>>[];
    for (final ph in photos) {
      final f = File(db.absPath(ph.path));
      if (!await f.exists()) continue;
      final b = await f.readAsBytes();
      final name = 'zdjecia/${p.basename(ph.path)}';
      archive.addFile(ArchiveFile(name, b.length, b));
      photoEntries.add({...ph.toMap()..remove('id')..remove('grave_id'), 'path': name});
    }
    final json = {
      'format': 'znicz-grob',
      'version': 1,
      'cemetery': cem?.toMap()?..remove('id'),
      'grave': g.toMap()..remove('id')..remove('cemetery_id'),
      'people': people.where((x) => !x.deleted).map((x) => x.toMap()..remove('id')..remove('grave_id')).toList(),
      'photos': photoEntries,
    };
    final jb = utf8.encode(const JsonEncoder.withIndent(' ').convert(json));
    archive.addFile(ArchiveFile('grob.json', jb.length, jb));
    final title = people.isEmpty ? 'grob' : people.map((x) => x.lastName.isEmpty ? x.firstName : x.lastName).toSet().join('-');
    final safe = title.replaceAll(RegExp(r'[^\p{L}\p{N}\-]+', unicode: true), '_');
    final out = File(p.join(tempDir, 'grob-$safe.znicz'));
    await out.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return out;
  }

  /// Importuje grób z pliku .znicz. Zwraca id nowego grobu albo rzuca wyjątek z opisem błędu.
  static Future<int?> importGraveFile() async {
    final bytes = await _pickBytes();
    if (bytes == null) return null;
    return importGraveBytes(bytes);
  }

  static Future<int> importGraveBytes(Uint8List bytes) async {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('To nie jest plik grobu (.znicz)');
    }
    final jf = archive.files.where((e) => e.name == 'grob.json').toList();
    if (jf.isEmpty) throw const FormatException('W pliku brakuje opisu grobu');
    final json = jsonDecode(utf8.decode(jf.first.content as List<int>)) as Map<String, dynamic>;
    if (json['format'] != 'znicz-grob') throw const FormatException('Nieznany format pliku');
    final db = AppDb.I;

    int? cemId;
    final cm = json['cemetery'] as Map<String, dynamic>?;
    if (cm != null) {
      final incoming = Cemetery.fromMap({...Map<String, Object?>.from(cm), 'uid': null, 'updated': null, 'deleted': 0});
      // ten sam cmentarz już jest? (nazwa albo pozycja w promieniu ~300 m)
      for (final c in await db.cemeteries()) {
        final sameName = c.name.toLowerCase().trim() == incoming.name.toLowerCase().trim();
        final near = c.hasLocation && incoming.hasLocation && (c.lat! - incoming.lat!).abs() < 0.003 && (c.lng! - incoming.lng!).abs() < 0.004;
        if (sameName || near) {
          cemId = c.id;
          break;
        }
      }
      cemId ??= await db.saveCemetery(incoming);
    }
    final g = Grave.fromMap({...Map<String, Object?>.from(json['grave'] as Map), 'id': null, 'cemetery_id': cemId, 'uid': null, 'updated': null, 'deleted': 0});
    final gid = await db.saveGrave(g, notify: false);
    for (final pm in (json['people'] as List? ?? const [])) {
      await db.savePerson(Person.fromMap({...Map<String, Object?>.from(pm as Map), 'id': null, 'grave_id': gid, 'uid': null, 'updated': null}), notify: false);
    }
    for (final phm in (json['photos'] as List? ?? const [])) {
      final m = Map<String, Object?>.from(phm as Map);
      final entry = archive.files.where((e) => e.name == m['path']).toList();
      if (entry.isEmpty) continue;
      final rel = await importPhotoBytes(entry.first.content as List<int>, p.extension(m['path'] as String));
      await db.savePhoto(GravePhoto.fromMap({...m, 'id': null, 'grave_id': gid, 'path': rel, 'uid': null, 'updated': null}), notify: false);
    }
    db.changed();
    return gid;
  }
}
