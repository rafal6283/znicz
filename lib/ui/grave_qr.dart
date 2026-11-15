import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';

/// Link otwierający miejsce grobu w mapach (działa u każdego, bez aplikacji).
String graveMapsLink(GraveView g) {
  final lat = g.grave.lat ?? g.cemetery?.lat;
  final lng = g.grave.lng ?? g.cemetery?.lng;
  if (lat == null || lng == null) return '';
  return 'https://www.google.com/maps/search/?api=1&query=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// Kod QR do grobu: zeskanowany aparatem otwiera nawigację do grobu – dla rodziny bez aplikacji.
class GraveQrScreen extends StatelessWidget {
  final GraveView grave;
  const GraveQrScreen({super.key, required this.grave});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final link = graveMapsLink(grave);
    final where = [grave.cemetery?.label, grave.grave.placeLabel].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    return Scaffold(
      appBar: AppBar(title: const Text('Kod QR do grobu')),
      body: link.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Grób nie ma zapisanego położenia – dodaj je, żeby utworzyć kod.')))
          : ListView(padding: const EdgeInsets.all(24), children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(data: link, size: 260, backgroundColor: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(grave.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              if (where.isNotEmpty) Text(where, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              if ((grave.grave.directions ?? '').isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(grave.grave.directions!, textAlign: TextAlign.center)),
              const SizedBox(height: 16),
              Text(
                'Zeskanuj aparatem telefonu – otworzy się mapa z nawigacją do grobu. Działa bez aplikacji Znicz, '
                'więc możesz pokazać kod komuś na miejscu albo wydrukować go razem z opisem.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: [grave.title, if (where.isNotEmpty) where, if ((grave.grave.directions ?? '').isNotEmpty) 'Jak dojść: ${grave.grave.directions}', link].join('\n'),
                )),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Wyślij link'),
              ),
            ]),
    );
  }
}
