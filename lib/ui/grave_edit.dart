import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../logic/dates_pl.dart';
import '../logic/dictation_parser.dart';
import '../logic/geo.dart';
import '../logic/inscription_parser.dart';
import '../services/location.dart';
import '../services/notifications.dart';
import '../services/ocr.dart';
import 'cemetery.dart';
import 'common.dart';
import 'dictation.dart';
import 'guess_review.dart';
import 'map_screen.dart';
import 'nearby_cemeteries.dart';
import 'person_edit.dart';

enum _LocSource { none, gps, map, photo, saved }

/// Dodawanie i edycja grobu. Dla nowego grobu od razu zbiera pozycję GPS (stań przy grobie).
class GraveEditScreen extends StatefulWidget {
  final int? graveId;
  final double? lat; // nowy grób w miejscu wskazanym na mapie
  final double? lng;
  final int? cemeteryId;
  const GraveEditScreen({super.key, this.graveId, this.lat, this.lng, this.cemeteryId});
  @override
  State<GraveEditScreen> createState() => _GraveEditScreenState();
}

class _GraveEditScreenState extends State<GraveEditScreen> {
  bool get isNew => widget.graveId == null;
  bool _loading = true;
  bool _saving = false;
  Grave _g = Grave();
  List<Person> _people = [];
  final List<int> _removedPeople = [];
  List<Cemetery> _cems = [];
  int? _cemId;
  String? _newCemName;
  final List<String> _pendingPhotos = []; // ścieżki zdjęć do dodania po zapisie

  // szybki formularz pierwszej osoby
  final _qFirst = TextEditingController();
  final _qLast = TextEditingController();
  final _qBirth = TextEditingController();
  final _qDeath = TextEditingController();
  String? _qInscription;

  final _section = TextEditingController();
  final _row = TextEditingController();
  final _number = TextEditingController();
  final _directions = TextEditingController();
  final _notes = TextEditingController();
  final _fee = TextEditingController();
  String? _type;

  // położenie
  _LocSource _src = _LocSource.none;
  double? _lat, _lng, _acc;
  LocationSampler? _sampler;
  int _samples = 0;
  double? _lastAcc;
  String? _locError;
  bool _cemAuto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = AppDb.I;
    _cems = await db.cemeteries();
    if (!isNew) {
      final g = await db.grave(widget.graveId!);
      if (g != null) {
        _g = g;
        _people = await db.people(g.id!);
        _cemId = g.cemeteryId;
        _section.text = g.section ?? '';
        _row.text = g.row ?? '';
        _number.text = g.number ?? '';
        _directions.text = g.directions ?? '';
        _notes.text = g.notes ?? '';
        _fee.text = g.feePaidUntil?.format() ?? '';
        _type = g.type;
        if (g.hasLocation) {
          _lat = g.lat;
          _lng = g.lng;
          _acc = g.accuracy;
          _src = _LocSource.saved;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
    if (isNew && widget.lat != null) {
      setState(() {
        _lat = widget.lat;
        _lng = widget.lng;
        _src = _LocSource.map;
        _cemId = widget.cemeteryId;
      });
      if (_cemId == null) _autoCemetery();
    } else if (isNew) {
      _startGps();
    }
  }

  @override
  void dispose() {
    _sampler?.stop();
    for (final c in [_qFirst, _qLast, _qBirth, _qDeath, _section, _row, _number, _directions, _notes, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- położenie ----------

  Future<void> _startGps() async {
    final err = await LocationService.ensurePermission();
    if (!mounted) return;
    if (err != null) {
      setState(() => _locError = err);
      return;
    }
    _sampler?.stop();
    setState(() {
      _locError = null;
      _samples = 0;
      _src = _LocSource.gps;
    });
    _sampler = LocationSampler((avg, count, last) {
      if (!mounted || avg == null || _src != _LocSource.gps) return;
      setState(() {
        _lat = avg.lat;
        _lng = avg.lng;
        _acc = avg.accuracy;
        _samples = count;
        _lastAcc = last;
      });
      _autoCemetery();
    })
      ..start();
  }

  void _stopGps() {
    _sampler?.stop();
    _sampler = null;
  }

  /// Nowy grób: wybierz cmentarz w promieniu 1,5 km (pierwszy dobry odczyt).
  Future<void> _autoCemetery() async {
    if (_cemAuto || !isNew || _cemId != null || _newCemName != null || _lat == null || (_src != _LocSource.map && (_acc ?? 999) > 60)) return;
    _cemAuto = true;
    final views = await AppDb.I.graveViews();
    double? best;
    int? bestId;
    // najpierw obrys cmentarza (z OpenStreetMap) – stoisz w jego granicach
    for (final c in _cems) {
      if (pointInPolygon(_lat!, _lng!, c.outline)) {
        if (mounted && _cemId == null) setState(() => _cemId = c.id);
        return;
      }
    }
    for (final c in _cems) {
      final pts = <(double, double)>[
        if (c.hasLocation) (c.lat!, c.lng!),
        for (final v in views)
          if (v.grave.cemeteryId == c.id && v.grave.hasLocation) (v.grave.lat!, v.grave.lng!),
      ];
      for (final p in pts) {
        final d = distanceM(_lat!, _lng!, p.$1, p.$2);
        if (d < 1500 && (best == null || d < best)) {
          best = d;
          bestId = c.id;
        }
      }
    }
    if (bestId != null && mounted && _cemId == null) setState(() => _cemId = bestId);
  }

  Future<void> _pickOnMap() async {
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _lat == null ? null : LatLng(_lat!, _lng!), title: 'Gdzie jest grób?')),
    );
    if (r == null) return;
    _stopGps();
    setState(() {
      _lat = r.latitude;
      _lng = r.longitude;
      _acc = null;
      _src = _LocSource.map;
    });
  }

  // ---------- zdjęcie nagrobka + odczyt napisu ----------

  Future<void> _photo(ImageSource source, {bool readText = true}) async {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 2600, imageQuality: 88, requestFullMetadata: true);
    if (x == null || !mounted) return;
    // zdjęcie z galerii z GPS – może posłużyć za położenie grobu
    if (source == ImageSource.gallery && (_src == _LocSource.none || (_src == _LocSource.gps && _samples == 0))) {
      final meta = await readPhotoMeta(x.path);
      if (meta.lat != null && mounted) {
        final use = await confirm(context, 'Położenie ze zdjęcia', 'Zdjęcie ma zapisaną pozycję GPS${meta.taken != null ? ' (zrobione ${fmtDate(meta.taken!)})' : ''}. Użyć jej jako miejsca grobu?',
            ok: 'Użyj', destructive: false);
        if (use) {
          _stopGps();
          setState(() {
            _lat = meta.lat;
            _lng = meta.lng;
            _acc = 15;
            _src = _LocSource.photo;
          });
        }
      }
    }
    setState(() => _pendingPhotos.add(x.path));
    if (!readText || !mounted) return;

    String text = '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Expanded(child: Text('Odczytuję napis z nagrobka…'))])),
    );
    try {
      text = await Ocr.readImage(x.path);
    } catch (e) {
      text = '';
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    final guesses = parseInscription(text);
    if (text.trim().isEmpty) {
      snack(context, 'Nie udało się odczytać napisu – zdjęcie zostało dodane, dane wpisz lub podyktuj');
      return;
    }
    final chosen = await reviewGuesses(context, title: 'Odczytano z nagrobka', guesses: guesses, rawText: text);
    if (chosen == null || !mounted) return;
    _applyGuesses(chosen, inscription: text);
  }

  void _applyGuesses(List<PersonGuess> list, {String? inscription}) {
    setState(() {
      for (var i = 0; i < list.length; i++) {
        final g = list[i];
        final simple = g.maidenName == null && g.relation == null && g.burial == null && g.note == null;
        // pierwsza osoba trafia do pustego szybkiego formularza (o ile nie ma szczegółów)
        if (i == 0 && _people.isEmpty && !_quickHasData && simple) {
          _qFirst.text = g.firstName;
          _qLast.text = g.lastName;
          _qBirth.text = g.birth?.format() ?? '';
          _qDeath.text = g.death?.format() ?? '';
          _qInscription = inscription;
          continue;
        }
        if (_quickHasData) {
          _people.add(_personFromQuick());
          _clearQuick();
        }
        _people.add(Person(
          graveId: _g.id ?? 0,
          firstName: g.firstName,
          lastName: g.lastName,
          maidenName: g.maidenName,
          birth: g.birth,
          death: g.death,
          burial: g.burial,
          relation: g.relation,
          notes: g.note,
          inscription: i == 0 ? inscription : null,
          sort: _people.length,
        ));
      }
    });
  }

  bool get _quickHasData => _qFirst.text.trim().isNotEmpty || _qLast.text.trim().isNotEmpty;

  Person _personFromQuick() => Person(
        graveId: _g.id ?? 0,
        firstName: _qFirst.text.trim(),
        lastName: _qLast.text.trim(),
        birth: parseLooseDate(_qBirth.text),
        death: parseLooseDate(_qDeath.text),
        inscription: _qInscription,
        sort: _people.length,
      );

  void _clearQuick() {
    _qFirst.clear();
    _qLast.clear();
    _qBirth.clear();
    _qDeath.clear();
    _qInscription = null;
  }

  // ---------- dyktowanie całego grobu ----------

  Future<void> _dictateAll() async {
    final t = await dictate(
      context,
      title: 'Podyktuj dane grobu',
      hint: 'np. „Jan Kowalski, dziadek, urodzony 12 marca 1932, zmarł 5 listopada 2010, kwatera 12, rząd 3, numer 45, '
          'oraz Anna Kowalska z domu Nowak, zmarła 2015”',
    );
    if (t == null || t.isEmpty || !mounted) return;
    final r = parseDictation(t);
    if (r.isEmpty) {
      snack(context, 'Nie rozpoznano danych – spróbuj mówić wolniej, ze słowami „urodzony”, „zmarł”, „kwatera”');
      return;
    }
    Cemetery? match;
    if (r.cemetery != null) {
      final f = fold(r.cemetery!.replaceFirst(RegExp(r'^Cmentarz\s*', caseSensitive: false), ''));
      for (final c in _cems) {
        final cf = fold('${c.name} ${c.town ?? ''}');
        if (f.split(' ').where((w) => w.length > 3).every((w) => cf.contains(w.substring(0, w.length - 2)))) {
          match = c;
          break;
        }
      }
    }
    final extra = <String>[
      if (r.section != null) 'Kwatera ${r.section}',
      if (r.row != null) 'Rząd ${r.row}',
      if (r.number != null) 'Numer ${r.number}',
      if (r.cemetery != null) match != null ? 'Cmentarz: ${match.label}' : '${r.cemetery} (nowy)',
      if (r.directions != null) 'Dojście: ${r.directions}',
    ];
    final chosen = await reviewGuesses(context, title: 'Rozpoznano z dyktowania', guesses: r.people, rawText: t, extra: extra);
    if (chosen == null || !mounted) return;
    setState(() {
      if (r.section != null) _section.text = r.section!;
      if (r.row != null) _row.text = r.row!;
      if (r.number != null) _number.text = r.number!;
      if (r.directions != null) _directions.text = r.directions!;
      if (match != null) {
        _cemId = match.id;
        _newCemName = null;
      } else if (r.cemetery != null) {
        _cemId = null;
        _newCemName = r.cemetery;
      }
    });
    _applyGuesses(chosen);
  }

  // ---------- osoby ----------

  Future<void> _editPerson(Person? p) async {
    final isNewP = p == null;
    if (isNewP && _quickHasData) {
      _people.add(_personFromQuick());
      _clearQuick();
    }
    final person = p ?? Person(graveId: _g.id ?? 0, lastName: _people.isNotEmpty ? _people.first.lastName : '', sort: _people.length);
    final r = await Navigator.push<PersonEditResult>(context, MaterialPageRoute(builder: (_) => PersonEditScreen(person: person, isNew: isNewP)));
    if (r == null) {
      setState(() {});
      return;
    }
    setState(() {
      if (r.person == null) {
        _people.remove(p);
        if (p?.id != null) _removedPeople.add(p!.id!);
      } else if (isNewP) {
        _people.add(r.person!);
      }
    });
  }

  // ---------- cmentarz ----------

  Future<void> _newCemetery() async {
    final c = await Navigator.push<Cemetery>(
      context,
      MaterialPageRoute(builder: (_) => CemeteryEditScreen(lat: _lat, lng: _lng, name: _newCemName)),
    );
    if (c == null) return;
    _cems = await AppDb.I.cemeteries();
    setState(() {
      _cemId = c.id;
      _newCemName = null;
    });
  }

  Future<void> _nearby() async {
    final before = _cems.map((c) => c.id).toSet();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NearbyCemeteriesScreen(lat: _lat, lng: _lng)));
    _cems = await AppDb.I.cemeteries();
    if (!mounted) return;
    final added = _cems.where((c) => !before.contains(c.id)).toList();
    setState(() {
      // wybierz dodany cmentarz, w którego granicach jest grób (albo jedyny dodany)
      final inside = _lat == null ? <Cemetery>[] : added.where((c) => pointInPolygon(_lat!, _lng!, c.outline)).toList();
      if (inside.isNotEmpty) {
        _cemId = inside.first.id;
      } else if (added.length == 1) {
        _cemId = added.first.id;
      }
      if (_cemId != null) _newCemName = null;
    });
  }

  // ---------- zapis ----------

  Future<void> _save() async {
    if (_saving) return;
    final hasSomething = _people.isNotEmpty || _quickHasData || _lat != null || _pendingPhotos.isNotEmpty || _section.text.isNotEmpty || _number.text.isNotEmpty;
    if (!hasSomething) {
      snack(context, 'Dodaj osobę, położenie albo zdjęcie grobu');
      return;
    }
    setState(() => _saving = true);
    _stopGps();
    final db = AppDb.I;
    try {
      if (_cemId == null && _newCemName != null) {
        _cemId = await db.saveCemetery(Cemetery(name: _newCemName!, lat: _lat, lng: _lng));
      }
      if (_cemId != null && _lat != null) {
        final c = await db.cemetery(_cemId!);
        if (c != null && !c.hasLocation) {
          c
            ..lat = _lat
            ..lng = _lng;
          await db.saveCemetery(c);
        }
      }
      String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      _g
        ..cemeteryId = _cemId
        ..lat = _lat
        ..lng = _lng
        ..accuracy = _src == _LocSource.map ? null : _acc
        ..section = t(_section)
        ..row = t(_row)
        ..number = t(_number)
        ..directions = t(_directions)
        ..notes = t(_notes)
        ..type = _type
        ..feePaidUntil = parseLooseDate(_fee.text);
      final gid = await db.saveGrave(_g, notify: false);
      if (_quickHasData) {
        _people.add(_personFromQuick());
        _clearQuick();
      }
      for (var i = 0; i < _people.length; i++) {
        final p = _people[i]
          ..graveId = gid
          ..sort = i;
        await db.savePerson(p, notify: false);
      }
      for (final id in _removedPeople) {
        await db.deletePerson(id);
      }
      var first = (await db.photos(gid)).isEmpty;
      for (final path in _pendingPhotos) {
        await Storage.addPhoto(gid, path, cover: first);
        first = false;
        try {
          if (path.contains('cache')) await File(path).delete();
        } catch (_) {}
      }
      db.changed();
      Notifications.reschedule();
      if (mounted) Navigator.pop(context, gid);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        snack(context, 'Nie udało się zapisać: $e');
      }
    }
  }

  // ---------- widok ----------

  Widget _locationCard() {
    final cs = Theme.of(context).colorScheme;
    String title;
    String sub;
    IconData icon = Icons.place_outlined;
    Color? color;
    switch (_src) {
      case _LocSource.gps:
        if (_lat == null) {
          title = 'Ustalam położenie…';
          sub = 'Stań przy grobie i chwilę poczekaj';
          icon = Icons.gps_not_fixed;
        } else {
          final a = _acc ?? 99;
          title = 'Położenie ±${a < 1 ? '<1' : a.round()} m';
          sub = '$_samples odczytów GPS${_lastAcc != null ? ' (ostatni ±${_lastAcc!.round()} m)' : ''} · im dłużej stoisz, tym dokładniej';
          icon = Icons.gps_fixed;
          color = a <= 6 ? Colors.green.shade700 : (a <= 15 ? cs.primary : cs.error);
        }
      case _LocSource.map:
        title = 'Położenie wskazane na mapie';
        sub = '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}';
      case _LocSource.photo:
        title = 'Położenie ze zdjęcia';
        sub = 'z danych GPS zapisanych w zdjęciu';
      case _LocSource.saved:
        title = 'Położenie zapisane${_acc != null ? ' (±${_acc!.round()} m)' : ''}';
        sub = 'Jeśli stoisz przy grobie, możesz je ustalić od nowa';
      case _LocSource.none:
        title = 'Bez położenia';
        sub = _locError ?? 'Dodaj je, żeby trafić do grobu kompasem';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ListTile(
            leading: Icon(icon, color: color),
            title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            subtitle: Text(sub),
            trailing: _src == _LocSource.gps && _sampler != null ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              if (_src == _LocSource.gps && _sampler != null)
                FilledButton.tonalIcon(
                  onPressed: _lat == null
                      ? null
                      : () {
                          _stopGps();
                          setState(() {});
                        },
                  icon: const Icon(Icons.check),
                  label: const Text('Zatwierdź'),
                )
              else
                OutlinedButton.icon(onPressed: _startGps, icon: const Icon(Icons.my_location), label: Text(_src == _LocSource.none ? 'Jestem przy grobie' : 'Ustal tutaj')),
              OutlinedButton.icon(onPressed: _pickOnMap, icon: const Icon(Icons.map_outlined), label: const Text('Na mapie')),
              if (_lat != null && _src != _LocSource.gps)
                TextButton(
                  onPressed: () => setState(() {
                    _lat = _lng = _acc = null;
                    _src = _LocSource.none;
                  }),
                  child: const Text('Usuń'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final cemItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem(value: null, child: Text('— nie wybrano —')),
      for (final c in _cems) DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nowy grób' : 'Edycja grobu'),
        actions: [IconButton(tooltip: 'Podyktuj wszystko', icon: const Icon(Icons.record_voice_over_outlined), onPressed: _dictateAll)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Card(
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Szybko', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Zrób zdjęcie nagrobka – odczytam imiona i daty. Albo podyktuj wszystko naraz.', style: TextStyle(color: cs.onPrimaryContainer)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: () => _photo(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Nagrobek'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.tonalIcon(onPressed: _dictateAll, icon: const Icon(Icons.mic_none), label: const Text('Podyktuj'))),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => _photo(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Zdjęcie z galerii')),
              ),
            ]),
          ),
        ),
        if (_pendingPhotos.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(top: 8), children: [
              for (final p in _pendingPhotos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(p), width: 76, height: 76, fit: BoxFit.cover, cacheWidth: 228)),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _pendingPhotos.remove(p)),
                        child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        SectionTitle('Osoby pochowane', trailing: TextButton.icon(onPressed: () => _editPerson(null), icon: const Icon(Icons.person_add_alt), label: const Text('Dodaj'))),
        if (_people.isEmpty) ...[
          VoiceField(controller: _qFirst, label: 'Imię', caps: TextCapitalization.words, onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          VoiceField(controller: _qLast, label: 'Nazwisko', caps: TextCapitalization.words, onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: PartialDateField(controller: _qBirth, label: 'Ur.')),
            const SizedBox(width: 8),
            Expanded(child: PartialDateField(controller: _qDeath, label: 'Zm.')),
          ]),
        ] else
          for (final p in _people)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(child: Text(p.firstName.isEmpty ? '?' : p.firstName[0])),
                title: Text(p.fullName),
                subtitle: Text([
                  if (p.birth != null) 'ur. ${p.birth!.format()}',
                  if (p.death != null) 'zm. ${p.death!.format()}',
                  if ((p.relation ?? '').isNotEmpty) p.relation!,
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editPerson(p),
              ),
            ),
        const SectionTitle('Miejsce'),
        _locationCard(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int?>(
              key: ValueKey('cem_$_cemId'),
              initialValue: _cems.any((c) => c.id == _cemId) ? _cemId : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Cmentarz', helperText: _newCemName != null && _cemId == null ? 'Nowy: $_newCemName' : null),
              items: cemItems,
              onChanged: (v) => setState(() {
                _cemId = v;
                if (v != null) _newCemName = null;
              }),
            ),
          ),
          IconButton(tooltip: 'Cmentarze w pobliżu (mapa)', onPressed: _nearby, icon: const Icon(Icons.travel_explore)),
          IconButton(tooltip: 'Nowy cmentarz', onPressed: _newCemetery, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _section, decoration: const InputDecoration(labelText: 'Kwatera'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _row, decoration: const InputDecoration(labelText: 'Rząd'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'Numer'))),
        ]),
        const SizedBox(height: 12),
        VoiceField(controller: _directions, label: 'Jak dojść', hint: 'np. od głównej bramy prosto, za kaplicą w lewo, trzeci rząd', maxLines: 4),
        const SectionTitle('Pozostałe'),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Rodzaj grobu'),
          items: [for (final t in graveTypes) DropdownMenuItem(value: t, child: Text(t))],
          onChanged: (v) => setState(() => _type = v),
        ),
        const SizedBox(height: 12),
        PartialDateField(controller: _fee, label: 'Opłata za miejsce ważna do'),
        const SizedBox(height: 12),
        VoiceField(controller: _notes, label: 'Notatki', maxLines: 5, append: true),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Na liście na Wszystkich Świętych'),
          value: _g.allSaints,
          onChanged: (v) => setState(() => _g.allSaints = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ulubiony (na górze listy)'),
          value: _g.favorite,
          onChanged: (v) => setState(() => _g.favorite = v),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
          label: const Text('Zapisz'),
        ),
      ]),
    );
  }
}
