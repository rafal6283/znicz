import 'package:flutter/material.dart';

import '../data/db.dart';
import '../services/doba.dart';
import 'common.dart';
import 'visit_edit.dart';

/// Wizyty podpowiedziane przez Dobę: kiedy byłeś na cmentarzu z grobami bliskich.
class DobaVisitsScreen extends StatefulWidget {
  const DobaVisitsScreen({super.key});
  @override
  State<DobaVisitsScreen> createState() => _DobaVisitsScreenState();
}

class _DobaVisitsScreenState extends State<DobaVisitsScreen> {
  List<DobaVisitProposal>? _list;
  ({bool installed, bool granted})? _st;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await DobaBridge.status();
    final l = st.granted ? await DobaBridge.proposals() : <DobaVisitProposal>[];
    if (!mounted) return;
    setState(() {
      _st = st;
      _list = l;
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('Wizyty z Doby')),
      body: st == null || list == null
          ? const Center(child: CircularProgressIndicator())
          : !st.installed
              ? const EmptyState(
                  icon: Icons.route_outlined,
                  title: 'Doba nie jest zainstalowana',
                  body: 'Doba zapisuje automatycznie, gdzie i jak długo przebywasz. Po instalacji Znicz sam podpowie wizyty na cmentarzach.',
                )
              : !st.granted
                  ? EmptyState(
                      icon: Icons.lock_open_outlined,
                      title: 'Połącz z Dobą',
                      body: 'Znicz odczyta z Doby tylko pobyty — porówna je z położeniem Twoich cmentarzy i grobów. Nic nie jest wysyłane do internetu.',
                      action: FilledButton(
                        onPressed: () async {
                          final ok = await DobaBridge.request();
                          if (!ok && context.mounted) snack(context, 'Bez zgody Znicz nie widzi pobytów z Doby');
                          _load();
                        },
                        child: const Text('Pozwól'),
                      ),
                    )
                  : list.isEmpty
                      ? const EmptyState(
                          icon: Icons.check_circle_outline,
                          title: 'Wszystko zapisane',
                          body: 'Brak nowych pobytów na Twoich cmentarzach z ostatnich 90 dni.',
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 32),
                          children: [for (final p in list) _ProposalCard(p, onDone: _load)],
                        ),
    );
  }
}

class _ProposalCard extends StatefulWidget {
  final DobaVisitProposal p;
  final VoidCallback onDone;
  const _ProposalCard(this.p, {required this.onDone});
  @override
  State<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends State<_ProposalCard> {
  late final Set<int> _graves = {for (final g in widget.p.graves) g.grave.id!};
  final Set<String> _actions = {'znicz'};

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final s = DateTime.fromMillisecondsSinceEpoch(p.stay.start);
    final e = DateTime.fromMillisecondsSinceEpoch(p.stay.end);
    const days = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];
    const months = ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'];
    final day = '${days[s.weekday - 1]}, ${s.day} ${months[s.month - 1]} ${s.year}';
    String two(int v) => v.toString().padLeft(2, '0');
    String hmf(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(day, style: Theme.of(context).textTheme.titleMedium),
          Text('${p.cemetery?.label ?? p.stay.place ?? 'Cmentarz'} · ${hmf(s)}–${hmf(e)} (${p.stay.length.inMinutes} min)',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          for (final g in p.graves)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _graves.contains(g.grave.id),
              onChanged: (v) => setState(() => v == true ? _graves.add(g.grave.id!) : _graves.remove(g.grave.id)),
              title: Text(g.title),
            ),
          Wrap(spacing: 6, children: [
            for (final a in const ['znicz', 'kwiaty', 'sprzątanie', 'modlitwa'])
              FilterChip(
                avatar: Icon(visitIcon(a), size: 18),
                label: Text(a),
                selected: _actions.contains(a),
                onSelected: (v) => setState(() => v ? _actions.add(a) : _actions.remove(a)),
              ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () async {
                await DobaBridge.dismiss(p);
                widget.onDone();
              },
              child: const Text('Pomiń'),
            ),
            FilledButton(
              onPressed: _graves.isEmpty
                  ? null
                  : () async {
                      await DobaBridge.accept(p, _graves, _actions);
                      if (context.mounted) snack(context, 'Dopisano ${_graves.length} wizyt');
                      widget.onDone();
                    },
              child: const Text('Dopisz wizyty'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Baner na liście grobów, gdy Doba ma nowe wizyty do dopisania.
class DobaBanner extends StatefulWidget {
  const DobaBanner({super.key});
  @override
  State<DobaBanner> createState() => _DobaBannerState();
}

class _DobaBannerState extends State<DobaBanner> {
  int _n = 0;

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
    final l = await DobaBridge.proposals();
    if (mounted) setState(() => _n = l.length);
  }

  @override
  Widget build(BuildContext context) {
    if (_n == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: const Icon(Icons.route_outlined),
          title: Text(_n == 1 ? 'Doba: 1 pobyt na cmentarzu' : 'Doba: $_n pobyty na cmentarzach'),
          subtitle: const Text('Dopisać wizyty przy grobach?'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const DobaVisitsScreen()));
            _load();
          },
        ),
      ),
    );
  }
}
