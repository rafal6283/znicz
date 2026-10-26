import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../sync/sync_service.dart';
import 'common.dart';

const _actionIcons = {
  'znicz': Icons.local_fire_department_outlined,
  'kwiaty': Icons.local_florist_outlined,
  'sprzątanie': Icons.cleaning_services_outlined,
  'modlitwa': Icons.volunteer_activism_outlined,
  'naprawa': Icons.handyman_outlined,
};

IconData visitIcon(String a) => _actionIcons[a] ?? Icons.check;

/// Zapis wizyty przy grobie (z dziennika lub po dojściu kompasem).
class VisitEditScreen extends StatefulWidget {
  final int graveId;
  final Visit? visit;
  const VisitEditScreen({super.key, required this.graveId, this.visit});
  @override
  State<VisitEditScreen> createState() => _VisitEditScreenState();
}

class _VisitEditScreenState extends State<VisitEditScreen> {
  late final Visit v = widget.visit ?? Visit(graveId: widget.graveId, actions: {'znicz'});
  late final _note = TextEditingController(text: v.note ?? '');
  late DateTime _date = v.dateTime;
  late final Set<String> _actions = {...v.actions};
  bool _photo = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    v
      ..date = _date.millisecondsSinceEpoch
      ..actions = _actions
      ..note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (widget.visit == null && v.by == null) {
      final name = (await SyncConfig.load()).myName;
      if (name.isNotEmpty) v.by = name;
    }
    await AppDb.I.saveVisit(v);
    if (_photo) {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 85);
      if (x != null) await Storage.addPhoto(widget.graveId, x.path, caption: 'Wizyta ${fmtDate(_date)}', cover: false);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.visit == null ? 'Wizyta' : 'Edycja wizyty'),
        actions: [
          if (widget.visit != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Usunąć wizytę?', 'Wpis zniknie z dziennika.')) {
                  await AppDb.I.deleteVisit(v.id!);
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('${fmtLong(_date)}, ${weekday(_date)}'),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(1990), lastDate: DateTime.now().add(const Duration(days: 1)));
            if (d != null) setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
          },
        ),
        const SizedBox(height: 8),
        Text('Co zrobione', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in visitActions)
            FilterChip(
              avatar: Icon(visitIcon(a), size: 18),
              label: Text(a),
              selected: _actions.contains(a),
              onSelected: (s) => setState(() => s ? _actions.add(a) : _actions.remove(a)),
            ),
        ]),
        const SizedBox(height: 16),
        VoiceField(controller: _note, label: 'Notatka', hint: 'np. trzeba wymienić wkład do znicza, ziemia przy płycie', maxLines: 5, append: true),
        if (widget.visit == null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _photo,
            onChanged: (x) => setState(() => _photo = x ?? false),
            title: const Text('Zrób zdjęcie grobu po zapisaniu'),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: const Text('Zapisz wizytę')),
      ]),
    );
  }
}
