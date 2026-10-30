import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/services/catalog.dart';

void main() {
  test('wbudowany katalog cmentarzy okolicy', () {
    final items = CemeteryCatalog.parse(File('assets/cmentarze_okolica.json').readAsStringSync());
    expect(items.length, greaterThan(100));
    expect(CemeteryCatalog.radiusKm, 50);
    // najbliższy – cmentarz parafialny w Celestynowie
    final first = items.first;
    expect(first.town, 'Celestynów');
    expect(first.kind, 'parafialny');
    expect(first.outline.length, greaterThanOrEqualTo(3));
    // każdy ma położenie
    expect(items.every((c) => c.lat > 51 && c.lat < 53 && c.lng > 20 && c.lng < 22.5), isTrue);
    final draft = cemeteryDraftFrom(first);
    expect(draft.osmId, first.osmId);
    expect(draft.town, 'Celestynów');
  });
}
