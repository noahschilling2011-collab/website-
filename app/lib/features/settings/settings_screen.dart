import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../auth/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _enable2fa(BuildContext context, WidgetRef ref) async {
    final api = ref.read(apiClientProvider);
    final setup = await api.post('/api/auth/totp/setup');
    if (!context.mounted) return;
    final code = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('2FA aktivieren'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Secret in deiner Authenticator-App hinzufügen:'),
          const SizedBox(height: NexusTokens.s2),
          SelectableText(setup['secret'] as String,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          const SizedBox(height: NexusTokens.s4),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(labelText: 'Code zur Bestätigung', counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aktivieren')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await api.post('/api/auth/totp/enable', {'code': code.text.trim()});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('2FA ist aktiv ✅')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final darkMode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(children: [
        const _SectionHeader('Darstellung'),
        RadioListTile<bool?>(
          value: null,
          groupValue: darkMode,
          onChanged: (v) => ref.read(themeModeProvider.notifier).state = v,
          title: const Text('System'),
        ),
        RadioListTile<bool?>(
          value: false,
          groupValue: darkMode,
          onChanged: (v) => ref.read(themeModeProvider.notifier).state = v,
          title: const Text('Hell'),
        ),
        RadioListTile<bool?>(
          value: true,
          groupValue: darkMode,
          onChanged: (v) => ref.read(themeModeProvider.notifier).state = v,
          title: const Text('Dunkel'),
        ),
        const Divider(),
        const _SectionHeader('Sicherheit'),
        ListTile(
          leading: const Icon(Icons.security),
          title: const Text('Zwei-Faktor-Authentifizierung'),
          subtitle: const Text('TOTP mit Authenticator-App'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _enable2fa(context, ref),
        ),
        const ListTile(
          leading: Icon(Icons.fingerprint),
          title: Text('Biometrischer Login'),
          subtitle: Text('Beim App-Start verfügbar (Face ID / Fingerabdruck)'),
        ),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Ende-zu-Ende-Verschlüsselung'),
          subtitle: Text('Notizen können clientseitig verschlüsselt gespeichert werden'),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: Text('Abmelden', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => ref.read(authControllerProvider.notifier).logout(),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(NexusTokens.s4, NexusTokens.s4, NexusTokens.s4, NexusTokens.s1),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
