import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../services/presence.dart';
import 'cemetery.dart';
import 'cemetery_icon.dart';
import 'compass_screen.dart';
import 'visit_edit.dart';

/// Baner „Jesteś na cmentarzu …” z szybkimi akcjami: prowadź do grobu, zapisz wizytę.
class PresenceBanner extends StatefulWidget {
  const PresenceBanner({super.key});
  @override
  State<PresenceBanner> createState() => _PresenceBannerState();
}

class _PresenceBannerState extends State<PresenceBanner> {
  List<GraveView> _graves = [];

  @override
  void initState() {
    super.initState();
    CemeteryPresence.current.addListener(_load);
    CemeteryPresence.check();
  }

  @override
  void dispose() {
    CemeteryPresence.current.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final c = CemeteryPresence.current.value;
    final g = c == null ? <GraveView>[] : (await AppDb.I.graveViews()).where((v) => v.grave.cemeteryId == c.id).toList();
    if (mounted) setState(() => _graves = g);
  }

  @override
  Widget build(BuildContext context) {
    final c = CemeteryPresence.current.value;
    if (c == null) return const SizedBox();
    final cs = Theme.of(context).colorScheme;
    final one = _graves.length == 1 ? _graves.first : null;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CemeteryIcon(kind: c.kind, color: cs.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Jesteś na cmentarzu: ${c.label}', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: cs.onTertiaryContainer),
              onPressed: () {
                CemeteryPresence.dismissed.add(c.uid);
                CemeteryPresence.current.value = null;
              },
            ),
          ]),
          Wrap(spacing: 8, children: [
            if (one != null && one.grave.hasLocation)
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompassScreen(grave: one))),
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Prowadź do grobu'),
              )
            else if (_graves.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: c.id!))),
                icon: const Icon(Icons.explore_outlined),
                label: Text('Groby tutaj (${_graves.length})'),
              ),
            if (one != null)
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VisitEditScreen(graveId: one.grave.id!))),
                icon: const Icon(Icons.local_fire_department_outlined),
                label: const Text('Zapisz wizytę'),
              ),
          ]),
        ]),
      ),
    );
  }
}
