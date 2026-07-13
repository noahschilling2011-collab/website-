import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'network/api_client.dart';
import 'storage/local_store.dart';

/// Overridden in main() with the opened instance.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(localStoreProvider);
  late final ApiClient client;
  client = ApiClient(
    baseUrl: ApiClient.defaultBaseUrl,
    onUnauthorized: () async {
      // Refresh-token rotation: exchange the stored refresh token for a
      // new pair; on failure the session is dead and the caller signs out.
      final refresh = store.tokens?.refresh;
      if (refresh == null) return null;
      final res = await http.post(
        Uri.parse('${ApiClient.defaultBaseUrl}/api/auth/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );
      if (res.statusCode >= 400) {
        await store.clearTokens();
        return null;
      }
      final tokens = ((jsonDecode(res.body) as Map)['tokens'] as Map).cast<String, dynamic>();
      await store.saveTokens(
        access: tokens['accessToken'] as String,
        refresh: tokens['refreshToken'] as String,
      );
      return tokens['accessToken'] as String;
    },
  );
  client.accessToken = store.tokens?.access;
  return client;
});

/// App-wide theme mode, persisted per device.
final themeModeProvider = StateProvider<bool?>((ref) => null); // null = system
