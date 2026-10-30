import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Szyfrowanie plików synchronizacji rodzinnej (AES-256-GCM, klucz wspólny dla rodziny).
///
/// Format pliku: `"ZNE1" | nonce(12) | szyfrogram | tag(16)`; AAD = "ZNE1" + ścieżka pliku na serwerze,
/// więc pliku nie da się podmienić pod inną nazwę. Klucz (32 bajty, base64url) jest w kodzie zaproszenia.
/// Pliki bez nagłówka to dane sprzed włączenia szyfrowania — są czytane i przy okazji szyfrowane.
class FamilyCrypto {
  static const _magic = [0x5A, 0x4E, 0x45, 0x31]; // ZNE1
  static final _aes = AesGcm.with256bits();

  final SecretKey _key;
  FamilyCrypto._(this._key);

  static FamilyCrypto? fromKey(String b64) {
    if (b64.isEmpty) return null;
    try {
      final b = base64Url.decode(base64Url.normalize(b64));
      return b.length == 32 ? FamilyCrypto._(SecretKey(b)) : null;
    } catch (_) {
      return null;
    }
  }

  static String newKey() {
    final r = Random.secure();
    return base64Url.encode(List.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static bool isSealed(List<int> data) =>
      data.length >= 4 && data[0] == _magic[0] && data[1] == _magic[1] && data[2] == _magic[2] && data[3] == _magic[3];

  Future<Uint8List> seal(List<int> data, String path) async {
    final box = await _aes.encrypt(data, secretKey: _key, nonce: _aes.newNonce(), aad: [..._magic, ...utf8.encode(path)]);
    return Uint8List.fromList([..._magic, ...box.concatenation()]);
  }

  Future<Uint8List> open(List<int> file, String path) async {
    if (!isSealed(file) || file.length < 4 + 12 + 16) throw const FormatException('Uszkodzony plik');
    try {
      final box = SecretBox.fromConcatenation(file.sublist(4), nonceLength: 12, macLength: 16);
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: _key, aad: [..._magic, ...utf8.encode(path)]));
    } on SecretBoxAuthenticationError {
      throw const FormatException('Klucz rodziny nie pasuje do danych na serwerze — wklej aktualny kod zaproszenia.');
    }
  }
}
