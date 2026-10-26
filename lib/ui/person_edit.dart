import 'package:flutter/material.dart';

import '../data/models.dart';
import '../logic/dates_pl.dart';
import '../logic/dictation_parser.dart';
import 'common.dart';
import 'dictation.dart';

class PersonEditResult {
  final Person? person; // null = usuń
  PersonEditResult(this.person);
}

const relationSuggestions = ['mama', 'tata', 'babcia', 'dziadek', 'prababcia', 'pradziadek', 'brat', 'siostra', 'ciocia', 'wujek', 'mąż', 'żona', 'teść', 'teściowa'];

/// Edycja osoby pochowanej (działa też na osobie jeszcze niezapisanej w bazie).
class PersonEditScreen extends StatefulWidget {
  final Person person;
  final bool isNew;
  const PersonEditScreen({super.key, required this.person, this.isNew = false});
  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends State<PersonEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.person.firstName);
  late final _last = TextEditingController(text: widget.person.lastName);
  late final _maiden = TextEditingController(text: widget.person.maidenName ?? '');
  late final _relation = TextEditingController(text: widget.person.relation ?? '');
  late final _birth = TextEditingController(text: widget.person.birth?.format() ?? '');
  late final _death = TextEditingController(text: widget.person.death?.format() ?? '');
  late final _burial = TextEditingController(text: widget.person.burial?.format() ?? '');
  late final _inscription = TextEditingController(text: widget.person.inscription ?? '');
  late final _notes = TextEditingController(text: widget.person.notes ?? '');
  late bool _remindDeath = widget.person.remindDeath;
  late bool _remindBirth = widget.person.remindBirth;

  @override
  void dispose() {
    for (final c in [_first, _last, _maiden, _relation, _birth, _death, _burial, _inscription, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _dictateAll() async {
    final t = await dictate(context, title: 'Podyktuj dane osoby', hint: 'np. „Anna Kowalska z domu Nowak, babcia, urodzona 3 maja 1930, zmarła 12 stycznia 2001”');
    if (t == null || t.isEmpty) return;
    final r = parseDictation(t);
    if (r.people.isEmpty) {
      if (mounted) snack(context, 'Nie rozpoznano danych – wpisz je ręcznie albo powiedz wyraźniej');
      return;
    }
    final g = r.people.first;
    setState(() {
      if (g.firstName.isNotEmpty) _first.text = g.firstName;
      if (g.lastName.isNotEmpty) _last.text = g.lastName;
      if (g.maidenName != null) _maiden.text = g.maidenName!;
      if (g.relation != null) _relation.text = g.relation!;
      if (g.birth != null) _birth.text = g.birth!.format();
      if (g.death != null) _death.text = g.death!.format();
      if (g.burial != null) _burial.text = g.burial!.format();
      if (g.note != null) _notes.text = [_notes.text.trim(), g.note!].where((e) => e.isNotEmpty).join('\n');
    });
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? true)) return;
    final p = widget.person
      ..firstName = _first.text.trim()
      ..lastName = _last.text.trim()
      ..maidenName = _maiden.text.trim().isEmpty ? null : _maiden.text.trim()
      ..relation = _relation.text.trim().isEmpty ? null : _relation.text.trim()
      ..birth = parseLooseDate(_birth.text)
      ..death = parseLooseDate(_death.text)
      ..burial = parseLooseDate(_burial.text)
      ..inscription = _inscription.text.trim().isEmpty ? null : _inscription.text.trim()
      ..notes = _notes.text.trim().isEmpty ? null : _notes.text.trim()
      ..remindDeath = _remindDeath
      ..remindBirth = _remindBirth;
    if (p.firstName.isEmpty && p.lastName.isEmpty) {
      snack(context, 'Wpisz przynajmniej imię albo nazwisko');
      return;
    }
    Navigator.pop(context, PersonEditResult(p));
  }

  @override
  Widget build(BuildContext context) {
    final death = parseLooseDate(_death.text);
    final birth = parseLooseDate(_birth.text);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nowa osoba' : 'Osoba pochowana'),
        actions: [
          IconButton(tooltip: 'Podyktuj wszystko', icon: const Icon(Icons.record_voice_over_outlined), onPressed: _dictateAll),
          if (!widget.isNew)
            IconButton(
              tooltip: 'Usuń osobę',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Usunąć osobę?', 'Dane tej osoby zostaną usunięte z grobu.') && context.mounted) {
                  Navigator.pop(context, PersonEditResult(null));
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          VoiceField(controller: _first, label: 'Imię (imiona)', caps: TextCapitalization.words),
          const SizedBox(height: 12),
          VoiceField(controller: _last, label: 'Nazwisko', caps: TextCapitalization.words),
          const SizedBox(height: 12),
          VoiceField(controller: _maiden, label: 'Nazwisko rodowe', caps: TextCapitalization.words),
          const SizedBox(height: 12),
          VoiceField(controller: _relation, label: 'Kim była dla Ciebie', hint: 'np. babcia ze strony mamy', caps: TextCapitalization.none),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: -6, children: [
            for (final r in relationSuggestions)
              ActionChip(label: Text(r), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _relation.text = r)),
          ]),
          const SizedBox(height: 16),
          PartialDateField(controller: _birth, label: 'Data urodzenia'),
          const SizedBox(height: 12),
          PartialDateField(controller: _death, label: 'Data śmierci'),
          if (ageAt(birth, death) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Przeżył(a) ${ageAt(birth, death)} ${yearsWord(ageAt(birth, death)!)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 12),
          PartialDateField(controller: _burial, label: 'Data pogrzebu'),
          const SizedBox(height: 16),
          VoiceField(controller: _inscription, label: 'Napis z nagrobka', maxLines: 6, append: true),
          const SizedBox(height: 12),
          VoiceField(controller: _notes, label: 'Wspomnienia, notatki', maxLines: 6, append: true),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Przypominaj o rocznicy śmierci'),
            subtitle: Text(death?.isFull == true ? 'co roku ${fmtDayMonth(death!.toDateTime())}' : 'potrzebna pełna data śmierci'),
            value: _remindDeath,
            onChanged: (v) => setState(() => _remindDeath = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Przypominaj o rocznicy urodzin'),
            subtitle: Text(birth?.isFull == true ? 'co roku ${fmtDayMonth(birth!.toDateTime())}' : 'potrzebna pełna data urodzenia'),
            value: _remindBirth,
            onChanged: (v) => setState(() => _remindBirth = v),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Zapisz')),
        ]),
      ),
    );
  }
}
