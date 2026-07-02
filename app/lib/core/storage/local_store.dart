import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Offline layer: caches server responses per key and queues mutations
/// made while offline. On reconnect the queue is replayed in order.
class LocalStore {
  LocalStore(this._prefs);

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _cachePrefix = 'cache:';
  static const _queueKey = 'sync_queue';
  static const _tokenKey = 'auth_tokens';

  // ---------- Response cache ----------

  Future<void> putCache(String key, Map<String, dynamic> value) =>
      _prefs.setString('$_cachePrefix$key', jsonEncode(value));

  Map<String, dynamic>? getCache(String key) {
    final raw = _prefs.getString('$_cachePrefix$key');
    if (raw == null) return null;
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  // ---------- Offline mutation queue ----------

  List<Map<String, dynamic>> get pendingMutations {
    final raw = _prefs.getString(_queueKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> enqueueMutation({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final queue = [...pendingMutations, {'method': method, 'path': path, 'body': body}];
    await _prefs.setString(_queueKey, jsonEncode(queue));
  }

  Future<void> clearMutations() => _prefs.remove(_queueKey);

  // ---------- Auth tokens ----------
  // On mobile, prefer flutter_secure_storage; SharedPreferences keeps the
  // web build working without extra platform setup.

  Future<void> saveTokens({required String access, required String refresh}) =>
      _prefs.setString(_tokenKey, jsonEncode({'access': access, 'refresh': refresh}));

  ({String access, String refresh})? get tokens {
    final raw = _prefs.getString(_tokenKey);
    if (raw == null) return null;
    final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return (access: map['access'] as String, refresh: map['refresh'] as String);
  }

  Future<void> clearTokens() => _prefs.remove(_tokenKey);
}
