import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import 'tasks_controller.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  Future<void> _addTask(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: NexusTokens.s4,
          right: NexusTokens.s4,
          bottom: MediaQuery.of(context).viewInsets.bottom + NexusTokens.s4,
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Neue Aufgabe …'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ),
          const SizedBox(width: NexusTokens.s2),
          IconButton.filled(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, controller.text),
          ),
        ]),
      ),
    );
    if (title != null && title.trim().isNotEmpty) {
      await ref.read(tasksControllerProvider.notifier).add(title.trim());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Aufgaben')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTask(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Aufgabe'),
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorRetry(message: '$e', onRetry: () => ref.invalidate(tasksControllerProvider)),
        data: (items) => items.isEmpty
            ? const Center(child: Text('Alles erledigt 🎉'))
            : RefreshIndicator(
                onRefresh: () => ref.read(tasksControllerProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final task = items[i];
                    final done = task.status == 'done';
                    return Dismissible(
                      key: ValueKey(task.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: NexusTokens.s5),
                        child: const Icon(Icons.delete_outline),
                      ),
                      onDismissed: (_) => ref.read(tasksControllerProvider.notifier).remove(task),
                      child: CheckboxListTile(
                        value: done,
                        onChanged: (_) => ref.read(tasksControllerProvider.notifier).toggle(task),
                        title: AnimatedDefaultTextStyle(
                          duration: NexusTokens.fast,
                          style: TextStyle(
                            color: done
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : Theme.of(context).colorScheme.onSurface,
                            decoration: done ? TextDecoration.lineThrough : TextDecoration.none,
                          ),
                          child: Text(task.title),
                        ),
                        subtitle: task.dueAt != null
                            ? Text(DateFormat.yMMMd().format(task.dueAt!))
                            : null,
                        secondary: task.priority >= 3
                            ? const Icon(Icons.priority_high, color: NexusTokens.warning)
                            : null,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: NexusTokens.s3),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Erneut versuchen')),
      ]),
    );
  }
}
