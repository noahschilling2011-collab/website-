import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _totp = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;

  late final AnimationController _intro = AnimationController(vsync: this, duration: NexusTokens.slow)..forward();

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    _totp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final auth = ref.read(authControllerProvider.notifier);
    final current = ref.read(authControllerProvider);
    if (current is TotpRequired) {
      await auth.login(current.email, current.password, totpCode: _totp.text.trim());
    } else if (_registerMode) {
      await auth.register(_email.text.trim(), _password.text, _displayName.text.trim());
    } else {
      await auth.login(_email.text.trim(), _password.text);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final totpMode = state is TotpRequired;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NexusTokens.s5),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _intro, curve: NexusTokens.easeOutExpo),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _intro, curve: NexusTokens.easeOutExpo)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.auto_awesome, size: 56, color: scheme.primary),
                    const SizedBox(height: NexusTokens.s4),
                    Text('Nexus AI',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      totpMode ? 'Zwei-Faktor-Code eingeben' : 'Deine KI-Produktivitätszentrale',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: NexusTokens.s6),
                    if (totpMode)
                      TextField(
                        controller: _totp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(labelText: '6-stelliger Code', counterText: ''),
                      )
                    else ...[
                      if (_registerMode) ...[
                        TextField(controller: _displayName, decoration: const InputDecoration(labelText: 'Name')),
                        const SizedBox(height: NexusTokens.s3),
                      ],
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-Mail'),
                      ),
                      const SizedBox(height: NexusTokens.s3),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Passwort'),
                      ),
                    ],
                    if (state is SignedOut && state.error != null) ...[
                      const SizedBox(height: NexusTokens.s3),
                      Text(state.error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: NexusTokens.s4),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(totpMode
                              ? 'Bestätigen'
                              : _registerMode
                                  ? 'Konto erstellen'
                                  : 'Anmelden'),
                    ),
                    const SizedBox(height: NexusTokens.s2),
                    if (!totpMode)
                      TextButton(
                        onPressed: () => setState(() => _registerMode = !_registerMode),
                        child: Text(_registerMode ? 'Ich habe bereits ein Konto' : 'Neues Konto erstellen'),
                      ),
                    TextButton.icon(
                      onPressed: () => ref.read(authControllerProvider.notifier).unlockWithBiometrics(),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Mit Biometrie entsperren'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
