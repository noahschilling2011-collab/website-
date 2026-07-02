import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

class Task {
  const Task({required this.id, required this.title, required this.status, required this.priority, this.dueAt});

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        priority: (json['priority'] as num?)?.toInt() ?? 2,
        dueAt: json['due_at'] != null ? DateTime.tryParse(json['due_at'] as String) : null,
      );

  final String id;
  final String title;
  final String status;
  final int priority;
  final DateTime? dueAt;
}

/// ViewModel for tasks with an offline-first read path: cached list is
/// served immediately, then refreshed from the API; offline mutations
/// are queued and replayed on the next successful sync.
class TasksController extends AsyncNotifier<List<Task>> {
  static const _cacheKey = 'tasks';

  @override
  Future<List<Task>> build() async {
    final store = ref.read(localStoreProvider);
    final cached = store.getCache(_cacheKey);
    if (cached != null) {
      // Serve stale data instantly, refresh in the background.
      Future.microtask(refresh);
      return _parse(cached);
    }
    return _fetch();
  }

  List<Task> _parse(Map<String, dynamic> json) =>
      (json['tasks'] as List).cast<Map<String, dynamic>>().map(Task.fromJson).toList();

  Future<List<Task>> _fetch() async {
    final api = ref.read(apiClientProvider);
    final store = ref.read(localStoreProvider);
    await _replayQueue(api);
    final res = await api.get('/api/tasks');
    await store.putCache(_cacheKey, res);
    return _parse(res);
  }

  Future<void> refresh() async {
    state = AsyncData(await _fetch());
  }

  Future<void> _replayQueue(ApiClient api) async {
    final store = ref.read(localStoreProvider);
    for (final m in store.pendingMutations) {
      final method = m['method'] as String;
      final path = m['path'] as String;
      final body = (m['body'] as Map?)?.cast<String, dynamic>();
      if (method == 'POST') await api.post(path, body);
      if (method == 'PATCH') await api.patch(path, body);
      if (method == 'DELETE') await api.delete(path);
    }
    await store.clearMutations();
  }

  Future<void> _mutate(String method, String path, Map<String, dynamic>? body) async {
    final api = ref.read(apiClientProvider);
    try {
      if (method == 'POST') await api.post(path, body);
      if (method == 'PATCH') await api.patch(path, body);
      if (method == 'DELETE') await api.delete(path);
      await refresh();
    } on Object {
      // Offline or server down: queue for later replay.
      await ref.read(localStoreProvider).enqueueMutation(method: method, path: path, body: body);
    }
  }

  Future<void> add(String title) => _mutate('POST', '/api/tasks', {'title': title});

  Future<void> toggle(Task task) => _mutate('PATCH', '/api/tasks/${task.id}',
      {'status': task.status == 'done' ? 'open' : 'done'});

  Future<void> remove(Task task) => _mutate('DELETE', '/api/tasks/${task.id}', null);
}

final tasksControllerProvider = AsyncNotifierProvider<TasksController, List<Task>>(TasksController.new);
