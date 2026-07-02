import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';

class Note {
  const Note({required this.id, required this.title, required this.content, required this.pinned});

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        pinned: json['pinned'] as bool? ?? false,
      );

  final String id;
  final String title;
  final String content;
  final bool pinned;
}

final notesProvider = FutureProvider<List<Note>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/api/notes');
  return (res['notes'] as List).cast<Map<String, dynamic>>().map(Note.fromJson).toList();
});

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, {Note? note}) async {
    final title = TextEditingController(text: note?.title);
    final content = TextEditingController(text: note?.content);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? 'Neue Notiz' : 'Notiz bearbeiten'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Titel')),
            const SizedBox(height: NexusTokens.s3),
            TextField(
              controller: content,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Inhalt (Markdown)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (saved != true) return;
    final api = ref.read(apiClientProvider);
    final body = {'title': title.text, 'content': content.text};
    if (note == null) {
      await api.post('/api/notes', body);
    } else {
      await api.patch('/api/notes/${note.id}', body);
    }
    ref.invalidate(notesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(notesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notizen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Notiz'),
      ),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) => items.isEmpty
            ? const Center(child: Text('Noch keine Notizen'))
            : GridView.builder(
                padding: const EdgeInsets.all(NexusTokens.s4),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: NexusTokens.s3,
                  crossAxisSpacing: NexusTokens.s3,
                  childAspectRatio: 1.1,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final note = items[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _edit(context, ref, note: note),
                      onLongPress: () async {
                        await ref.read(apiClientProvider).delete('/api/notes/${note.id}');
                        ref.invalidate(notesProvider);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(NexusTokens.s4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                note.title.isEmpty ? 'Ohne Titel' : note.title,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (note.pinned) const Icon(Icons.push_pin, size: 16),
                          ]),
                          const SizedBox(height: NexusTokens.s2),
                          Expanded(
                            child: Text(
                              note.content,
                              maxLines: 6,
                              overflow: TextOverflow.fade,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
