import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofr_backup_ui/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:znicz/data/db.dart';
import 'package:znicz/data/koofr_backup.dart';
import 'package:znicz/data/models.dart';

/// Kopia na Koofr → nowy telefon (tylko kod odzyskiwania) → przywrócenie: groby i zdjęcia wracają.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('znicz');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (c) async => dir.path);
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HttpOverrides.global = null; // serwer WebDAV w pamięci potrzebuje prawdziwego HttpClient
  });

  test('przywrócenie kopii na czystym telefonie', () async {
    final db = AppDb.I;
    await db.init();
    await db.saveGrave(Grave(notes: 'przy alejce', section: 'B'), notify: false);
    await Directory(p.join(db.photosDir.path, 'g1')).create(recursive: true);
    await File(p.join(db.photosDir.path, 'g1', 'nagrobek.jpg')).writeAsBytes([7, 7, 7]);
    final restored = await kopiaAdapteraNaNowyTelefon(ZniczBackup());

    // „nowy telefon”: pusta baza i brak zdjęć
    await db.close();
    await File(db.dbPath).delete();
    await db.photosDir.delete(recursive: true);
    await db.init();
    expect(await db.graveViews(), isEmpty);

    await ZniczBackup().import(restored, (_) {});
    final graves = await db.graveViews();
    expect(graves.map((g) => g.grave.notes), ['przy alejce']);
    expect(await File(p.join(db.photosDir.path, 'g1', 'nagrobek.jpg')).readAsBytes(), [7, 7, 7]);
  });
}
