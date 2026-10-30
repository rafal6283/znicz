import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import '../sync/family_crypto.dart';
import '../sync/sync_service.dart';
import 'common.dart';

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});
  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  bool _selfSigned = false;
  bool _showPass = false;
  bool _busy = false;
  String? _msg;
  bool _ok = false;
  String _origUrl = '';
  String _key = ''; // klucz szyfrowania rodziny

  @override
  void initState() {
    super.initState();
    SyncConfig.load().then((c) {
      if (!mounted) return;
      setState(() {
        _url.text = c.url;
        _origUrl = c.url;
        _user.text = c.user;
        _pass.text = c.password;
        _name.text = c.myName;
        _selfSigned = c.allowSelfSigned;
        _key = c.familyKey;
      });
    });
  }

  @override
  void dispose() {
    for (final c in [_url, _user, _pass, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  SyncConfig get _cfg => SyncConfig(
      url: _url.text.trim(), user: _user.text.trim(), password: _pass.text, allowSelfSigned: _selfSigned, myName: _name.text.trim(), familyKey: _key);

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final err = await SyncService.test(_cfg);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = err == null;
      _msg = err ?? 'Połączenie działa, foldery są gotowe.';
    });
  }

  Future<void> _saveAndSync() async {
    if (_url.text.trim().isEmpty) {
      snack(context, 'Podaj adres serwera');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final err0 = await SyncService.test(_cfg);
    if (err0 != null) {
      setState(() {
        _busy = false;
        _ok = false;
        _msg = err0;
      });
      return;
    }
    // inny serwer = zacznij od zera (wszystko zostanie wysłane i pobrane)
    if (_url.text.trim() != _origUrl) await AppDb.I.clearSyncState();
    await _cfg.save();
    _origUrl = _url.text.trim();
    final err = await SyncService.I.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = err == null;
      _msg = err ?? 'Zsynchronizowano: ${SyncService.I.lastResult ?? ''}';
    });
  }

  Future<void> _invite() async {
    if (_url.text.trim().isEmpty) return;
    await _cfg.save();
    final code = _cfg.inviteCode();
    await SharePlus.instance.share(ShareParams(
      text: 'Wspólne groby rodziny w aplikacji Znicz.\n'
          'Otwórz Znicz → Więcej → Synchronizacja rodzinna → „Mam kod zaproszenia” i wklej:\n\n$code',
      subject: 'Znicz – kod rodzinny',
    ));
  }

  /// Generuje klucz rodziny, szyfruje dane na serwerze i proponuje wysłanie nowego kodu.
  Future<void> _enableEncryption() async {
    if (!await confirm(
        context,
        'Włączyć szyfrowanie?',
        'Dane na serwerze zostaną zaszyfrowane. Pozostałe osoby muszą zaktualizować Znicza i wkleić nowy kod '
            'zaproszenia — do tego czasu ich synchronizacja pokaże komunikat o kluczu.',
        ok: 'Włącz')) {
      return;
    }
    setState(() {
      _key = FamilyCrypto.newKey();
      _busy = true;
    });
    await _cfg.save();
    // wszystko zostanie wysłane ponownie — już zaszyfrowane
    await AppDb.I.clearSyncState();
    final err = await SyncService.I.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = err == null;
      _msg = err ?? 'Szyfrowanie włączone. Wyślij rodzinie nowy kod zaproszenia.';
    });
    if (err == null) await _invite();
  }

  Future<void> _pasteInvite() async {
    final clip = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final c = TextEditingController(text: (clip?.text ?? '').contains('ZNICZ1-') ? clip!.text : '');
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Kod zaproszenia'),
        content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'ZNICZ1-…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Użyj')),
        ],
      ),
    );
    if (code == null) return;
    final cfg = SyncConfig.fromInvite(code);
    if (cfg == null) {
      if (mounted) snack(context, 'To nie jest poprawny kod zaproszenia');
      return;
    }
    setState(() {
      _url.text = cfg.url;
      _user.text = cfg.user;
      _pass.text = cfg.password;
      _selfSigned = cfg.allowSelfSigned;
      if (cfg.familyKey.isNotEmpty) _key = cfg.familyKey;
    });
    if (mounted && _name.text.trim().isEmpty) snack(context, 'Wpisz jeszcze swoje imię i zapisz');
  }

  Future<void> _disable() async {
    if (!await confirm(context, 'Wyłączyć synchronizację?', 'Dane na tym telefonie zostaną. Na serwerze też nic nie zniknie.', ok: 'Wyłącz')) return;
    final c = _cfg
      ..url = ''
      ..password = '';
    await c.save();
    await AppDb.I.clearSyncState();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronizacja rodzinna')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          'Wszyscy w rodzinie widzą te same groby, zdjęcia i wizyty. Dane leżą na Twoim serwerze (NAS) albo w darmowej chmurze z WebDAV – nie u nas. '
          'Po włączeniu szyfrowania serwer widzi tylko zaszyfrowane pliki.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pasteInvite, icon: const Icon(Icons.vpn_key_outlined), label: const Text('Mam kod zaproszenia')),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Adres folderu WebDAV', hintText: 'https://mojnas.synology.me:5006/znicz'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _user, autocorrect: false, decoration: const InputDecoration(labelText: 'Użytkownik')),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: !_showPass,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Hasło',
            suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Certyfikat z własnym podpisem'),
          subtitle: const Text('Włącz, jeśli NAS nie ma certyfikatu Let’s Encrypt'),
          value: _selfSigned,
          onChanged: (v) => setState(() => _selfSigned = v),
        ),
        const SizedBox(height: 4),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Twoje imię', helperText: 'Widoczne przy wizytach, np. „odwiedził(a): Rafał”')),
        const SizedBox(height: 16),
        if (_msg != null)
          Card(
            color: _ok ? cs.secondaryContainer : cs.errorContainer,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_msg!, style: TextStyle(color: _ok ? cs.onSecondaryContainer : cs.onErrorContainer))),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Sprawdź'))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _busy ? null : _saveAndSync,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Zapisz i synchronizuj'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_origUrl.isNotEmpty) ...[
          FilledButton.tonalIcon(onPressed: _invite, icon: const Icon(Icons.group_add_outlined), label: const Text('Zaproś rodzinę (wyślij kod)')),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Kod zawiera login i hasło – wysyłaj go tylko bliskim.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(_key.isEmpty ? Icons.lock_open : Icons.lock, color: _key.isEmpty ? cs.error : cs.primary),
              title: Text(_key.isEmpty ? 'Dane na serwerze nie są szyfrowane' : 'Dane rodziny są szyfrowane'),
              subtitle: Text(_key.isEmpty
                  ? 'Włącz szyfrowanie — potem wyślij rodzinie nowy kod zaproszenia (zawiera klucz). '
                      'Wszyscy muszą mieć najnowszą wersję Znicza.'
                  : 'Klucz jest w kodzie zaproszenia — bez niego nikt nie odczyta grobów ani zdjęć na serwerze.'),
              trailing: _key.isEmpty ? FilledButton(onPressed: _busy ? null : _enableEncryption, child: const Text('Włącz')) : null,
            ),
          ),
          TextButton(onPressed: _disable, child: const Text('Wyłącz synchronizację')),
        ],
        const SizedBox(height: 16),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Jak to ustawić na Synology?'),
          childrenPadding: EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Centrum pakietów → zainstaluj „WebDAV Server”, włącz HTTPS (port 5006).\n'
                '2. Panel sterowania → Folder udostępniony → utwórz „znicz”.\n'
                '3. Panel sterowania → Użytkownik → utwórz np. „rodzina” z prawem odczytu i zapisu tylko do folderu „znicz” (i aplikacją WebDAV).\n'
                '4. Dostęp spoza domu: DDNS (np. nazwa.synology.me) + przekierowanie portu 5006 na routerze i certyfikat Let’s Encrypt. '
                'Albo Tailscale na NAS-ie i telefonach – wtedy bez otwierania portów. QuickConnect nie obsługuje WebDAV.\n'
                '5. Adres w aplikacji: https://nazwa.synology.me:5006/znicz\n'
                '6. „Zaproś rodzinę” – wyślij kod pozostałym.'),
          ],
        ),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Bez NAS-a – darmowa chmura'),
          childrenPadding: EdgeInsets.only(bottom: 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Każda usługa z WebDAV zadziała, np. Koofr (10 GB za darmo, serwery w UE):\n'
                '1. Załóż konto na koofr.eu i utwórz folder „znicz”.\n'
                '2. Ustawienia → Hasła → wygeneruj hasło aplikacji.\n'
                '3. Adres: https://app.koofr.net/dav/Koofr/znicz, użytkownik: e-mail konta, hasło: hasło aplikacji.\n'
                'Działa też Nextcloud, ownCloud i inne serwery WebDAV.'),
          ],
        ),
      ]),
    );
  }
}
