import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/expenses.dart';
import '../sync/sync_service.dart';
import 'common.dart';

String zl(double v) {
  final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).replaceAll('.', ',');
  // odstępy tysięcy
  final parts = s.split(',');
  final b = StringBuffer();
  final i = parts[0];
  for (var k = 0; k < i.length; k++) {
    if (k > 0 && (i.length - k) % 3 == 0 && i[k - 1] != '-') b.write(' ');
    b.write(i[k]);
  }
  return '${b.toString()}${parts.length > 1 ? ',${parts[1]}' : ''} zł';
}

/// Dodawanie / edycja wydatku.
Future<void> editExpense(BuildContext context, {required int graveId, Expense? expense, List<String> names = const []}) async {
  final e = expense ?? Expense(graveId: graveId, amount: 0);
  final amount = TextEditingController(text: expense == null ? '' : expense.amount.toStringAsFixed(2).replaceAll('.', ','));
  final note = TextEditingController(text: e.note ?? '');
  final paid = TextEditingController(text: e.paidBy ?? (expense == null ? (await SyncConfig.load()).myName : ''));
  var cat = e.category;
  var date = e.dateTime;
  if (!context.mounted) return;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(c).viewInsets.bottom + 16),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(expense == null ? 'Nowy wydatek' : 'Wydatek', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: expense == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Kwota', suffixText: 'zł'),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: -6, children: [
              for (final k in expenseCategories)
                ChoiceChip(label: Text(k), selected: cat == k, visualDensity: VisualDensity.compact, onSelected: (_) => set(() => cat = k)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: paid, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Kto zapłacił')),
            if (names.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final n in names) ActionChip(label: Text(n), visualDensity: VisualDensity.compact, onPressed: () => set(() => paid.text = n)),
              ]),
            const SizedBox(height: 8),
            VoiceField(controller: note, label: 'Notatka', hint: 'np. opłata na 20 lat, faktura nr…'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(fmtLong(date)),
              onTap: () async {
                final d = await showDatePicker(context: c, initialDate: date, firstDate: DateTime(1950), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) set(() => date = d);
              },
            ),
            Row(children: [
              if (expense != null)
                TextButton(
                  onPressed: () async {
                    await AppDb.I.deleteExpense(expense.id!);
                    if (c.mounted) Navigator.pop(c, false);
                  },
                  child: Text('Usuń', style: TextStyle(color: Theme.of(c).colorScheme.error)),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Zapisz')),
            ]),
          ]),
        ),
      ),
    ),
  );
  if (ok != true) return;
  final v = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.'));
  if (v == null || v <= 0) {
    if (context.mounted) snack(context, 'Podaj kwotę');
    return;
  }
  e
    ..amount = v
    ..category = cat
    ..note = note.text.trim().isEmpty ? null : note.text.trim()
    ..paidBy = paid.text.trim().isEmpty ? null : paid.text.trim()
    ..date = date.millisecondsSinceEpoch;
  await AppDb.I.saveExpense(e);
}

/// Wydatki: jednego grobu albo wszystkich, z rozliczeniem kto ile dołożył.
class ExpensesScreen extends StatefulWidget {
  final int? graveId;
  final String? title;
  const ExpensesScreen({super.key, this.graveId, this.title});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  List<Expense> _items = [];
  Map<int, GraveView> _graves = {};
  int? _year;

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
    final e = await AppDb.I.expenses(graveId: widget.graveId);
    final g = {for (final v in await AppDb.I.graveViews()) v.grave.id!: v};
    if (mounted) {
      setState(() {
        _items = e.where((x) => g.containsKey(x.graveId)).toList();
        _graves = g;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final years = {for (final e in _items) e.dateTime.year}.toList()..sort((a, b) => b.compareTo(a));
    final list = _year == null ? _items : _items.where((e) => e.dateTime.year == _year).toList();
    final total = list.fold<double>(0, (a, e) => a + e.amount);
    final s = settle(list);
    final names = {for (final e in _items) if ((e.paidBy ?? '').isNotEmpty) e.paidBy!}.toList()..sort();
    final byCat = <String, double>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Wydatki na groby')),
      floatingActionButton: widget.graveId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => editExpense(context, graveId: widget.graveId!, names: names),
              icon: const Icon(Icons.add),
              label: const Text('Wydatek'),
            ),
      body: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
        if (years.length > 1)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('razem'), selected: _year == null, onSelected: (_) => setState(() => _year = null))),
              for (final y in years)
                Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text('$y'), selected: _year == y, onSelected: (_) => setState(() => _year = y))),
            ]),
          ),
        Card(
          margin: const EdgeInsets.all(16),
          color: cs.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Razem ${zl(total)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: cs.onPrimaryContainer)),
              for (final e in (byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                Text('${e.key}: ${zl(e.value)}', style: TextStyle(color: cs.onPrimaryContainer)),
            ]),
          ),
        ),
        if (s.paid.length > 1) ...[
          const SectionTitle('Rozliczenie (po równo)'),
          for (final e in s.paid.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline),
              title: Text(e.key),
              subtitle: Text('zapłacił(a) ${zl(e.value)}'),
              trailing: Text(
                s.balance[e.key]!.abs() < 0.01 ? 'rozliczony' : (s.balance[e.key]! > 0 ? 'dostaje ${zl(s.balance[e.key]!)}' : 'dopłaca ${zl(-s.balance[e.key]!)}'),
                style: TextStyle(color: s.balance[e.key]! < -0.01 ? cs.error : cs.primary, fontWeight: FontWeight.w600),
              ),
            ),
          for (final t in s.transfers)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 4),
              child: Text('${t.$1} → ${t.$2}: ${zl(t.$3)}', style: TextStyle(color: cs.onSurfaceVariant)),
            ),
        ],
        SectionTitle('Wpisy (${list.length})'),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(widget.graveId == null ? 'Wydatki dodasz na karcie grobu.' : 'Brak wydatków.', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final e in list)
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('${zl(e.amount)} · ${e.category}'),
            subtitle: Text([
              fmtDate(e.dateTime),
              if (e.paidBy != null) e.paidBy!,
              if (widget.graveId == null && _graves[e.graveId] != null) _graves[e.graveId]!.title,
              if (e.note != null) e.note!,
            ].join(' · ')),
            onTap: () => editExpense(context, graveId: e.graveId, expense: e, names: names),
          ),
      ]),
    );
  }
}
