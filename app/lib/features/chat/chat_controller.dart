import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role;
  final String content;
}

class ChatState {
  const ChatState({
    this.conversationId,
    this.provider = 'anthropic',
    this.messages = const [],
    this.streaming = false,
    this.error,
  });

  final String? conversationId;
  final String provider;
  final List<ChatMessage> messages;
  final bool streaming;
  final String? error;

  ChatState copyWith({
    String? conversationId,
    String? provider,
    List<ChatMessage>? messages,
    bool? streaming,
    String? error,
  }) =>
      ChatState(
        conversationId: conversationId ?? this.conversationId,
        provider: provider ?? this.provider,
        messages: messages ?? this.messages,
        streaming: streaming ?? this.streaming,
        error: error,
      );
}

/// ViewModel for the AI chat: creates a conversation lazily on first send
/// and appends streamed deltas token by token.
class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  void setProvider(String provider) {
    // Provider is fixed per conversation; switching starts a new one.
    state = ChatState(provider: provider);
  }

  Future<void> send(String content) async {
    if (state.streaming || content.trim().isEmpty) return;
    final api = ref.read(apiClientProvider);
    state = state.copyWith(error: null);

    try {
      var conversationId = state.conversationId;
      if (conversationId == null) {
        final res = await api.post('/api/ai/conversations', {'provider': state.provider});
        conversationId = (res['conversation'] as Map)['id'] as String;
        state = state.copyWith(conversationId: conversationId);
        ref.invalidate(conversationsProvider);
      }

      state = state.copyWith(
        messages: [...state.messages, ChatMessage(role: 'user', content: content), const ChatMessage(role: 'assistant', content: '')],
        streaming: true,
      );

      await for (final raw in api.postSse('/api/ai/conversations/$conversationId/messages', {'content': content})) {
        final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
        if (data['error'] != null) {
          state = state.copyWith(streaming: false, error: data['error'] as String);
          return;
        }
        final delta = data['delta'] as String? ?? '';
        final messages = [...state.messages];
        final last = messages.removeLast();
        messages.add(ChatMessage(role: 'assistant', content: last.content + delta));
        state = state.copyWith(messages: messages);
      }
      state = state.copyWith(streaming: false);
    } catch (e) {
      state = state.copyWith(streaming: false, error: e.toString());
    }
  }

  void newConversation() => state = ChatState(provider: state.provider);

  /// Opens an existing conversation from the history list.
  Future<void> loadConversation(String id, String provider) async {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/api/ai/conversations/$id/messages');
    final messages = (res['messages'] as List)
        .cast<Map<String, dynamic>>()
        .map((m) => ChatMessage(role: m['role'] as String, content: m['content'] as String))
        .toList();
    state = ChatState(conversationId: id, provider: provider, messages: messages);
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ConversationSummary {
  const ConversationSummary({required this.id, required this.title, required this.provider});

  final String id;
  final String title;
  final String provider;
}

/// History list for the chat drawer.
final conversationsProvider = FutureProvider<List<ConversationSummary>>((ref) async {
  final res = await ref.watch(apiClientProvider).get('/api/ai/conversations');
  return (res['conversations'] as List).cast<Map<String, dynamic>>().map((c) =>
      ConversationSummary(
        id: c['id'] as String,
        title: c['title'] as String,
        provider: c['provider'] as String,
      )).toList();
});
