import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/data/models.dart';
import 'package:znicz/logic/anniversaries.dart';
import 'package:znicz/logic/dates_pl.dart';
import 'package:znicz/logic/dictation_parser.dart';
import 'package:znicz/logic/geo.dart';
import 'package:znicz/logic/inscription_parser.dart';
import 'package:znicz/sync/bundle.dart';
import 'package:znicz/sync/sync_service.dart';
import 'package:znicz/sync/webdav.dart';

void main() {
  group('PartialDate', () {
    test('parsuje formy polskie i ISO', () {
      expect(PartialDate.parse('12.03.1932'), const PartialDate(1932, 3, 12));
      expect(PartialDate.parse('03.1932'), const PartialDate(1932, 3));
      expect(PartialDate.parse('1932'), const PartialDate(1932));
      expect(PartialDate.parse('1932-03-12'), const PartialDate(1932, 3, 12));
      expect(PartialDate.parse('12 III 1932'), const PartialDate(1932, 3, 12));
      expect(PartialDate.parse('31.02.1932'), isNull);
    });
    test('zapis i format', () {
      expect(const PartialDate(1932, 3, 12).toStorage(), '1932-03-12');
      expect(const PartialDate(1932, 3).format(), '03.1932');
      expect(PartialDate.parse(const PartialDate(1932, 3).toStorage()), const PartialDate(1932, 3));
    });
    test('wiek', () {
      expect(ageAt(const PartialDate(1932, 3, 12), const PartialDate(2010, 3, 11)), 77);
      expect(ageAt(const PartialDate(1932, 3, 12), const PartialDate(2010, 3, 12)), 78);
      expect(ageAt(const PartialDate(1932), const PartialDate(2010)), 78);
    });
  });

  group('Daty w tekście', () {
    test('różne zapisy', () {
      final h = findDates('ur. 12 marca 1932 zm. 5.11.2010');
      expect(h.map((e) => e.date).toList(), [const PartialDate(1932, 3, 12), const PartialDate(2010, 11, 5)]);
      expect(findDates('1920 - 1990').map((e) => e.date).toList(), [const PartialDate(1920), const PartialDate(1990)]);
      expect(findDates('XII 1944').first.date, const PartialDate(1944, 12));
      expect(findDates('3 maja 1930').first.date, const PartialDate(1930, 5, 3));
      expect(findDates('października 1999').first.date, const PartialDate(1999, 10));
      expect(findDates('zyl lat 78'), isEmpty);
    });
    test('liczebniki z dyktowania', () {
      expect(ordinalDaysToDigits('dwudziestego pierwszego marca 1950'), '21 marca 1950');
      expect(parseLooseDate('dwunastego marca 1932'), const PartialDate(1932, 3, 12));
      expect(parseLooseDate('1932'), const PartialDate(1932));
    });
  });

  group('Napis z nagrobka', () {
    test('jedna osoba, daty pod imieniem', () {
      final r = parseInscription('Ś.P.\nJAN KOWALSKI\nur. 12.03.1932\nzm. 05.11.2010\nSPOCZYWAJ W POKOJU');
      expect(r.length, 1);
      expect(r.first.firstName, 'Jan');
      expect(r.first.lastName, 'Kowalski');
      expect(r.first.birth, const PartialDate(1932, 3, 12));
      expect(r.first.death, const PartialDate(2010, 11, 5));
    });
    test('dwie osoby z latami w jednej linii', () {
      final r = parseInscription('ŚP\nANNA NOWAK 1920 - 1990\nJÓZEF NOWAK 1918 - 1985');
      expect(r.length, 2);
      expect(r[0].toString(), 'Anna|Nowak||1920|1990');
      expect(r[1].toString(), 'Józef|Nowak||1918|1985');
    });
    test('imię i nazwisko w osobnych liniach, nazwisko rodowe', () {
      final r = parseInscription('ŚP\nMARIA\nWIŚNIEWSKA\nz d. KOWALCZYK\n* 3.05.1930\n† 12.01.2001');
      expect(r.length, 1);
      expect(r.first.firstName, 'Maria');
      expect(r.first.lastName, 'Wiśniewska');
      expect(r.first.maidenName, 'Kowalczyk');
      expect(r.first.birth, const PartialDate(1930, 5, 3));
      expect(r.first.death, const PartialDate(2001, 1, 12));
    });
    test('nazwisko rodziny w liczbie mnogiej', () {
      final r = parseInscription('GRÓB RODZINY\nANNA 1920-1990\nJAN 1918-1985\nKOWALSCY');
      expect(r.length, 2);
      expect(r[0].lastName, 'Kowalska');
      expect(r[1].lastName, 'Kowalski');
    });
    test('żył lat', () {
      final r = parseInscription('ŚP\nSTANISŁAW ZIELIŃSKI\nzm. 1999\nżył lat 81');
      expect(r.first.death, const PartialDate(1999));
      expect(r.first.birth, const PartialDate(1918));
    });
  });

  group('Dyktowanie', () {
    test('pełny opis grobu', () {
      final r = parseDictation('Jan Kowalski dziadek urodzony 12 marca 1932 zmarł 5 listopada 2010 kwatera 12 rząd 3 numer 45');
      expect(r.people.length, 1);
      final p = r.people.first;
      expect(p.firstName, 'Jan');
      expect(p.lastName, 'Kowalski');
      expect(p.relation, 'dziadek');
      expect(p.birth, const PartialDate(1932, 3, 12));
      expect(p.death, const PartialDate(2010, 11, 5));
      expect(r.section, '12');
      expect(r.row, '3');
      expect(r.number, '45');
    });
    test('dwie osoby, nazwisko rodowe, cmentarz', () {
      final r = parseDictation('Jan Kowalski zmarł 2010 oraz Anna Kowalska z domu Nowak zmarła 2015 cmentarz parafialny w Celestynowie');
      expect(r.people.length, 2);
      expect(r.people[1].maidenName, 'Nowak');
      expect(r.people[1].death, const PartialDate(2015));
      expect(r.cemetery, 'Cmentarz parafialny w Celestynowie');
    });
    test('kwatera z literą i liczebnik porządkowy', () {
      final r = parseDictation('babcia Zofia Nowak zmarła dwudziestego pierwszego stycznia 1999 kwatera 12 b');
      expect(r.people.first.relation, 'babcia');
      expect(r.people.first.firstName, 'Zofia');
      expect(r.people.first.death, const PartialDate(1999, 1, 21));
      expect(r.section, '12b');
    });
  });

  group('Geo', () {
    test('odległość i kierunek', () {
      // ok. 111 m na 0,001° szerokości
      final d = distanceM(52.0, 21.0, 52.001, 21.0);
      expect(d, closeTo(111.2, 0.5));
      expect(bearingDeg(52.0, 21.0, 52.001, 21.0), closeTo(0, 0.5));
      expect(bearingDeg(52.0, 21.0, 52.0, 21.001), closeTo(90, 0.5));
      expect(angleDiff(10, 350), closeTo(20, 1e-9));
      expect(angleDiff(350, 10), closeTo(-20, 1e-9));
    });
    test('uśrednianie odrzuca słabe odczyty', () {
      final avg = averageSamples([GeoSample(52.0, 21.0, 4), GeoSample(52.0, 21.0, 5), GeoSample(52.01, 21.01, 60)])!;
      expect(avg.lat, closeTo(52.0, 1e-6));
      expect(avg.accuracy, lessThan(5));
    });
    test('trasa', () {
      final order = visitOrder([(0.0, 0.0), (0.0, 0.003), (0.0, 0.001), (0.0, 0.002)], start: (0.0, -0.001));
      expect(order, [0, 2, 3, 1]);
    });
    test('format odległości', () {
      expect(formatDistance(7.4), '7 m');
      expect(formatDistance(1520), '1,5 km');
    });
  });

  group('Rocznice', () {
    test('najbliższe wystąpienie', () {
      final today = DateTime(2026, 10, 26);
      expect(nextOccurrence(11, 1, today), DateTime(2026, 11, 1));
      expect(nextOccurrence(1, 5, today), DateTime(2027, 1, 5));
      expect(nextOccurrence(2, 29, today), DateTime(2027, 2, 28));
      final p = Person(graveId: 1, firstName: 'Jan', death: const PartialDate(2010, 11, 5));
      final ev = upcomingEvents([p], [], today);
      expect(ev.single.years, 16);
      expect(ev.single.date, DateTime(2026, 11, 5));
    });
  });

  group('Synchronizacja', () {
    test('odcisk zmienia się przy zmianie rekordu', () {
      final a = fingerprintOf([
        {'uid': 'a', 'updated': 1, 'deleted': 0},
        {'uid': 'b', 'updated': 2, 'deleted': 0},
      ]);
      final b = fingerprintOf([
        {'uid': 'b', 'updated': 2, 'deleted': 0},
        {'uid': 'a', 'updated': 1, 'deleted': 0},
      ]);
      final c = fingerprintOf([
        {'uid': 'a', 'updated': 1, 'deleted': 1},
        {'uid': 'b', 'updated': 2, 'deleted': 0},
      ]);
      expect(a, b);
      expect(a == c, isFalse);
    });
    test('nowsza wersja wygrywa, przy remisie usunięcie', () {
      expect(remoteWins({'updated': 5}, {'updated': 4}), isTrue);
      expect(remoteWins({'updated': 4}, {'updated': 5}), isFalse);
      expect(remoteWins({'updated': 5, 'deleted': 1}, {'updated': 5, 'deleted': 0}), isTrue);
      expect(remoteWins({'updated': 1}, null), isTrue);
    });
    test('pakiet grobu w obie strony', () {
      final b = GraveBundle({'uid': 'g1', 'updated': 3, 'deleted': 0, 'cemetery_uid': 'c1'}, [
        {'uid': 'p1', 'updated': 2, 'deleted': 0, 'first_name': 'Jan'}
      ], [], []);
      final back = GraveBundle.decode(b.encode());
      expect(back.uid, 'g1');
      expect(back.people.first['first_name'], 'Jan');
      expect(back.fingerprint, b.fingerprint);
    });
    test('kod zaproszenia', () {
      final c = SyncConfig(url: 'https://nas.example.pl:5006/znicz', user: 'rodzina', password: 'tajne:hasło', allowSelfSigned: true);
      final code = c.inviteCode();
      expect(code.startsWith('ZNICZ1-'), isTrue);
      final back = SyncConfig.fromInvite('Wklej to: $code\n')!;
      expect(back.url, c.url);
      expect(back.password, 'tajne:hasło');
      expect(back.allowSelfSigned, isTrue);
      expect(SyncConfig.fromInvite('coś innego'), isNull);
    });
    test('odpowiedź PROPFIND (Synology)', () {
      const xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:ns0="DAV:">
<D:response><D:href>/znicz/groby/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
<D:response><D:href>/znicz/groby/abc.json</D:href><D:propstat><D:prop><D:getetag>"5f-63a1"</D:getetag><D:resourcetype/></D:prop></D:propstat></D:response>
<D:response><D:href>/znicz/groby/x%20y.json</D:href><D:propstat><D:prop><lp1:getetag xmlns:lp1="DAV:">W/"77"</lp1:getetag><D:resourcetype/></D:prop></D:propstat></D:response>
</D:multistatus>''';
      final l = WebDav.parseMultistatus(xml, '/znicz/groby/');
      expect(l.length, 2);
      expect(l[0].name, 'abc.json');
      expect(l[0].etag, '5f-63a1');
      expect(l[0].isDir, isFalse);
      expect(l[1].name, 'x y.json');
      expect(l[1].etag, '77');
    });
    test('adres serwera', () {
      expect(WebDav.normalizeBase('nas.local:5006/znicz').toString(), 'https://nas.local:5006/znicz/');
      expect(WebDav('https://a.pl/dav', 'u', 'p').uri('groby/a b.json').toString(), 'https://a.pl/dav/groby/a%20b.json');
      expect(WebDav('https://app.koofr.net/dav/Koofr/znicz', 'u', 'p').uri('').toString(), 'https://app.koofr.net/dav/Koofr/znicz/');
      expect(WebDav.normalizeBase('https://app.koofr.net/dav/Koofr/znicz').resolve('..').toString(), 'https://app.koofr.net/dav/Koofr/');
    });
  });
}
