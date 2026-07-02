import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

sealed class AuthState {
  const AuthState();
}

class SignedOut extends AuthState {
  const SignedOut({this.error});
  final String? error;
}

class TotpRequired extends AuthState {
  const TotpRequired({required this.email, required this.password});
  final String email;
  final String password;
}

class SignedIn extends AuthState {
  const SignedIn({required this.displayName, required this.email});
  final String displayName;
  final String email;
}

/// ViewModel (MVVM) for the auth flow: login, register, 2FA and
/// biometric quick unlock of a stored session.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final tokens = ref.read(localStoreProvider).tokens;
    return tokens != null ? const SignedIn(displayName: '', email: '') : const SignedOut();
  }

  ApiClient get _api => ref.read(apiClientProvider);

  Future<void> login(String email, String password, {String? totpCode}) async {
    try {
      final res = await _api.post('/api/auth/login', {
        'email': email,
        'password': password,
        if (totpCode != null) 'totpCode': totpCode,
      });
      if (res['requiresTotp'] == true) {
        state = TotpRequired(email: email, password: password);
        return;
      }
      await _storeTokens(res['tokens'] as Map<String, dynamic>);
      state = SignedIn(displayName: '', email: email);
    } on ApiException catch (e) {
      state = SignedOut(error: e.message);
    }
  }

  Future<void> register(String email, String password, String displayName) async {
    try {
      final res = await _api.post('/api/auth/register', {
        'email': email,
        'password': password,
        'displayName': displayName,
      });
      await _storeTokens(res['tokens'] as Map<String, dynamic>);
      state = SignedIn(displayName: displayName, email: email);
    } on ApiException catch (e) {
      state = SignedOut(error: e.message);
    }
  }

  /// Biometric unlock: only re-activates an existing stored session.
  Future<bool> unlockWithBiometrics() async {
    final store = ref.read(localStoreProvider);
    if (store.tokens == null) return false;
    final auth = LocalAuthentication();
    if (!await auth.isDeviceSupported()) return true; // web/desktop: skip
    final ok = await auth.authenticate(
      localizedReason: 'Nexus AI entsperren',
      options: const AuthenticationOptions(stickyAuth: true),
    );
    if (ok) state = const SignedIn(displayName: '', email: '');
    return ok;
  }

  Future<void> logout() async {
    final store = ref.read(localStoreProvider);
    final refresh = store.tokens?.refresh;
    if (refresh != null) {
      try {
        await _api.post('/api/auth/logout', {'refreshToken': refresh});
      } on ApiException {
        // Session is cleared locally regardless.
      }
    }
    await store.clearTokens();
    ref.invalidate(apiClientProvider);
    state = const SignedOut();
  }

  Future<void> _storeTokens(Map<String, dynamic> tokens) async {
    await ref.read(localStoreProvider).saveTokens(
          access: tokens['accessToken'] as String,
          refresh: tokens['refreshToken'] as String,
        );
    ref.invalidate(apiClientProvider);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
