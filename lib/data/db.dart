import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Centralny dostęp do danych + powiadamianie ekranów o zmianach.
///
/// Rekordy nie są kasowane, tylko oznaczane jako usunięte (`deleted=1`) – dzięki temu usunięcie
/// dociera przez synchronizację do pozostałych członków rodziny.
class AppDb extends ChangeNotifier {
  AppDb._();
  static final AppDb I = AppDb._();

  Database? _db;
  late Directory root;
  String initStage = '';

  /// Wywoływane po każdej lokalnej zmianie danych (uruchamia synchronizację w tle).
  VoidCallback? onLocalChange;

  Database get db => _db!;
  Directory get photosDir => Directory(p.join(root.path, 'zdjecia'));
  String get dbPath => p.join(root.path, 'znicz.db');
  String absPath(String rel) => p.join(root.path, rel);

  static const _live = 'deleted=0';

  Future<void> init() async {
    initStage = 'katalog dokumentów';
    root = await getApplicationDocumentsDirectory();
    initStage = 'folder zdjęć';
    await photosDir.create(recursive: true);
    initStage = 'baza danych';
    await _open();
    initStage = 'gotowe';
  }

  Future<void> _open() async {
    _db = await openDatabase(
      dbPath,
      version: 2,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (d, from, to) async {
        if (from < 2) {
          await d.execute('ALTER TABLE cemeteries ADD COLUMN osm_id TEXT');
          await d.execute('ALTER TABLE cemeteries ADD COLUMN outline TEXT');
          await d.execute('ALTER TABLE graves ADD COLUMN osm_id TEXT');
        }
      },
      onCreate: (d, v) async {
        const sync = 'uid TEXT NOT NULL UNIQUE, updated INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0';
        await d.execute('''CREATE TABLE cemeteries(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, town TEXT, address TEXT, lat REAL, lng REAL,
          kind TEXT, phone TEXT, hours TEXT, search_url TEXT, notes TEXT, osm_id TEXT, outline TEXT, $sync)''');
        await d.execute('''CREATE TABLE graves(
          id INTEGER PRIMARY KEY AUTOINCREMENT, cemetery_id INTEGER REFERENCES cemeteries(id) ON DELETE SET NULL,
          lat REAL, lng REAL, accuracy REAL, section TEXT, row_no TEXT, number TEXT, type TEXT, directions TEXT,
          notes TEXT, fee_until TEXT, all_saints INTEGER DEFAULT 1, favorite INTEGER DEFAULT 0, created INTEGER NOT NULL, osm_id TEXT, $sync)''');
        await d.execute('''CREATE TABLE people(
          id INTEGER PRIMARY KEY AUTOINCREMENT, grave_id INTEGER NOT NULL REFERENCES graves(id) ON DELETE CASCADE,
          first_name TEXT, last_name TEXT, maiden_name TEXT, birth TEXT, death TEXT, burial TEXT, relation TEXT,
          inscription TEXT, notes TEXT, remind_death INTEGER DEFAULT 1, remind_birth INTEGER DEFAULT 0, sort INTEGER DEFAULT 0, $sync)''');
        await d.execute('''CREATE TABLE photos(
          id INTEGER PRIMARY KEY AUTOINCREMENT, grave_id INTEGER NOT NULL REFERENCES graves(id) ON DELETE CASCADE,
          path TEXT NOT NULL, caption TEXT, taken INTEGER NOT NULL, cover INTEGER DEFAULT 0, $sync)''');
        await d.execute('''CREATE TABLE visits(
          id INTEGER PRIMARY KEY AUTOINCREMENT, grave_id INTEGER NOT NULL REFERENCES graves(id) ON DELETE CASCADE,
          date INTEGER NOT NULL, actions TEXT, note TEXT, by_name TEXT, $sync)''');
        // stan synchronizacji: co ostatnio wysłano / pobrano dla danego pliku
        await d.execute('CREATE TABLE sync_state(key TEXT PRIMARY KEY, etag TEXT, fp TEXT)');
        await d.execute('CREATE INDEX idx_people_g ON people(grave_id)');
        await d.execute('CREATE INDEX idx_photos_g ON photos(grave_id)');
        await d.execute('CREATE INDEX idx_visits_g ON visits(grave_id, date)');
        await d.execute('CREATE INDEX idx_graves_c ON graves(cemetery_id)');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> reopen() async {
    await close();
    await init();
    notifyListeners();
  }

  /// Zmiana z interfejsu (lokalna) – odśwież ekrany i zaplanuj synchronizację.
  void changed() {
    notifyListeners();
    onLocalChange?.call();
  }

  /// Zmiana z synchronizacji – tylko odśwież ekrany.
  void refreshed() => notifyListeners();

  Future<int> _upsert(String table, Map<String, Object?> m, int? id, {bool touch = true}) async {
    final data = Map<String, Object?>.from(m)..remove('id');
    if (touch) data['updated'] = nowMs();
    if (id == null) return db.insert(table, data);
    await db.update(table, data, where: 'id=?', whereArgs: [id]);
    return id;
  }

  Future<int?> idForUid(String table, String uid) async {
    final r = await db.query(table, columns: ['id'], where: 'uid=?', whereArgs: [uid]);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  Future<String?> uidForId(String table, int id) async {
    final r = await db.query(table, columns: ['uid'], where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : r.first['uid'] as String;
  }

  // ---------- cmentarze ----------

  Future<List<Cemetery>> cemeteries({bool withDeleted = false}) async =>
      (await db.query('cemeteries', where: withDeleted ? null : _live, orderBy: 'name COLLATE NOCASE')).map(Cemetery.fromMap).toList();

  Future<Cemetery?> cemetery(int id) async {
    final r = await db.query('cemeteries', where: 'id=? AND $_live', whereArgs: [id]);
    return r.isEmpty ? null : Cemetery.fromMap(r.first);
  }

  Future<int> saveCemetery(Cemetery c) async {
    c.updated = nowMs();
    c.id = await _upsert('cemeteries', c.toMap(), c.id);
    changed();
    return c.id!;
  }

  Future<void> deleteCemetery(int id) async {
    final t = nowMs();
    await db.update('cemeteries', {'deleted': 1, 'updated': t}, where: 'id=?', whereArgs: [id]);
    // groby zostają, bez cmentarza
    await db.update('graves', {'cemetery_id': null, 'updated': t}, where: 'cemetery_id=?', whereArgs: [id]);
    changed();
  }

  // ---------- groby ----------

  Future<Grave?> grave(int id) async {
    final r = await db.query('graves', where: 'id=? AND $_live', whereArgs: [id]);
    return r.isEmpty ? null : Grave.fromMap(r.first);
  }

  Future<int> saveGrave(Grave g, {bool notify = true}) async {
    g.updated = nowMs();
    g.id = await _upsert('graves', g.toMap(), g.id);
    if (notify) changed();
    return g.id!;
  }

  /// Usuwa grób (oznacza jako usunięty razem z osobami, zdjęciami i wizytami) i kasuje pliki zdjęć.
  Future<void> deleteGrave(int id) async {
    for (final ph in await photos(id)) {
      try {
        await File(absPath(ph.path)).delete();
      } catch (_) {}
    }
    final t = nowMs();
    await db.transaction((tx) async {
      await tx.update('graves', {'deleted': 1, 'updated': t}, where: 'id=?', whereArgs: [id]);
      for (final tb in ['people', 'photos', 'visits']) {
        await tx.update(tb, {'deleted': 1, 'updated': t}, where: 'grave_id=? AND deleted=0', whereArgs: [id]);
      }
    });
    changed();
  }

  /// Wszystkie groby z osobami, cmentarzem, zdjęciem tytułowym i ostatnią wizytą.
  Future<List<GraveView>> graveViews({int? onlyId}) async {
    final graves = (await db.query('graves', where: onlyId == null ? _live : 'id=? AND $_live', whereArgs: onlyId == null ? null : [onlyId]))
        .map(Grave.fromMap)
        .toList();
    final cems = {for (final c in await cemeteries()) c.id!: c};
    final people = <int, List<Person>>{};
    for (final r in await db.query('people', where: _live, orderBy: 'sort, id')) {
      final p = Person.fromMap(r);
      people.putIfAbsent(p.graveId, () => []).add(p);
    }
    final covers = <int, GravePhoto>{};
    for (final r in await db.query('photos', where: _live, orderBy: 'cover DESC, taken DESC')) {
      final ph = GravePhoto.fromMap(r);
      covers.putIfAbsent(ph.graveId, () => ph);
    }
    final visits = <int, Visit>{};
    for (final r in await db.query('visits', where: _live, orderBy: 'date ASC')) {
      final v = Visit.fromMap(r);
      visits[v.graveId] = v; // ostatnia wygrywa
    }
    return graves
        .map((g) => GraveView(g, g.cemeteryId == null ? null : cems[g.cemeteryId], people[g.id] ?? const [], covers[g.id], visits[g.id]))
        .toList();
  }

  Future<GraveView?> graveView(int id) async {
    final l = await graveViews(onlyId: id);
    return l.isEmpty ? null : l.first;
  }

  // ---------- osoby ----------

  Future<List<Person>> people(int graveId) async =>
      (await db.query('people', where: 'grave_id=? AND $_live', whereArgs: [graveId], orderBy: 'sort, id')).map(Person.fromMap).toList();

  Future<List<Person>> allPeople() async {
    final r = await db.rawQuery('SELECT p.* FROM people p JOIN graves g ON g.id=p.grave_id WHERE p.deleted=0 AND g.deleted=0');
    return r.map(Person.fromMap).toList();
  }

  Future<int> savePerson(Person p, {bool notify = true}) async {
    p.updated = nowMs();
    p.id = await _upsert('people', p.toMap(), p.id);
    if (notify) changed();
    return p.id!;
  }

  Future<void> deletePerson(int id) async {
    await db.update('people', {'deleted': 1, 'updated': nowMs()}, where: 'id=?', whereArgs: [id]);
    changed();
  }

  // ---------- zdjęcia ----------

  Future<List<GravePhoto>> photos(int graveId) async =>
      (await db.query('photos', where: 'grave_id=? AND $_live', whereArgs: [graveId], orderBy: 'cover DESC, taken DESC')).map(GravePhoto.fromMap).toList();

  Future<int> savePhoto(GravePhoto ph, {bool notify = true}) async {
    ph.updated = nowMs();
    ph.id = await _upsert('photos', ph.toMap(), ph.id);
    if (notify) changed();
    return ph.id!;
  }

  Future<void> setCover(GravePhoto ph) async {
    final t = nowMs();
    await db.update('photos', {'cover': 0, 'updated': t}, where: 'grave_id=? AND cover=1', whereArgs: [ph.graveId]);
    await db.update('photos', {'cover': 1, 'updated': t}, where: 'id=?', whereArgs: [ph.id]);
    changed();
  }

  Future<void> deletePhoto(GravePhoto ph) async {
    try {
      await File(absPath(ph.path)).delete();
    } catch (_) {}
    await db.update('photos', {'deleted': 1, 'updated': nowMs()}, where: 'id=?', whereArgs: [ph.id]);
    changed();
  }

  // ---------- wizyty ----------

  Future<List<Visit>> visits(int graveId) async =>
      (await db.query('visits', where: 'grave_id=? AND $_live', whereArgs: [graveId], orderBy: 'date DESC')).map(Visit.fromMap).toList();

  Future<List<Visit>> visitsBetween(DateTime from, DateTime to) async => (await db.query('visits',
          where: 'date>=? AND date<? AND $_live', whereArgs: [from.millisecondsSinceEpoch, to.millisecondsSinceEpoch], orderBy: 'date DESC'))
      .map(Visit.fromMap)
      .toList();

  Future<int> saveVisit(Visit v) async {
    v.updated = nowMs();
    v.id = await _upsert('visits', v.toMap(), v.id);
    changed();
    return v.id!;
  }

  Future<void> deleteVisit(int id) async {
    await db.update('visits', {'deleted': 1, 'updated': nowMs()}, where: 'id=?', whereArgs: [id]);
    changed();
  }

  Future<bool> get isEmpty async => (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM graves WHERE deleted=0')) ?? 0) == 0;

  // ---------- stan synchronizacji ----------

  /// (etag pliku na serwerze, odcisk zawartości, która jest na serwerze)
  Future<(String?, String?)> syncState(String key) async {
    final r = await db.query('sync_state', where: 'key=?', whereArgs: [key]);
    if (r.isEmpty) return (null, null);
    return (r.first['etag'] as String?, r.first['fp'] as String?);
  }

  Future<void> setSyncState(String key, {String? etag, String? fp}) async {
    final (e0, f0) = await syncState(key);
    await db.insert('sync_state', {'key': key, 'etag': etag ?? e0, 'fp': fp ?? f0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeSyncState(String key) async => db.delete('sync_state', where: 'key=?', whereArgs: [key]);

  Future<Set<String>> syncKeys(String prefix) async =>
      (await db.query('sync_state', columns: ['key'], where: 'key LIKE ?', whereArgs: ['$prefix%'])).map((r) => r['key'] as String).toSet();

  Future<void> clearSyncState() async => db.delete('sync_state');
}
