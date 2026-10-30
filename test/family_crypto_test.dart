import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/sync/family_crypto.dart';

void main() {
  test('szyfrowanie plików rodziny', () async {
    final k = FamilyCrypto.newKey();
    final fc = FamilyCrypto.fromKey(k)!;
    final data = utf8.encode('{"uid":"g1","name":"Grób dziadka"}');
    final sealed = await fc.seal(data, 'groby/g1.json');
    expect(FamilyCrypto.isSealed(sealed), isTrue);
    expect(FamilyCrypto.isSealed(data), isFalse);
    expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('dziadka')));
    expect(await fc.open(sealed, 'groby/g1.json'), data);
    // inna nazwa pliku albo inny klucz — odrzucone
    expect(() => fc.open(sealed, 'groby/g2.json'), throwsFormatException);
    expect(() => FamilyCrypto.fromKey(FamilyCrypto.newKey())!.open(sealed, 'groby/g1.json'), throwsFormatException);
    expect(FamilyCrypto.fromKey(''), isNull);
    expect(FamilyCrypto.fromKey('zly'), isNull);
  });
}
