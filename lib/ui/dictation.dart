import 'dart:async';

import 'package:flutter/material.dart';

import '../services/speech.dart';

/// Arkusz dyktowania: słucha od razu, pokazuje tekst na żywo, pozwala poprawić i dopowiedzieć.
/// Zwraca tekst albo null (anulowano).
Future<String?> dictate(BuildContext context, {required String title, String initial = '', String? hint}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _DictationSheet(title: title, initial: initial, hint: hint),
    ),
  );
}

class _DictationSheet extends StatefulWidget {
  final String title;
  final String initial;
  final String? hint;
  const _DictationSheet({required this.title, required this.initial, this.hint});
  @override
  State<_DictationSheet> createState() => _DictationSheetState();
}

class _DictationSheetState extends State<_DictationSheet> with SingleTickerProviderStateMixin {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  bool _listening = false;
  String _base = ''; // tekst sprzed bieżącego nasłuchu
  String? _error;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final ok = await Speech.init();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Rozpoznawanie mowy jest niedostępne. Sprawdź dostęp do mikrofonu i czy w telefonie jest usługa rozpoznawania mowy (np. aplikacja Google).');
      return;
    }
    _base = _c.text.trim();
    setState(() {
      _listening = true;
      _error = null;
    });
    await Speech.listen(
      onResult: (text, fin) {
        if (!mounted) return;
        final joined = _base.isEmpty ? text : '$_base $text';
        _c.value = TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
        if (fin) setState(() => _listening = false);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    // rozpoznawanie potrafi skończyć się bez wyniku – pilnuj stanu przycisku
    _watch?.cancel();
    _watch = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return t.cancel();
      if (_listening && !Speech.isListening) {
        setState(() {
          _listening = false;
          if (Speech.lastError != null && _c.text.trim() == _base) _error = _errorText(Speech.lastError!);
        });
      }
    });
  }

  String _errorText(String e) {
    if (e.contains('no_match') || e.contains('speech_timeout')) return 'Nic nie usłyszałem – dotknij mikrofonu i spróbuj jeszcze raz.';
    if (e.contains('network')) return 'Rozpoznawanie mowy potrzebuje internetu (albo pobranego pakietu języka polskiego).';
    if (e.contains('permission')) return 'Brak dostępu do mikrofonu – zezwól w ustawieniach telefonu.';
    return 'Błąd rozpoznawania mowy ($e).';
  }

  Future<void> _stop() async {
    await Speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _watch?.cancel();
    Speech.cancel();
    _pulse.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          if (widget.hint != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.hint!, style: TextStyle(color: cs.onSurfaceVariant))),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _listening ? _stop : _start,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final s = _listening ? 1 + _pulse.value * 0.12 : 1.0;
                  return Transform.scale(
                    scale: s,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening ? cs.primary : cs.surfaceContainerHighest,
                        boxShadow: _listening ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 20 * _pulse.value + 4)] : null,
                      ),
                      child: Icon(_listening ? Icons.mic : Icons.mic_none, size: 36, color: _listening ? cs.onPrimary : cs.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(_listening ? 'Słucham… (dotknij, by zakończyć)' : 'Dotknij mikrofonu, by dopowiedzieć', style: TextStyle(color: cs.onSurfaceVariant))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: cs.error))),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Rozpoznany tekst (możesz poprawić)'),
          ),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(onPressed: () => _c.clear(), child: const Text('Wyczyść')),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                await Speech.stop();
                if (context.mounted) Navigator.pop(context, _c.text.trim());
              },
              child: const Text('Gotowe'),
            ),
          ]),
        ]),
      ),
    );
  }
}
