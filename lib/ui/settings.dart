import 'package:flutter/material.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart' show KoofrBackupTile, KoofrConfig;
import 'package:url_launcher/url_launcher.dart';

import '../data/db.dart';
import '../data/koofr_backup.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../services/notifications.dart';
import '../sync/sync_service.dart';
import 'cemetery.dart';
import 'common.dart';
import 'grave_detail.dart';
import 'nearby_cemeteries.dart';
import 'sync_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ReminderSettings? _rem;
  SyncConfig? _sync;
  List<Cemetery> _cems = [];

  @override
  void initState() {
    super.initState();
    AppDb.I.addListener(_load);
    SyncService.I.addListener(_onSync);
    _load();
  }

  @override
  void dispose() {
    AppDb.I.removeListener(_load);
    SyncService.I.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final r = await ReminderSettings.load();
    final s = await SyncConfig.load();
    final c = await AppDb.I.cemeteries();
    if (mounted) {
      setState(() {
        _rem = r;
        _sync = s;
        _cems = c;
      });
    }
  }

  Future<void> _saveRem() async {
    await _rem!.save();
    setState(() {});
    final n = await Notifications.reschedule();
    if (mounted && _rem!.enabled) snack(context, 'Zaplanowano przypomnień: $n');
  }

  String _syncStatus() {
    final s = SyncService.I;
    if (s.running) return 'Synchronizuję…';
    if (s.lastError != null) return 'Błąd: ${s.lastError}';
    if (s.lastSync != null) return 'Ostatnio: ${fmtDate(s.lastSync!)} ${s.lastSync!.hour.toString().padLeft(2, '0')}:${s.lastSync!.minute.toString().padLeft(2, '0')}${s.lastResult != null ? ' · ${s.lastResult}' : ''}';
    return 'Jeszcze nie synchronizowano';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _rem;
    final syncOn = _sync?.isSet ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Więcej')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const SectionTitle('Rodzina'),
        ListTile(
          leading: Icon(Icons.sync, color: syncOn ? cs.primary : null),
          title: const Text('Synchronizacja rodzinna'),
          subtitle: Text(syncOn ? _syncStatus() : 'Wspólne groby przez Twój NAS lub darmową chmurę', maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: SyncService.I.lastError != null && syncOn ? cs.error : null)),
          trailing: syncOn
              ? IconButton(
                  tooltip: 'Synchronizuj teraz',
                  icon: SyncService.I.running ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                  onPressed: SyncService.I.running ? null : () => SyncService.I.syncNow(),
                )
              : const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncSettingsScreen()));
            _load();
          },
        ),
        const SectionTitle('Przypomnienia'),
        if (r != null) ...[
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Przypomnienia o rocznicach'),
            value: r.enabled,
            onChanged: (v) async {
              r.enabled = v;
              if (v) await Notifications.requestPermission();
              await _saveRem();
            },
          ),
          if (r.enabled) ...[
            ListTile(
              leading: const SizedBox(),
              title: const Text('Kiedy przypominać'),
              trailing: DropdownButton<int>(
                value: r.daysBefore,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('w dniu')),
                  DropdownMenuItem(value: 1, child: Text('dzień wcześniej')),
                  DropdownMenuItem(value: 3, child: Text('3 dni wcześniej')),
                  DropdownMenuItem(value: 7, child: Text('tydzień wcześniej')),
                ],
                onChanged: (v) {
                  r.daysBefore = v ?? 1;
                  _saveRem();
                },
              ),
            ),
            ListTile(
              leading: const SizedBox(),
              title: const Text('O godzinie'),
              trailing: Text('${r.hour}:00'),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: r.hour, minute: 0));
                if (t != null) {
                  r.hour = t.hour;
                  _saveRem();
                }
              },
            ),
            SwitchListTile(
              secondary: const SizedBox(),
              title: const Text('Przed Wszystkimi Świętymi'),
              subtitle: Text('${r.allSaintsDaysBefore} dni wcześniej – lista grobów do odwiedzenia'),
              value: r.allSaints,
              onChanged: (v) {
                r.allSaints = v;
                _saveRem();
              },
            ),
            ListTile(
              leading: const SizedBox(),
              title: const Text('Wyślij próbne powiadomienie'),
              onTap: () async {
                await Notifications.requestPermission();
                await Notifications.test();
              },
            ),
          ],
        ],
        SectionTitle('Cmentarze (${_cems.length})', trailing: IconButton(
          tooltip: 'Dodaj cmentarz ręcznie',
          icon: const Icon(Icons.add),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CemeteryEditScreen())),
        )),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: const Text('Cmentarze w pobliżu'),
          subtitle: const Text('Z mapy OpenStreetMap – z obrysem i położeniem'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NearbyCemeteriesScreen())),
        ),
        for (final c in _cems)
          ListTile(
            leading: const Icon(Icons.park_outlined),
            title: Text(c.label),
            subtitle: c.kind == null ? null : Text(c.kind!),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CemeteryScreen(cemeteryId: c.id!))),
          ),
        const SectionTitle('Dane'),
        FutureBuilder<KoofrConfig?>(
          future: koofrFromFamilySync(),
          builder: (c, snap) => KoofrBackupTile(suggestedConfig: snap.data),
        ),
        ListTile(
          leading: const Icon(Icons.file_open_outlined),
          title: const Text('Importuj grób z pliku'),
          subtitle: const Text('Plik .znicz otrzymany od rodziny'),
          onTap: () async {
            try {
              final id = await Storage.importGraveFile();
              if (id != null && context.mounted) {
                snack(context, 'Dodano grób');
                Navigator.push(context, MaterialPageRoute(builder: (_) => GraveDetailScreen(graveId: id)));
              }
            } catch (e) {
              if (context.mounted) snack(context, '$e');
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Kopia zapasowa'),
          subtitle: const Text('Wszystkie groby i zdjęcia w jednym pliku .zip'),
          onTap: () async {
            final ok = await Storage.exportBackup();
            if (ok && context.mounted) snack(context, 'Kopia zapisana');
          },
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Przywróć z kopii'),
          subtitle: const Text('Zastępuje wszystkie dane na tym telefonie'),
          onTap: () async {
            if (!await confirm(context, 'Przywrócić kopię?', 'Obecne dane na tym telefonie zostaną zastąpione danymi z kopii.', ok: 'Przywróć')) return;
            final err = await Storage.importBackup();
            if (!context.mounted) return;
            if (err == null) {
              snack(context, 'Przywrócono dane');
              Notifications.reschedule();
            } else if (err != 'Anulowano') {
              snack(context, err);
            }
          },
        ),
        const SectionTitle('Wyszukiwarki grobów'),
        ListTile(
          leading: const Icon(Icons.travel_explore),
          title: const Text('Grobonet'),
          subtitle: const Text('Ponad 1300 cmentarzy, głównie komunalne'),
          onTap: () => launchUrl(Uri.parse('https://www.grobonet.com/'), mode: LaunchMode.externalApplication),
        ),
        const SectionTitle('O aplikacji'),
        const ListTile(
          leading: Icon(Icons.local_fire_department_outlined),
          title: Text('Znicz'),
          subtitle: Text('Prywatny notatnik grobów bliskich. Dane są na Twoim telefonie i – jeśli włączysz – na Twoim serwerze.'),
        ),
      ]),
    );
  }
}
