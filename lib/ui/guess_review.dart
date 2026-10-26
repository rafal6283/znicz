import 'package:flutter/material.dart';

import '../logic/inscription_parser.dart';

/// Pokazuje osoby odczytane z nagrobka / z dyktowania i pozwala wybrać, które dodać.
Future<List<PersonGuess>?> reviewGuesses(
  BuildContext context, {
  required String title,
  required List<PersonGuess> guesses,
  String? rawText,
  List<String> extra = const [],
}) {
  return showModalBottomSheet<List<PersonGuess>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _Review(title: title, guesses: guesses, rawText: rawText, extra: extra),
  );
}

class _Review extends StatefulWidget {
  final String title;
  final List<PersonGuess> guesses;
  final String? rawText;
  final List<String> extra;
  const _Review({required this.title, required this.guesses, this.rawText, required this.extra});
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  late final List<bool> _on = List.filled(widget.guesses.length, true);

  String _line(PersonGuess g) {
    final parts = <String>[];
    if (g.birth != null) parts.add('ur. ${g.birth!.format()}');
    if (g.death != null) parts.add('zm. ${g.death!.format()}');
    if (g.burial != null) parts.add('pogrzeb ${g.burial!.format()}');
    if (g.relation != null) parts.add(g.relation!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            widget.guesses.isEmpty ? 'Nie rozpoznano osób. Możesz dodać je ręcznie.' : 'Zaznacz, co dodać. Wszystko da się później poprawić.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.guesses.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _on[i],
              onChanged: (v) => setState(() => _on[i] = v ?? false),
              title: Text(() {
                final g = widget.guesses[i];
                final n = '${g.firstName} ${g.lastName}'.trim();
                final m = g.maidenName == null ? '' : ' z d. ${g.maidenName}';
                return n.isEmpty ? '(bez imienia)$m' : '$n$m';
              }()),
              subtitle: Text(_line(widget.guesses[i])),
            ),
          for (final e in widget.extra) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check, size: 20), title: Text(e)),
          if ((widget.rawText ?? '').isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Odczytany tekst'),
              children: [Align(alignment: Alignment.centerLeft, child: SelectableText(widget.rawText!))],
            ),
          const SizedBox(height: 12),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.pop(context, [for (var i = 0; i < widget.guesses.length; i++) if (_on[i]) widget.guesses[i]]),
              child: const Text('Dodaj'),
            ),
          ]),
        ]),
      ),
    );
  }
}
