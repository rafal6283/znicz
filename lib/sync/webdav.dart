import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

class DavException implements Exception {
  final int? status;
  final String message;
  DavException(this.message, [this.status]);
  @override
  String toString() => message;
}

class PreconditionFailed extends DavException {
  PreconditionFailed() : super('Plik na serwerze zmienił się w międzyczasie', 412);
}

/// ETag bez cudzysłowów i znacznika „W/” – serwery różnie je zapisują w PROPFIND i w nagłówkach.
String? normEtag(String? e) {
  if (e == null) return null;
  final t = e.trim().replaceFirst(RegExp(r'^W/'), '').replaceAll('"', '').trim();
  return t.isEmpty ? null : t;
}

class DavEntry {
  final String name; // nazwa pliku (bez katalogu)
  final String? etag;
  final bool isDir;
  DavEntry(this.name, this.etag, this.isDir);
}

/// Prosty klient WebDAV (Synology WebDAV Server, Nextcloud, Koofr, …).
class WebDav {
  final Uri base; // zawsze kończy się „/”
  final String user;
  final String password;
  final bool allowSelfSigned;
  late final http.Client _client;

  WebDav(String url, this.user, this.password, {this.allowSelfSigned = false}) : base = normalizeBase(url) {
    final hc = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    if (allowSelfSigned) hc.badCertificateCallback = (_, __, ___) => true;
    _client = IOClient(hc);
  }

  static Uri normalizeBase(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    if (!u.endsWith('/')) u = '$u/';
    return Uri.parse(u);
  }

  void close() => _client.close();

  Map<String, String> get _auth => {
        if (user.isNotEmpty) 'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$password'))}',
      };

  /// Ścieżka względna („groby/abc.json”) → pełny adres z poprawnie zakodowanymi segmentami.
  Uri uri(String rel) {
    final segs = rel.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return base.resolve(rel.endsWith('/') ? '$segs/' : segs);
  }

  Future<http.Response> _send(String method, String rel, {Map<String, String>? headers, List<int>? body}) async {
    final req = http.Request(method, uri(rel));
    req.headers.addAll(_auth);
    if (headers != null) req.headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    try {
      final res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 60)));
      if (res.statusCode == 401) throw DavException('Serwer odrzucił login lub hasło (401)', 401);
      if (res.statusCode == 403) throw DavException('Brak uprawnień do folderu na serwerze (403)', 403);
      return res;
    } on SocketException catch (e) {
      throw DavException('Brak połączenia z serwerem (${e.osError?.message ?? e.message})');
    } on HandshakeException {
      throw DavException('Błąd certyfikatu HTTPS. Jeśli NAS ma certyfikat z własnym podpisem, zaznacz tę opcję w ustawieniach synchronizacji.');
    } on HttpException catch (e) {
      throw DavException('Błąd połączenia: ${e.message}');
    }
  }

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:resourcetype/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>';

  /// Zawartość katalogu (bez samego katalogu). Zwraca null, gdy katalog nie istnieje.
  Future<List<DavEntry>?> list(String dir) async {
    final res = await _send('PROPFIND', dir.endsWith('/') ? dir : '$dir/',
        headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'}, body: utf8.encode(_propfindBody));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 207) throw DavException('Serwer nie odpowiada jak WebDAV (PROPFIND ${res.statusCode}). Sprawdź adres.', res.statusCode);
    return parseMultistatus(utf8.decode(res.bodyBytes, allowMalformed: true), uri(dir.endsWith('/') ? dir : '$dir/').path);
  }

  static List<DavEntry> parseMultistatus(String xmlText, String dirPath) {
    final doc = XmlDocument.parse(xmlText);
    final out = <DavEntry>[];
    String norm(String p) => Uri.decodeComponent(p).replaceAll(RegExp(r'/+$'), '');
    final self = norm(dirPath);
    for (final r in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
      final hrefEl = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'href').firstOrNull;
      if (hrefEl == null) continue;
      var href = hrefEl.innerText.trim();
      if (href.startsWith('http')) href = Uri.parse(href).path;
      final path = norm(href);
      if (path == self || path.isEmpty) continue;
      final isDir = r.descendants.whereType<XmlElement>().any((e) => e.name.local == 'collection');
      final etagEl = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'getetag').firstOrNull;
      final lm = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'getlastmodified').firstOrNull;
      final len = r.descendants.whereType<XmlElement>().where((e) => e.name.local == 'getcontentlength').firstOrNull;
      // bez ETag: zastępczo data modyfikacji + rozmiar
      var etag = etagEl?.innerText.trim();
      if (etag == null || etag.isEmpty) {
        final alt = '${lm?.innerText.trim() ?? ''}|${len?.innerText.trim() ?? ''}';
        etag = alt == '|' ? null : alt;
      }
      out.add(DavEntry(path.split('/').last, etag?.contains('|') == true ? etag : normEtag(etag), isDir));
    }
    return out;
  }

  Future<void> mkcol(String dir) async {
    final res = await _send('MKCOL', dir.endsWith('/') ? dir : '$dir/');
    // 201 utworzono, 405 już istnieje
    if (res.statusCode != 201 && res.statusCode != 405 && res.statusCode != 200 && res.statusCode != 301) {
      throw DavException('Nie udało się utworzyć folderu „$dir” na serwerze (${res.statusCode})', res.statusCode);
    }
  }

  /// Pobiera plik; zwraca (treść, etag) albo null, gdy go nie ma.
  Future<(Uint8List, String?)?> get(String rel) async {
    final res = await _send('GET', rel);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw DavException('Błąd pobierania $rel (${res.statusCode})', res.statusCode);
    return (res.bodyBytes, normEtag(res.headers['etag']));
  }

  /// Wysyła plik. [ifMatch] – tylko gdy na serwerze jest dokładnie ta wersja; [ifNoneMatch] – tylko gdy pliku nie ma.
  Future<String?> put(String rel, List<int> bytes, {String? ifMatch, bool ifNoneMatch = false, String contentType = 'application/octet-stream'}) async {
    final h = {'Content-Type': contentType};
    // If-Match tylko dla prawdziwego ETag (nie dla zastępczego „data|rozmiar”)
    if (ifMatch != null && !ifMatch.contains('|')) h['If-Match'] = '"$ifMatch"';
    if (ifNoneMatch) h['If-None-Match'] = '*';
    final res = await _send('PUT', rel, headers: h, body: bytes);
    if (res.statusCode == 412) throw PreconditionFailed();
    if (res.statusCode < 200 || res.statusCode > 299) throw DavException('Błąd wysyłania $rel (${res.statusCode})', res.statusCode);
    return normEtag(res.headers['etag']);
  }

  Future<void> delete(String rel) async {
    final res = await _send('DELETE', rel);
    if (res.statusCode != 204 && res.statusCode != 200 && res.statusCode != 404) {
      throw DavException('Błąd usuwania $rel (${res.statusCode})', res.statusCode);
    }
  }
}
