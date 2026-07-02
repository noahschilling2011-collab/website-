import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/local_store.dart';

/// Overridden in main() with the opened instance.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(baseUrl: ApiClient.defaultBaseUrl);
  final tokens = ref.watch(localStoreProvider).tokens;
  client.accessToken = tokens?.access;
  return client;
});

/// App-wide theme mode, persisted per device.
final themeModeProvider = StateProvider<bool?>((ref) => null); // null = system
