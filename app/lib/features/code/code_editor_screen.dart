import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import 'syntax_highlighter.dart';

/// Code editor with syntax highlighting and the AI code assistant
/// (explain / fix / refactor / review / tests via POST /api/ai/code).
class CodeEditorScreen extends ConsumerStatefulWidget {
  const CodeEditorScreen({super.key});

  @override
  ConsumerState<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends ConsumerState<CodeEditorScreen> {
  late final CodeEditingController _code = CodeEditingController(language: _language);
  final _instruction = TextEditingController();
  String _language = 'javascript';
  bool _busy = false;

  static const _languages = ['javascript', 'typescript', 'dart', 'python', 'html', 'css', 'sql'];
  static const _actions = [
    (action: 'explain', label: 'Erklären', icon: Icons.psychology_outlined),
    (action: 'fix', label: 'Fixen', icon: Icons.build_outlined),
    (action: 'refactor', label: 'Refactor', icon: Icons.auto_fix_high_outlined),
    (action: 'review', label: 'Review', icon: Icons.rate_review_outlined),
    (action: 'test', label: 'Tests', icon: Icons.science_outlined),
    (action: 'generate', label: 'Generieren', icon: Icons.bolt_outlined),
  ];

  @override
  void dispose() {
    _code.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _run(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    String result;
    try {
      final res = await ref.read(apiClientProvider).post('/api/ai/code', {
        'action': action,
        'language': _language,
        'instruction': _instruction.text.trim().isEmpty
            ? 'Führe die Aktion auf dem Code aus.'
            : _instruction.text.trim(),
        if (_code.text.trim().isNotEmpty) 'code': _code.text,
      });
      result = res['result'] as String;
    } catch (e) {
      result = 'Fehler: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(NexusTokens.s5),
          child: SelectableText(result, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Code-Editor'),
        actions: [
          DropdownButton<String>(
            value: _language,
            underline: const SizedBox.shrink(),
            items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (l) => setState(() {
              _language = l!;
              _code.language = l;
            }),
          ),
          const SizedBox(width: NexusTokens.s4),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(NexusTokens.s4),
            child: TextField(
              controller: _code,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
              decoration: const InputDecoration(hintText: '// Code hier eingeben oder einfügen …'),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(NexusTokens.s4, 0, NexusTokens.s4, NexusTokens.s4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _instruction,
                decoration: const InputDecoration(
                  hintText: 'Optionale Anweisung (z. B. "In async/await umschreiben")',
                  isDense: true,
                ),
              ),
              const SizedBox(height: NexusTokens.s3),
              _busy
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(NexusTokens.s2),
                      child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    ))
                  : Wrap(
                      spacing: NexusTokens.s2,
                      runSpacing: NexusTokens.s2,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final a in _actions)
                          ActionChip(
                            avatar: Icon(a.icon, size: 18),
                            label: Text(a.label),
                            onPressed: () => _run(a.action),
                          ),
                      ],
                    ),
            ]),
          ),
        ),
      ]),
    );
  }
}
