import '../data/models.dart';

class Settlement {
  final Map<String, double> paid; // kto ile zapłacił
  final Map<String, double> balance; // + dostaje zwrot, − dopłaca
  final List<(String, String, double)> transfers; // kto → komu ile
  Settlement(this.paid, this.balance, this.transfers);
}

/// Rozliczenie po równo między osobami, które płaciły. Wydatki bez płacącego są pomijane.
Settlement settle(List<Expense> list) {
  final paid = <String, double>{};
  for (final e in list) {
    final who = (e.paidBy ?? '').trim();
    if (who.isEmpty) continue;
    paid[who] = (paid[who] ?? 0) + e.amount;
  }
  if (paid.isEmpty) return Settlement({}, {}, []);
  final total = paid.values.fold<double>(0, (a, b) => a + b);
  final share = total / paid.length;
  final balance = {for (final e in paid.entries) e.key: _r(e.value - share)};
  // minimalne przelewy: dłużnicy spłacają wierzycieli od największych kwot
  final debt = balance.entries.where((e) => e.value < -0.005).map((e) => [e.key, -e.value]).toList()
    ..sort((a, b) => (b[1] as double).compareTo(a[1] as double));
  final cred = balance.entries.where((e) => e.value > 0.005).map((e) => [e.key, e.value]).toList()
    ..sort((a, b) => (b[1] as double).compareTo(a[1] as double));
  final out = <(String, String, double)>[];
  var i = 0, j = 0;
  while (i < debt.length && j < cred.length) {
    final x = (debt[i][1] as double) < (cred[j][1] as double) ? debt[i][1] as double : cred[j][1] as double;
    if (x > 0.005) out.add((debt[i][0] as String, cred[j][0] as String, _r(x)));
    debt[i][1] = (debt[i][1] as double) - x;
    cred[j][1] = (cred[j][1] as double) - x;
    if ((debt[i][1] as double) < 0.005) i++;
    if ((cred[j][1] as double) < 0.005) j++;
  }
  return Settlement(paid, balance, out);
}

double _r(double v) => (v * 100).round() / 100;
