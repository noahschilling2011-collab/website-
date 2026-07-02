import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _providers = {
    'anthropic': 'Claude',
    'openai': 'GPT',
    'gemini': 'Gemini',
  };

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    ref.read(chatControllerProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    // Follow the stream to the bottom.
    ref.listen(chatControllerProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: NexusTokens.fast, curve: Curves.easeOut);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-Chat'),
        actions: [
          PopupMenuButton<String>(
            initialValue: state.provider,
            onSelected: (p) => ref.read(chatControllerProvider.notifier).setProvider(p),
            itemBuilder: (_) => _providers.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexusTokens.s4),
              child: Row(children: [
                Text(_providers[state.provider] ?? state.provider),
                const Icon(Icons.arrow_drop_down),
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Neue Unterhaltung',
            onPressed: () => ref.read(chatControllerProvider.notifier).newConversation(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.auto_awesome, size: 48, color: scheme.primary),
                      const SizedBox(height: NexusTokens.s3),
                      Text('Frag mich alles — ${_providers[state.provider]} antwortet.',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ]),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(NexusTokens.s4),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) => _MessageBubble(message: state.messages[i]),
                  ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(NexusTokens.s2),
              child: Text(state.error!, style: TextStyle(color: scheme.error)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(NexusTokens.s4, 0, NexusTokens.s4, NexusTokens.s4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: 'Nachricht an Nexus AI …'),
                  ),
                ),
                const SizedBox(width: NexusTokens.s2),
                AnimatedSwitcher(
                  duration: NexusTokens.fast,
                  child: state.streaming
                      ? const Padding(
                          padding: EdgeInsets.all(NexusTokens.s3),
                          child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton.filled(icon: const Icon(Icons.arrow_upward), onPressed: _send),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: NexusTokens.normal,
      curve: NexusTokens.easeOutExpo,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
      ),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: NexusTokens.s3),
          padding: const EdgeInsets.symmetric(horizontal: NexusTokens.s4, vertical: NexusTokens.s3),
          constraints: const BoxConstraints(maxWidth: 640),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(NexusTokens.radiusL),
              topRight: const Radius.circular(NexusTokens.radiusL),
              bottomLeft: Radius.circular(isUser ? NexusTokens.radiusL : NexusTokens.radiusS),
              bottomRight: Radius.circular(isUser ? NexusTokens.radiusS : NexusTokens.radiusL),
            ),
          ),
          child: SelectableText(
            message.content.isEmpty ? '…' : message.content,
            style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
