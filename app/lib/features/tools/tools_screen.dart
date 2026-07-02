import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';

/// Hub for the AI tools: summaries, translation, document writer,
/// presentations, mindmaps and media generation. Each tool posts to its
/// backend endpoint and shows the result in a shared result sheet.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = <_Tool>[
      _Tool('Webseite zusammenfassen', Icons.language, _promptKind.url, '/api/ai/summarize/url', 'summary'),
      _Tool('YouTube analysieren', Icons.play_circle_outline, _promptKind.url, '/api/ai/summarize/youtube', 'summary'),
      _Tool('Text/PDF zusammenfassen', Icons.description_outlined, _promptKind.longText, '/api/ai/summarize/text', 'summary'),
      _Tool('Übersetzen', Icons.translate, _promptKind.translate, '/api/ai/translate', 'translation'),
      _Tool('Dokument schreiben', Icons.edit_note, _promptKind.document, '/api/ai/documents/write', 'document'),
      _Tool('Präsentation erstellen', Icons.co_present_outlined, _promptKind.topic, '/api/ai/presentations', 'presentation'),
      _Tool('Mindmap generieren', Icons.account_tree_outlined, _promptKind.topic, '/api/ai/mindmaps', 'mindmap'),
      _Tool('Bild generieren', Icons.image_outlined, _promptKind.media, '/api/ai/media/image', 'job'),
      _Tool('Video generieren', Icons.movie_outlined, _promptKind.media, '/api/ai/media/video', 'job'),
      _Tool('Musik generieren', Icons.music_note_outlined, _promptKind.media, '/api/ai/media/music', 'job'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('KI-Werkzeuge')),
      body: GridView.builder(
        padding: const EdgeInsets.all(NexusTokens.s4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: NexusTokens.s3,
          crossAxisSpacing: NexusTokens.s3,
          childAspectRatio: 1.4,
        ),
        itemCount: tools.length,
        itemBuilder: (context, i) => _ToolCard(tool: tools[i]),
      ),
    );
  }
}

enum _promptKind { url, longText, translate, document, topic, media }

class _Tool {
  const _Tool(this.title, this.icon, this.kind, this.endpoint, this.resultKey);
  final String title;
  final IconData icon;
  final _promptKind kind;
  final String endpoint;
  final String resultKey;
}

class _ToolCard extends ConsumerWidget {
  const _ToolCard({required this.tool});

  final _Tool tool;

  Future<void> _run(BuildContext context, WidgetRef ref) async {
    final input = TextEditingController();
    final extra = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tool.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: input,
            autofocus: true,
            minLines: tool.kind == _promptKind.longText ? 4 : 1,
            maxLines: tool.kind == _promptKind.longText ? 10 : 3,
            decoration: InputDecoration(
              labelText: switch (tool.kind) {
                _promptKind.url => 'URL',
                _promptKind.longText => 'Text einfügen',
                _promptKind.translate => 'Text',
                _promptKind.document => 'Thema / Auftrag',
                _promptKind.topic => 'Thema',
                _promptKind.media => 'Prompt',
              },
            ),
          ),
          if (tool.kind == _promptKind.translate) ...[
            const SizedBox(height: NexusTokens.s3),
            TextField(controller: extra, decoration: const InputDecoration(labelText: 'Zielsprache (z. B. Englisch)')),
          ],
          if (tool.kind == _promptKind.document) ...[
            const SizedBox(height: NexusTokens.s3),
            TextField(controller: extra, decoration: const InputDecoration(labelText: 'Art (z. B. Bericht, E-Mail)')),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Los')),
        ],
      ),
    );
    if (confirmed != true || input.text.trim().isEmpty || !context.mounted) return;

    final body = switch (tool.kind) {
      _promptKind.url => {'url': input.text.trim()},
      _promptKind.longText => {'text': input.text},
      _promptKind.translate => {'text': input.text, 'targetLanguage': extra.text.trim()},
      _promptKind.document => {'topic': input.text, 'kind': extra.text.trim().isEmpty ? 'Dokument' : extra.text.trim()},
      _promptKind.topic => {'topic': input.text},
      _promptKind.media => {'prompt': input.text},
    };

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String result;
    try {
      final res = await ref.read(apiClientProvider).post(tool.endpoint, body);
      final value = res[tool.resultKey];
      result = value is String ? value : value.toString();
    } catch (e) {
      result = 'Fehler: $e';
    }
    if (!context.mounted) return;
    Navigator.pop(context); // close spinner
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(NexusTokens.s5),
          child: SelectableText(result),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _run(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(NexusTokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(tool.icon, color: scheme.primary, size: 28),
              Text(tool.title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
