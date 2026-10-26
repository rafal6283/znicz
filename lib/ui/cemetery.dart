import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/location.dart';
import 'common.dart';
import 'graves_list.dart';
import 'map_screen.dart';

Future<void> openExternalNavigation(BuildContext context, double lat, double lng, {String? label, bool walking = false}) async {
  final mode = walking ? 'walking' : 'driving';
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=$mode');
  final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label ?? 'Grób')})');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (!await launchUrl(geo, mode: LaunchMode.externalApplication) && context.mounted) {
      snack(context, 'Nie znaleziono aplikacji z mapami');
    }
  }
}

/// Edycja cmentarza. Zwraca zapisany cmentarz.
class CemeteryEditScreen extends StatefulWidget {
  final Cemetery? cemetery;
  final double? lat;
  final double? lng;
  final String? name;
  const CemeteryEditScreen({super.key, this.cemetery, this.lat, this.lng, this.name});
  @override
  State<CemeteryEditScreen> createState() => _CemeteryEditScreenState();
}

class _CemeteryEditScreenState extends State<CemeteryEditScreen> {
  late final Cemetery c = widget.cemetery ?? Cemetery(name: widget.name ?? '', lat: widget.lat, lng: widget.lng);
  late final _name = TextEditingController(text: c.name);
  late final _town = TextEditingController(text: c.town ?? '');
  late final _address = TextEditingController(text: c.address ?? '');
  late final _phone = TextEditingController(text: c.phone ?? '');
  late final _hours = TextEditingController(text: c.hours ?? '');
  late final _url = TextEditingController(text: c.searchUrl ?? '');
  late final _notes = TextEditingController(text: c.notes ?? '');
  late String? _kind = c.kind;
  late double? _lat = c.lat;
  late double? _lng = c.lng;

  @override
  void dispose() {
    for (final x in [_name, _town, _address, _phone, _hours, _url, _notes]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _here() async {
    final err = await LocationService.ensurePermission();
    if (err != null) {
      if (mounted) snack(context, err);
      return;
    }
    final p = await LocationService.current();
    if (p != null && mounted) {
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
      });
    }
  }

  Future<void> _pick() async {
    final r = await Navigator.push<LatLng>(context, MaterialPageRoute(builder: (_) => MapPickerScreen(initial: _lat == null ? null : LatLng(_lat!, _lng!), title: 'Wejście na cmentarz')));
    if (r != null) {
      setState(() {
        _lat = r.latitude;
        _lng = r.longitude;
      });
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      snack(context, 'Podaj nazwę cmentarza');
      return;
    }
    String? t(TextEditingController x) => x.text.trim().isEmpty ? null : x.text.trim();
    c
      ..name = _name.text.trim()
      ..town = t(_town)
      ..address = t(_address)
      ..phone = t(_phone)
      ..hours = t(_hours)
      ..searchUrl = t(_url)
      ..notes = t(_notes)
      ..kind = _kind
      ..lat = _lat
      ..lng = _lng;
    await AppDb.I.saveCemetery(c);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.cemetery == null ? 'Nowy cmentarz' : 'Cmentarz')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        VoiceField(controller: _name, label: 'Nazwa', hint: 'np. Cmentarz parafialny', caps: TextCapitalization.sentences),
        const SizedBox(height: 12),
        VoiceField(controller: _town, label: 'Miejscowość', caps: TextCapitalization.words),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Rodzaj'),
          items: [for (final k in cemeteryKinds) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => setState(() => _kind = v),
        ),
        const SizedBox(height: 12),
        VoiceField(controller: _address, label: 'Adres', caps: TextCapitalization.words),
        const SizedBox(height: 12),
        VoiceField(controller: _phone, label: 'Telefon do kancelarii / zarządcy', keyboard: TextInputType.phone, caps: TextCapitalization.none),
        const SizedBox(height: 12),
        VoiceField(controller: _hours, label: 'Godziny otwarcia', caps: TextCapitalization.none),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Wyszukiwarka grobów tego cmentarza', hintText: 'np. https://miasto.grobonet.com'),
        ),
        const SizedBox(height: 12),
        VoiceField(controller: _notes, label: 'Notatki (parking, woda, gdzie kupić znicze)', maxLines: 4, append: true),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(_lat == null ? 'Położenie nieustalone' : 'Położenie zapisane'),
            subtitle: _lat == null ? const Text('Potrzebne do nawigacji samochodem') : Text('${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: _here, icon: const Icon(Icons.my_location), label: const Text('Jestem tu')),
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.map_outlined), label: const Text('Wskaż na mapie')),
        ]),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ]),
    );
  }
}

/// Karta cmentarza: dane, kontakt, nawigacja i groby na nim.
class CemeteryScreen extends StatefulWidget {
  final int cemeteryId;
  const CemeteryScreen({super.key, required this.cemeteryId});
  @override
  State<CemeteryScreen> createState() => _CemeteryScreenState();
}

class _CemeteryScreenState extends State<CemeteryScreen> {
  Cemetery? _c;
  List<GraveView> _graves = [];

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final c = await AppDb.I.cemetery(widget.cemeteryId);
    final g = (await AppDb.I.graveViews()).where((x) => x.grave.cemeteryId == widget.cemeteryId).toList();
    if (mounted) {
      setState(() {
        _c = c;
        _graves = g;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Edytuj',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryEditScreen(cemetery: c))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'del') {
                final ok = await confirm(context, 'Usunąć cmentarz?', 'Groby (${_graves.length}) zostaną, ale bez przypisanego cmentarza.');
                if (ok) {
                  await AppDb.I.deleteCemetery(c.id!);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Usuń cmentarz'))],
          ),
        ],
      ),
      body: ListView(children: [
        if ((c.town ?? '').isNotEmpty || (c.kind ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text([c.kind, c.town, c.address].whereType<String>().where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.hasLocation)
              FilledButton.tonalIcon(
                onPressed: () => openExternalNavigation(context, c.lat!, c.lng!, label: c.name),
                icon: const Icon(Icons.directions_car_outlined),
                label: const Text('Dojazd'),
              ),
            if ((c.phone ?? '').isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () => launchUrl(Uri.parse('tel:${c.phone!.replaceAll(' ', '')}')),
                icon: const Icon(Icons.call_outlined),
                label: const Text('Zadzwoń'),
              ),
            if ((c.searchUrl ?? '').isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () {
                  var u = c.searchUrl!.trim();
                  if (!u.startsWith('http')) u = 'https://$u';
                  launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.travel_explore),
                label: const Text('Wyszukiwarka grobów'),
              ),
          ]),
        ),
        if ((c.hours ?? '').isNotEmpty) ListTile(leading: const Icon(Icons.schedule), title: Text(c.hours!)),
        if ((c.notes ?? '').isNotEmpty) ListTile(leading: const Icon(Icons.notes), title: Text(c.notes!)),
        SectionTitle('Groby (${_graves.length})'),
        for (final g in _graves) GraveTile(g),
        const SizedBox(height: 24),
      ]),
    );
  }
}
