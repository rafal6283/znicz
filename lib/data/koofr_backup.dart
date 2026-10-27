import 'dart:io';

import 'package:koofr_backup_ui/koofr_backup_ui.dart' show BackupAdapter, BackupBlob, BackupContent, KoofrConfig, KoofrException, RestoredBackup;
import 'package:path/path.dart' as p;

import '../sync/sync_service.dart';
import 'db.dart';

/// Kopia Znicza na rodzinnym Koofr: baza jako dane, zdjęcia jako załączniki wysyłane raz.
class ZniczBackup extends BackupAdapter {
  @override
  String get appId => 'znicz';
  @override
  String get appName => 'Znicz';
  @override
  String get contentNote => 'W kopii są groby, osoby, wizyty, cmentarze i zdjęcia (to, co widać na tym telefonie).';

  @override
  Future<BackupContent> export() async {
    final db = AppDb.I;
    await db.close();
    List<int> dbBytes;
    try {
      dbBytes = await File(db.dbPath).readAsBytes();
    } finally {
      await db.reopen();
    }
    final blobs = <BackupBlob>[];
    if (await db.photosDir.exists()) {
      await for (final e in db.photosDir.list(recursive: true)) {
        if (e is File) blobs.add(BackupBlob(p.relative(e.path, from: db.root.path), e.readAsBytes));
      }
    }
    return BackupContent(dbBytes, blobs);
  }

  @override
  Future<void> import(RestoredBackup r, void Function(String step) progress) async {
    final db = AppDb.I;
    if (r.data.length < 16 || String.fromCharCodes(r.data.sublist(0, 15)) != 'SQLite format 3') {
      throw KoofrException('Kopia nie zawiera bazy Znicza.');
    }
    final tmp = Directory(p.join(db.root.path, 'zdjecia.przywracanie'));
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await tmp.create(recursive: true);
    var i = 0;
    for (final e in r.blobs.entries) {
      progress('Zdjęcia: ${++i} z ${r.blobs.length}');
      if (!e.key.startsWith('zdjecia/') || e.key.contains('..')) continue;
      final dest = File(p.join(tmp.path, p.relative(e.key, from: 'zdjecia')));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await r.blob(e.value), flush: true);
    }
    progress('Zapisywanie…');
    await db.close();
    final cur = File(db.dbPath);
    if (await cur.exists()) await cur.copy('${db.dbPath}.przed-przywroceniem');
    await cur.writeAsBytes(r.data, flush: true);
    if (await db.photosDir.exists()) await db.photosDir.delete(recursive: true);
    await tmp.rename(db.photosDir.path);
    await db.reopen();
  }
}

/// Jeśli synchronizacja rodzinna działa na Koofr, te same dane logowania podpowiadamy dla kopii.
Future<KoofrConfig?> koofrFromFamilySync() async {
  final c = await SyncConfig.load();
  if (!c.isSet || !c.url.contains('koofr.net') || c.user.isEmpty || c.password.isEmpty) return null;
  return KoofrConfig(email: c.user, appPassword: c.password);
}
