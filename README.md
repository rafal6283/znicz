# Znicz

Prywatny notatnik grobów bliskich na Androida i iPhone'a (Flutter) – w stylu Cmentarz GPS / BillionGraves, z synchronizacją dla całej rodziny.

## Co potrafi

- **Groby i cmentarze** – dokładne położenie (uśrednianie odczytów GPS przy grobie, wskazanie na mapie albo pozycja ze zdjęcia), kwatera / rząd / numer, opis drogi od bramy, rodzaj grobu, termin opłaty za miejsce.
- **Osoby pochowane** – imiona, nazwisko i nazwisko rodowe, daty niepełne (sam rok też), relacja („babcia”), napis z nagrobka, wspomnienia.
- **Zdjęcie nagrobka → dane** – odczyt napisu (ML Kit, bez internetu) i rozpoznanie imion, nazwisk i dat, także „z d.”, „żył lat 78” i nazwisk rodzin („KOWALSCY”).
- **Dyktowanie** – mikrofon przy każdym polu oraz „Podyktuj wszystko”: *„Jan Kowalski, dziadek, urodzony 12 marca 1932, zmarł 5 listopada 2010, kwatera 12, rząd 3, numer 45, oraz Anna Kowalska z domu Nowak…”*.
- **Prowadzenie do grobu** – strzałka kompasu, odległość i mapa (OpenStreetMap albo zdjęcia satelitarne), „Jesteś przy grobie” ze zdjęciem i opisem drogi; dojazd samochodem przez Google Maps.
- **Pamięć** – najbliższe rocznice śmierci i urodzin z przypomnieniami, przypomnienie przed Wszystkimi Świętymi i o końcu opłaty za grób.
- **Wszystkich Świętych** – lista grobów do odwiedzenia z odhaczaniem (widać, kto z rodziny już był) i trasa ułożona od Twojej pozycji.
- **Dziennik wizyt** – znicz, kwiaty, sprzątanie, notatka, zdjęcie.
- **Synchronizacja rodzinna** – przez WebDAV: Synology NAS (pakiet „WebDAV Server”), Nextcloud albo darmowa chmura (np. Koofr). Zmiany łączą się na poziomie pojedynczych rekordów, usunięcia też docierają do wszystkich. Konfigurację przekazuje się rodzinie jednym kodem zaproszenia.
- **Udostępnianie** – opis z linkiem do mapy albo plik `.znicz` z całym grobem i zdjęciami; kopia zapasowa `.zip`; przycisk „Szukaj w Grobonet”.

## Synchronizacja – układ plików na serwerze

```
<folder>/cmentarze/<uid>.json
<folder>/groby/<uid>.json     – grób + osoby + opisy zdjęć + wizyty (z rekordami usuniętymi)
<folder>/zdjecia/<uid>.jpg
```

Każdy rekord ma stały `uid` i znacznik `updated`; przy scalaniu wygrywa nowsza wersja. Wysyłanie używa `If-Match`, więc równoczesne zmiany dwóch osób nie nadpisują się nawzajem.

## Instalacja

Każdy push na `main` buduje aplikację w GitHub Actions i publikuje ją w zakładce **Releases**:

- **Android** – `znicz.apk`: pobierz na telefonie i zainstaluj. Kolejne wersje instalują się jako aktualizacja (stały klucz `android/app/znicz.jks`).
- **iPhone** – `znicz.ipa` (budowany, gdy opis commita zawiera `[ios]` albo ręcznie z Actions): zainstaluj przez Sideloadly lub AltStore swoim Apple ID.

`[smoke]` w opisie commita uruchamia dodatkowo test na emulatorze Androida.

## Struktura

- `lib/data/` – modele, baza SQLite, zdjęcia, kopia zapasowa, eksport grobu
- `lib/logic/` – daty po polsku, odczyt napisów nagrobnych, dyktowanie, geometria (kompas, uśrednianie GPS, trasa), rocznice
- `lib/services/` – lokalizacja, OCR + EXIF, mowa, powiadomienia
- `lib/sync/` – klient WebDAV i synchronizacja
- `lib/ui/` – ekrany
- `test/logic_test.dart` – testy logiki (uruchamiane w CI)
- `.github/patch_platforms.py` – uprawnienia i ustawienia Androida/iOS dopisywane po `flutter create`
