import 'package:flutter/material.dart';
import 'package:koofr_backup_ui/koofr_backup_ui.dart' show KoofrBackground, KoofrBackup;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/db.dart';
import 'data/koofr_backup.dart';
import 'services/notifications.dart';
import 'sync/sync_service.dart';
import 'ui/common.dart';
import 'ui/home.dart';

/// Kopia na Koofr w tle (Android) — także przy zamkniętej aplikacji.
@pragma('vm:entry-point')
void koofrCallback() => KoofrBackground.dispatch(() async {
      await AppDb.I.init();
      return ZniczBackup();
    });

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZniczApp());
}

/// Start bazy z widocznym komunikatem błędu (zamiast zawieszenia na logo).
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> with WidgetsBindingObserver {
  late Future<void> _init = _start();
  bool _started = false;

  Future<void> _start() async {
    await AppDb.I.init().timeout(const Duration(seconds: 25));
    // każda zmiana danych → synchronizacja z rodziną za kilka sekund
    AppDb.I.onLocalChange = SyncService.I.schedule;
    _started = true;
    // w tle – nie blokują startu
    Notifications.reschedule();
    SyncService.I.loadStatus().then((_) => SyncService.I.syncNow(quiet: true));
    KoofrBackup.setup(ZniczBackup()).then((_) => KoofrBackground.start(koofrCallback)).ignore();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // po powrocie do aplikacji pobierz zmiany rodziny
    if (state == AppLifecycleState.resumed && _started) SyncService.I.syncNow(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                const Text('Nie udało się uruchomić aplikacji', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SelectableText('Etap: ${AppDb.I.initStage}\n${snap.error}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => setState(() => _init = _start()), child: const Text('Spróbuj ponownie')),
              ]),
            ),
          );
        }
        return const HomeScreen();
      },
    );
  }
}

class ZniczApp extends StatelessWidget {
  const ZniczApp({super.key});

  ThemeData _theme(Brightness b) {
    final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      appBarTheme: AppBarTheme(backgroundColor: cs.surface, scrolledUnderElevation: 1, centerTitle: false),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      cardTheme: CardThemeData(elevation: 0, color: cs.surfaceContainerLow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Znicz',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const StartupGate(),
    );
  }
}
