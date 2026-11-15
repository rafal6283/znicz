import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/dates_pl.dart';
import 'common.dart';

/// Ile czego kupić – suma dla grupy grobów.
class ShoppingNeed {
  int candles = 0;
  int flowers = 0;
  int graves = 0;
}

/// Zakupy pogrupowane wg osoby, która zajmuje się grobem (pole „kto odwiedza”).
Map<String, ShoppingNeed> shoppingByPerson(List<Grave> graves) {
  final out = <String, ShoppingNeed>{};
  for (final g in graves) {
    if (!g.allSaints) continue;
    final who = (g.visitor ?? '').trim().isEmpty ? 'Nieprzydzielone' : g.visitor!.trim();
    final n = out.putIfAbsent(who, ShoppingNeed.new);
    n
      ..candles += g.candles
      ..flowers += g.flowers
      ..graves += 1;
  }
  return out;
}

/// Lista zakupów na Wszystkich Świętych: znicze i kwiaty dla każdego grobu, podział na osoby.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  List<GraveView> _graves = [];
  Set<String> _bought = {}; // kupione: „osoba|znicze” / „osoba|kwiaty”
  String get _prefKey => 'shopping_${DateTime.now().month == 12 ? DateTime.now().year + 1 : DateTime.now().year}';

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
    final g = (await AppDb.I.graveViews()).where((v) => v.grave.allSaints).toList()
      ..sort((a, b) => fold(a.grave.visitor ?? '~').compareTo(fold(b.grave.visitor ?? '~')));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _graves = g;
      _bought = (prefs.getStringList(_prefKey) ?? const []).toSet();
    });
  }

  Future<void> _toggle(String key) async {
    setState(() => _bought.contains(key) ? _bought.remove(key) : _bought.add(key));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey, _bought.toList());
  }

  Future<void> _change(Grave g, {int dc = 0, int df = 0}) async {
    g
      ..candles = (g.candles + dc).clamp(0, 30)
      ..flowers = (g.flowers + df).clamp(0, 20);
    await AppDb.I.saveGrave(g);
  }

  String _text(Map<String, ShoppingNeed> by) {
    final b = StringBuffer('Zakupy na Wszystkich Świętych\n');
    for (final e in by.entries) {
      b.writeln('\n${e.key} (${e.value.graves} ${e.value.graves == 1 ? 'grób' : 'grobów'}): znicze ${e.value.candles}, kwiaty ${e.value.flowers}');
      for (final g in _graves.where((v) => ((v.grave.visitor ?? '').trim().isEmpty ? 'Nieprzydzielone' : v.grave.visitor!.trim()) == e.key)) {
        b.writeln('  • ${g.title}: ${g.grave.candles} zn., ${g.grave.flowers} kw.');
      }
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final by = shoppingByPerson(_graves.map((v) => v.grave).toList());
    final totalC = by.values.fold<int>(0, (a, n) => a + n.candles);
    final totalF = by.values.fold<int>(0, (a, n) => a + n.flowers);
    return Scaffold(
      appBar: AppBar(title: const Text('Zakupy na 1 listopada'), actions: [
        if (_graves.isNotEmpty)
          IconButton(
            tooltip: 'Wyślij rodzinie',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => SharePlus.instance.share(ShareParams(text: _text(by))),
          ),
      ]),
      body: _graves.isEmpty
          ? const EmptyState(icon: Icons.shopping_basket_outlined, title: 'Brak grobów na liście', body: 'W edycji grobu włącz „Na liście na Wszystkich Świętych”.')
          : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Card(
                margin: const EdgeInsets.all(16),
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.local_fire_department, size: 36, color: cs.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Razem: $totalC zniczy, $totalF kwiatów\nna ${_graves.length} grobów',
                          style: TextStyle(color: cs.onPrimaryContainer, fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
              for (final e in by.entries) ...[
                SectionTitle(e.key),
                CheckboxListTile(
                  value: _bought.contains('${e.key}|c'),
                  onChanged: (_) => _toggle('${e.key}|c'),
                  secondary: const Icon(Icons.local_fire_department_outlined),
                  title: Text('Znicze: ${e.value.candles}'),
                ),
                CheckboxListTile(
                  value: _bought.contains('${e.key}|f'),
                  onChanged: (_) => _toggle('${e.key}|f'),
                  secondary: const Icon(Icons.local_florist_outlined),
                  title: Text('Kwiaty: ${e.value.flowers}'),
                ),
                for (final g in _graves.where((v) => ((v.grave.visitor ?? '').trim().isEmpty ? 'Nieprzydzielone' : v.grave.visitor!.trim()) == e.key))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    child: Row(children: [
                      Expanded(child: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant))),
                      _Stepper(icon: Icons.local_fire_department_outlined, value: g.grave.candles, onMinus: () => _change(g.grave, dc: -1), onPlus: () => _change(g.grave, dc: 1)),
                      _Stepper(icon: Icons.local_florist_outlined, value: g.grave.flowers, onMinus: () => _change(g.grave, df: -1), onPlus: () => _change(g.grave, df: 1)),
                    ]),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Kto zajmuje się którym grobem, ustawisz na liście Wszystkich Świętych. Liczby zniczy i kwiatów zmieniają się u całej rodziny.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final IconData icon;
  final int value;
  final VoidCallback onMinus, onPlus;
  const _Stepper({required this.icon, required this.value, required this.onMinus, required this.onPlus});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(visualDensity: VisualDensity.compact, onPressed: value > 0 ? onMinus : null, icon: const Icon(Icons.remove, size: 18)),
      Icon(icon, size: 16),
      SizedBox(width: 22, child: Text('$value', textAlign: TextAlign.center)),
      IconButton(visualDensity: VisualDensity.compact, onPressed: onPlus, icon: const Icon(Icons.add, size: 18)),
    ]);
  }
}
