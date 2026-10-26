import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/notifications.dart';
import 'bundle.dart';
import 'webdav.dart';

/// Ustawienia synchronizacji rodzinnej.
class SyncConfig {
  String url;
  String user;
  String password;
  bool allowSelfSigned;
  String myName; // podpis przy wizytach („Rafał”)

  SyncConfig({this.url = '', this.user = '', this.password = '', this.allowSelfSigned = false, this.myName = ''});

  bool get isSet => url.trim().isNotEmpty;

  static const _secure = FlutterSecureStorage();

  static Future<SyncConfig> load() async {
    final p = await SharedPreferences.getInstance();
    String pass = '';
    try {
      pass = await _secure.read(key: 'sync_pass') ?? '';
    } catch (_) {}
    return SyncConfig(
      url: p.getString('sync_url') ?? '',
      user: p.getString('sync_user') ?? '',
      password: pass,
      allowSelfSigned: p.getBool('sync_self_signed') ?? false,
      myName: p.getString('sync_name') ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sync_url', url.trim());
    await p.setString('sync_user', user.trim());
    await p.setBool('sync_self_signed', allowSelfSigned);
    await p.setString('sync_name', myName.trim());
    try {
      await _secure.write(key: 'sync_pass', value: password);
    } catch (_) {}
  }

  /// Kod zaproszenia dla rodziny (adres + login + hasło), do wklejenia w ich aplikacji.
  String inviteCode() {
    final j = jsonEncode({'u': url.trim(), 'l': user.trim(), 'p': password, 's': allowSelfSigned});
    return 'ZNICZ1-${base64Url.encode(utf8.encode(j)).replaceAll('=', '')}';
  }

  static SyncConfig? fromInvite(String code) {
    final m = RegExp(r'ZNICZ1-([A-Za-z0-9_\-]+)').firstMatch(code.replaceAll(RegExp(r'\s'), ''));
    if (m == null) return null;
    try {
      var b = m.group(1)!;
      while (b.length % 4 != 0) {
        b += '=';
      }
      final j = jsonDecode(utf8.decode(base64Url.decode(b))) as Map<String, dynamic>;
      return SyncConfig(url: j['u'] as String? ?? '', user: j['l'] as String? ?? '', password: j['p'] as String? ?? '', allowSelfSigned: j['s'] == true);
    } catch (_) {
      return null;
    }
  }
}

class SyncStats {
  int pulled = 0;
  int pushed = 0;
  int photosUp = 0;
  int photosDown = 0;
  @override
  String toString() {
    final parts = <String>[];
    if (pulled > 0) parts.add('pobrano zmian: $pulled');
    if (pushed > 0) parts.add('wysłano: $pushed');
    if (photosUp + photosDown > 0) parts.add('zdjęcia ↑$photosUp ↓$photosDown');
    return parts.isEmpty ? 'wszystko aktualne' : parts.join(', ');
  }
}

/// Synchronizacja przez WebDAV (np. Synology NAS). Na serwerze:
/// `cmentarze/UID.json`, `groby/UID.json` (z osobami, zdjęciami i wizytami), `zdjecia/UID.jpg`
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService I = SyncService._();

  bool running = false;
  DateTime? lastSync;
  String? lastError;
  String? lastResult;
  Timer? _debounce;
  bool _again = false;

  Future<void> loadStatus() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getInt('sync_last');
    lastSync = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
    lastError = p.getString('sync_error');
    notifyListeners();
  }

  /// Po lokalnej zmianie: synchronizuj za kilka sekund (kolejne zmiany przesuwają termin).
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () => syncNow(quiet: true));
  }

  Future<String?> syncNow({bool quiet = false}) async {
    final cfg = await SyncConfig.load();
    if (!cfg.isSet) return 'Synchronizacja nie jest skonfigurowana';
    if (running) {
      _again = true;
      return null;
    }
    running = true;
    lastError = null;
    notifyListeners();
    final dav = WebDav(cfg.url, cfg.user, cfg.password, allowSelfSigned: cfg.allowSelfSigned);
    final prefs = await SharedPreferences.getInstance();
    try {
      final stats = await _run(dav);
      lastSync = DateTime.now();
      lastResult = stats.toString();
      await prefs.setInt('sync_last', lastSync!.millisecondsSinceEpoch);
      await prefs.remove('sync_error');
      if (stats.pulled > 0 || stats.photosDown > 0) {
        AppDb.I.refreshed();
        Notifications.reschedule();
      }
      return null;
    } catch (e) {
      lastError = '$e';
      await prefs.setString('sync_error', lastError!);
      if (!quiet) debugPrint('Synchronizacja: $e');
      return lastError;
    } finally {
      dav.close();
      running = false;
      notifyListeners();
      if (_again) {
        _again = false;
        schedule();
      }
    }
  }

  /// Sprawdza połączenie i przygotowuje foldery.
  /// Zawartość folderu synchronizacji; gdy go nie ma – próbuje go utworzyć.
  static Future<List<DavEntry>?> _openRoot(WebDav dav) async {
    final root = await dav.list('');
    if (root != null) return root;
    try {
      await dav.mkcol('');
    } catch (_) {}
    return dav.list('');
  }

  /// Podpowiedź, gdy folderu nie ma: co faktycznie jest piętro wyżej.
  static Future<String> _missingHelp(SyncConfig cfg) async {
    final base = WebDav.normalizeBase(cfg.url);
    final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final name = segs.isEmpty ? '' : segs.last;
    final parent = base.resolve('..');
    final dav = WebDav(parent.toString(), cfg.user, cfg.password, allowSelfSigned: cfg.allowSelfSigned);
    try {
      final items = await dav.list('');
      if (items == null) {
        return 'Nie ma folderu „$name” ani folderu nadrzędnego ${Uri.decodeFull(parent.path)}. Sprawdź adres.';
      }
      final dirs = items.where((e) => e.isDir).map((e) => e.name).toList();
      return 'Nie udało się otworzyć ani utworzyć folderu „$name”. '
          '${dirs.isEmpty ? 'W ${Uri.decodeFull(parent.path)} nie ma żadnych folderów.' : 'W ${Uri.decodeFull(parent.path)} są foldery: ${dirs.join(', ')}.'} '
          'Wielkość liter ma znaczenie – popraw adres albo utwórz folder „$name”.';
    } catch (e) {
      return 'Folder „$name” nie istnieje i nie udało się go utworzyć ($e).';
    } finally {
      dav.close();
    }
  }

  static Future<String?> test(SyncConfig cfg) async {
    final dav = WebDav(cfg.url, cfg.user, cfg.password, allowSelfSigned: cfg.allowSelfSigned);
    try {
      final root = await _openRoot(dav);
      if (root == null) return await _missingHelp(cfg);
      for (final d in ['cmentarze', 'groby', 'zdjecia']) {
        if (!root.any((e) => e.isDir && e.name == d)) await dav.mkcol(d);
      }
      return null;
    } catch (e) {
      return '$e';
    } finally {
      dav.close();
    }
  }

  // ---------------------------------------------------------------------------

  Future<SyncStats> _run(WebDav dav) async {
    final db = AppDb.I;
    final stats = SyncStats();
    final root = await _openRoot(dav);
    if (root == null) throw DavException(await _missingHelp(await SyncConfig.load()));
    for (final d in ['cmentarze', 'groby', 'zdjecia']) {
      if (!root.any((e) => e.isDir && e.name == d)) await dav.mkcol(d);
    }

    // 1. cmentarze: pobierz zmienione, scal, wyślij lokalne zmiany
    final remoteC = {for (final e in (await dav.list('cmentarze')) ?? <DavEntry>[]) if (e.name.endsWith('.json')) e.name: e};
    for (final e in remoteC.values) {
      final key = 'c/${e.name}';
      final (etag, _) = await db.syncState(key);
      if (etag != null && etag == e.etag) continue;
      final got = await dav.get('cmentarze/${e.name}');
      if (got == null) continue;
      final m = Map<String, Object?>.from(jsonDecode(utf8.decode(got.$1)) as Map);
      if (await _mergeRecord('cemeteries', m)) stats.pulled++;
      await db.setSyncState(key, etag: e.etag ?? got.$2, fp: fingerprintOf([m]));
    }
    for (final c in await db.cemeteries(withDeleted: true)) {
      final name = '${c.uid}.json';
      final key = 'c/$name';
      final m = c.toMap()..remove('id');
      final fp = fingerprintOf([m]);
      final (etag, rfp) = await db.syncState(key);
      if (rfp == fp) continue;
      final newEtag = await _putWithRetry(dav, 'cmentarze/$name', utf8.encode(jsonEncode(m)), etag, exists: remoteC.containsKey(name), onConflict: () async {
        final got = await dav.get('cmentarze/$name');
        if (got != null) await _mergeRecord('cemeteries', Map<String, Object?>.from(jsonDecode(utf8.decode(got.$1)) as Map));
        final fresh = (await db.cemeteries(withDeleted: true)).firstWhere((x) => x.uid == c.uid);
        return utf8.encode(jsonEncode(fresh.toMap()..remove('id')));
      });
      await db.setSyncState(key, etag: newEtag ?? '', fp: fp);
      stats.pushed++;
    }

    // 2. groby
    final remoteG = {for (final e in (await dav.list('groby')) ?? <DavEntry>[]) if (e.name.endsWith('.json')) e.name: e};
    for (final e in remoteG.values) {
      final key = 'g/${e.name}';
      final (etag, _) = await db.syncState(key);
      if (etag != null && etag == e.etag) continue;
      final got = await dav.get('groby/${e.name}');
      if (got == null) continue;
      final b = GraveBundle.decode(got.$1);
      stats.pulled += await _mergeBundle(b);
      await db.setSyncState(key, etag: e.etag ?? got.$2, fp: b.fingerprint);
    }
    final graveRows = await db.db.query('graves', columns: ['id', 'uid']);
    for (final r in graveRows) {
      final gid = r['id'] as int;
      final uid = r['uid'] as String;
      final name = '$uid.json';
      final key = 'g/$name';
      final b = await _buildBundle(gid);
      final (etag, rfp) = await db.syncState(key);
      if (rfp == b.fingerprint) continue;
      final newEtag = await _putWithRetry(dav, 'groby/$name', b.encode(), etag, exists: remoteG.containsKey(name), onConflict: () async {
        final got = await dav.get('groby/$name');
        if (got != null) await _mergeBundle(GraveBundle.decode(got.$1));
        return (await _buildBundle(gid)).encode();
      });
      final sent = await _buildBundle(gid);
      await db.setSyncState(key, etag: newEtag ?? '', fp: sent.fingerprint);
      stats.pushed++;
    }

    // 3. zdjęcia: wyślij brakujące na serwerze, pobierz brakujące lokalnie, usuń skasowane
    final uploaded = await db.syncKeys('p/');
    final remoteP = {for (final e in (await dav.list('zdjecia')) ?? <DavEntry>[]) e.name};
    for (final r in await db.db.query('photos')) {
      final ph = GravePhoto.fromMap(r);
      final file = _photoFileName(ph);
      final key = 'p/$file';
      if (ph.deleted) {
        if (uploaded.contains(key) || remoteP.contains(file)) {
          try {
            await dav.delete('zdjecia/$file');
          } catch (_) {}
          await db.removeSyncState(key);
        }
        continue;
      }
      final local = File(db.absPath(ph.path));
      final exists = await local.exists();
      if (exists && !remoteP.contains(file)) {
        await dav.put('zdjecia/$file', await local.readAsBytes(), contentType: _mime(file));
        await db.setSyncState(key, etag: '', fp: 'ok');
        stats.photosUp++;
      } else if (!exists && remoteP.contains(file)) {
        final got = await dav.get('zdjecia/$file');
        if (got != null) {
          final rel = p.join('zdjecia', file);
          final f = File(db.absPath(rel));
          await f.parent.create(recursive: true);
          await f.writeAsBytes(got.$1, flush: true);
          if (ph.path != rel) await db.db.update('photos', {'path': rel}, where: 'id=?', whereArgs: [ph.id]);
          await db.setSyncState(key, etag: '', fp: 'ok');
          stats.photosDown++;
        }
      } else if (exists && !uploaded.contains(key)) {
        await db.setSyncState(key, etag: '', fp: 'ok');
      }
    }
    return stats;
  }

  static String _photoFileName(GravePhoto ph) {
    var ext = p.extension(ph.path).toLowerCase();
    if (ext.isEmpty || ext.length > 5) ext = '.jpg';
    return '${ph.uid}$ext';
  }

  static String _mime(String name) {
    final e = p.extension(name).toLowerCase();
    if (e == '.png') return 'image/png';
    if (e == '.heic') return 'image/heic';
    if (e == '.webp') return 'image/webp';
    return 'image/jpeg';
  }

  /// PUT z kontrolą wersji: gdy ktoś inny zmienił plik w międzyczasie – pobierz, scal i wyślij ponownie.
  Future<String?> _putWithRetry(WebDav dav, String rel, List<int> body, String? etag,
      {required bool exists, required Future<List<int>> Function() onConflict}) async {
    var data = body;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final known = etag != null && etag.isNotEmpty;
        return await dav.put(rel, data,
            ifMatch: exists && known ? etag : null, ifNoneMatch: !exists && attempt == 0, contentType: 'application/json; charset=utf-8');
      } on PreconditionFailed {
        data = await onConflict();
        exists = true;
        etag = null; // po scaleniu wysyłamy bez warunku – zawiera już zmiany drugiej osoby
      }
    }
    return dav.put(rel, data, contentType: 'application/json; charset=utf-8');
  }

  Future<GraveBundle> _buildBundle(int graveId) async {
    final db = AppDb.I.db;
    final g = Map<String, Object?>.from((await db.query('graves', where: 'id=?', whereArgs: [graveId])).first);
    final cid = g.remove('cemetery_id') as int?;
    g.remove('id');
    g['cemetery_uid'] = cid == null ? null : await AppDb.I.uidForId('cemeteries', cid);
    Future<List<Map<String, Object?>>> kids(String table) async => [
          for (final r in await db.query(table, where: 'grave_id=?', whereArgs: [graveId]))
            Map<String, Object?>.from(r)
              ..remove('id')
              ..remove('grave_id'),
        ];
    final photos = await kids('photos');
    for (final ph in photos) {
      ph['file'] = _photoFileName(GravePhoto(graveId: 0, path: ph['path'] as String, uid: ph['uid'] as String));
      ph.remove('path');
    }
    return GraveBundle(g, await kids('people'), photos, await kids('visits'));
  }

  /// Scala rekord z serwera z lokalnym. Zwraca true, gdy coś zmieniono.
  Future<bool> _mergeRecord(String table, Map<String, Object?> remote, {Map<String, Object?> fixed = const {}}) async {
    final db = AppDb.I.db;
    final uid = remote['uid'] as String?;
    if (uid == null) return false;
    final rows = await db.query(table, where: 'uid=?', whereArgs: [uid]);
    final local = rows.isEmpty ? null : rows.first;
    if (!remoteWins(remote, local)) return false;
    final data = Map<String, Object?>.from(remote)
      ..remove('id')
      ..addAll(fixed);
    // tylko kolumny istniejące w tabeli (starsze/nowsze wersje aplikacji)
    final cols = (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).toSet();
    data.removeWhere((k, _) => !cols.contains(k));
    if (local == null) {
      await db.insert(table, data);
    } else {
      await db.update(table, data, where: 'id=?', whereArgs: [local['id']]);
    }
    return true;
  }

  Future<int> _mergeBundle(GraveBundle b) async {
    final db = AppDb.I;
    var changes = 0;
    final g = Map<String, Object?>.from(b.grave);
    final cUid = g.remove('cemetery_uid') as String?;
    final cid = cUid == null ? null : await db.idForUid('cemeteries', cUid);
    if (await _mergeRecord('graves', g, fixed: {'cemetery_id': cid})) changes++;
    final gid = await db.idForUid('graves', b.uid);
    if (gid == null) return changes;
    for (final m in b.people) {
      if (await _mergeRecord('people', m, fixed: {'grave_id': gid})) changes++;
    }
    for (final m in b.visits) {
      if (await _mergeRecord('visits', m, fixed: {'grave_id': gid})) changes++;
    }
    for (final m in b.photos) {
      final file = m['file'] as String? ?? '${m['uid']}.jpg';
      final existing = await db.db.query('photos', where: 'uid=?', whereArgs: [m['uid']]);
      final path = existing.isEmpty ? p.join('zdjecia', file) : existing.first['path'] as String;
      final r = Map<String, Object?>.from(m)..remove('file');
      if (await _mergeRecord('photos', r, fixed: {'grave_id': gid, 'path': path})) {
        changes++;
        if ((m['deleted'] as num? ?? 0) == 1) {
          try {
            await File(db.absPath(path)).delete();
          } catch (_) {}
        }
      }
    }
    // grób usunięty przez kogoś z rodziny – usuń też lokalne pliki zdjęć
    if ((g['deleted'] as num? ?? 0) == 1) {
      for (final r in await db.db.query('photos', where: 'grave_id=?', whereArgs: [gid])) {
        try {
          await File(db.absPath(r['path'] as String)).delete();
        } catch (_) {}
      }
    }
    return changes;
  }
}
