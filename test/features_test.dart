import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/data/models.dart';
import 'package:znicz/logic/expenses.dart';
import 'package:znicz/logic/family.dart';
import 'package:znicz/logic/geo.dart';
import 'package:znicz/logic/ics.dart';
import 'package:znicz/services/offline_tiles.dart';
import 'package:znicz/services/presence.dart';
import 'package:znicz/ui/shopping.dart';

void main() {
  group('Drzewo rodzinne', () {
    final dziadek = Person(graveId: 1, firstName: 'Jan', lastName: 'Kowalski', birth: const PartialDate(1920), death: const PartialDate(1990, 5, 3));
    final babcia = Person(graveId: 1, firstName: 'Anna', lastName: 'Kowalska', maidenName: 'Nowak', spouseUid: dziadek.uid);
    final tata = Person(graveId: 2, firstName: 'Piotr', lastName: 'Kowalski', fatherUid: dziadek.uid, motherUid: babcia.uid);
    final idx = FamilyIndex([dziadek, babcia, tata]);

    test('relacje', () {
      expect(idx.spouse(dziadek)?.uid, babcia.uid); // zapisane po drugiej stronie
      expect(idx.children(dziadek).single.uid, tata.uid);
      expect(idx.ancestors(tata).first.map((e) => e?.firstName).toList(), ['Jan', 'Anna']);
      expect(idx.wouldCycle(dziadek, tata.uid), isTrue); // syn nie może być ojcem ojca
      expect(idx.wouldCycle(tata, dziadek.uid), isFalse);
      expect(guessSex(babcia), 'F');
      expect(guessSex(dziadek), 'M');
    });

    test('GEDCOM', () {
      final g = buildGedcom([dziadek, babcia, tata], placeOf: (_) => 'Cmentarz parafialny, Celestynów', now: DateTime(2026, 11, 15));
      expect(g, startsWith('0 HEAD'));
      expect(g, contains('1 NAME Jan /Kowalski/'));
      expect(g, contains('1 NAME Anna /Nowak/'));
      expect(g, contains('2 DATE 3 MAY 1990'));
      expect(g, contains('2 PLAC Cmentarz parafialny, Celestynów'));
      expect(RegExp(r'0 @F\d+@ FAM').allMatches(g).length, 1); // jedna rodzina: dziadkowie + dziecko
      expect(g, contains('1 CHIL'));
      expect(g.trim(), endsWith('0 TRLR'));
    });

    test('Geneteka', () {
      final u = genetekaUri(lastName: 'Kowalski', firstName: 'Jan', kind: 'S', fromYear: 1988, toYear: 1992);
      expect(u.host, 'geneteka.genealodzy.pl');
      expect(u.queryParameters['search_lastname'], 'Kowalski');
      expect(u.queryParameters['w'], '07mz');
      expect(u.queryParameters['bdm'], 'S');
    });
  });

  test('rozliczenie wydatków po równo', () {
    final s = settle([
      Expense(graveId: 1, amount: 300, paidBy: 'Rafał'),
      Expense(graveId: 1, amount: 0.5, paidBy: 'Ola'),
      Expense(graveId: 1, amount: 99.5, paidBy: 'Ola'),
      Expense(graveId: 1, amount: 50, paidBy: null),
    ]);
    expect(s.paid, {'Rafał': 300.0, 'Ola': 100.0});
    expect(s.balance['Rafał'], 100);
    expect(s.balance['Ola'], -100);
    expect(s.transfers.single, ('Ola', 'Rafał', 100.0));
  });

  test('kalendarz ICS', () {
    final p = Person(graveId: 1, firstName: 'Jan', lastName: 'Kowalski', death: const PartialDate(1990, 5, 3), birth: const PartialDate(1920));
    final ics = buildIcs([p], whereOf: (_) => 'Celestynów, ul. Otwocka', now: DateTime.utc(2026, 11, 15, 10));
    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('DTSTART;VALUE=DATE:19900503'));
    expect(ics, contains('RRULE:FREQ=YEARLY'));
    expect(ics, contains('LOCATION:Celestynów\\, ul. Otwocka'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2); // śmierć + Wszystkich Świętych (urodziny niepełne)
    expect(ics.split('\r\n').every((l) => l.length <= 75), isTrue);
  });

  group('Droga do grobu', () {
    // prosta trasa na północ co ~11 m, potem na wschód
    final route = [for (var i = 0; i < 10; i++) (52.0 + i * 0.0001, 21.0), for (var i = 1; i < 6; i++) (52.0009, 21.0 + i * 0.00015)];
    test('cel wzdłuż trasy', () {
      final t = routeTarget(route, 52.0002, 21.00002);
      expect(t.$1, greaterThan(52.0002)); // cel przed nami na trasie
      expect(t.$4, isFalse);
      expect(t.$3, greaterThan(80));
      final end = routeTarget(route, 52.0009, 21.00075);
      expect(end.$4, isTrue);
    });
    test('przerzedzanie', () {
      final dense = [for (var i = 0; i < 100; i++) (52.0 + i * 0.000005, 21.0)];
      expect(thinRoute(dense).length, lessThan(25));
    });
  });

  test('kafelki mapy offline', () {
    final c = Cemetery(name: 'Test', outline: const [(52.06, 21.368), (52.06, 21.371), (52.063, 21.371), (52.063, 21.368)]);
    final t19 = tilesForBox(52.06, 21.368, 52.063, 21.371, 19);
    expect(t19.length, inInclusiveRange(20, 200));
    final all = OfflineTiles.tilesFor(c);
    expect(all.length, lessThan(1500));
    expect(all.any((t) => t.$1 == 13), isTrue);
  });

  test('obecność na cmentarzu', () {
    final a = Cemetery(name: 'A', outline: const [(52.0, 21.0), (52.0, 21.01), (52.01, 21.01), (52.01, 21.0)]);
    final b = Cemetery(name: 'B', lat: 52.1, lng: 21.1);
    expect(CemeteryPresence.cemeteryAt([a, b], 52.005, 21.005)?.name, 'A');
    expect(CemeteryPresence.cemeteryAt([a, b], 52.1005, 21.1)?.name, 'B');
    expect(CemeteryPresence.cemeteryAt([a, b], 52.05, 21.05), isNull);
  });

  test('zakupy wg osób', () {
    final g = [
      Grave(visitor: 'Rafał', candles: 3, flowers: 1),
      Grave(visitor: 'Rafał', candles: 2, flowers: 2),
      Grave(candles: 1, flowers: 0),
      Grave(visitor: 'Ola', allSaints: false),
    ];
    final by = shoppingByPerson(g);
    expect(by['Rafał']!.candles, 5);
    expect(by['Rafał']!.graves, 2);
    expect(by['Nieprzydzielone']!.candles, 1);
    expect(by.containsKey('Ola'), isFalse);
  });

  test('model: trasa i relacje przechodzą przez bazę', () {
    final g = Grave(route: const [(52.0, 21.0), (52.0001, 21.0)], candles: 4);
    final back = Grave.fromMap(g.toMap());
    expect(back.route.length, 2);
    expect(back.candles, 4);
    final p = Person(graveId: 1, motherUid: 'm', spouseUid: 's');
    expect(Person.fromMap(p.toMap()).motherUid, 'm');
    final ph = GravePhoto(graveId: 1, path: 'a.m4a', kind: 'audio', personUid: 'x');
    expect(GravePhoto.fromMap(ph.toMap()).isAudio, isTrue);
  });
}
