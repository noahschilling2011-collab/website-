import { query, queryOne } from '../../db/pool.js';
import { AppError } from '../../utils/errors.js';
import { getProvider, type ChatMessage } from './providers/index.js';

export interface ConversationRow {
  id: string;
  user_id: string;
  title: string;
  provider: string;
  model: string | null;
  created_at: string;
  updated_at: string;
}

export async function listConversations(userId: string): Promise<ConversationRow[]> {
  return query<ConversationRow>(
    'SELECT * FROM conversations WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 100',
    [userId],
  );
}

export async function createConversation(
  userId: string,
  input: { title?: string; provider?: string; model?: string },
): Promise<ConversationRow> {
  if (input.provider) getProvider(input.provider); // validate early
  const row = await queryOne<ConversationRow>(
    `INSERT INTO conversations (user_id, title, provider, model)
     VALUES ($1, $2, COALESCE($3, 'anthropic'), $4) RETURNING *`,
    [userId, input.title ?? 'Neue Unterhaltung', input.provider ?? null, input.model ?? null],
  );
  return row!;
}

export async function getConversation(userId: string, id: string): Promise<ConversationRow> {
  const row = await queryOne<ConversationRow>(
    'SELECT * FROM conversations WHERE id = $1 AND user_id = $2',
    [id, userId],
  );
  if (!row) throw AppError.notFound('Conversation not found');
  return row;
}

export async function getHistory(conversationId: string): Promise<ChatMessage[]> {
  const rows = await query<{ role: ChatMessage['role']; content: string }>(
    'SELECT role, content FROM messages WHERE conversation_id = $1 ORDER BY created_at',
    [conversationId],
  );
  return rows;
}

export async function appendMessage(
  conversationId: string,
  role: ChatMessage['role'],
  content: string,
  tokens?: { in?: number; out?: number },
): Promise<void> {
  await query(
    `INSERT INTO messages (conversation_id, role, content, tokens_in, tokens_out)
     VALUES ($1, $2, $3, $4, $5)`,
    [conversationId, role, content, tokens?.in ?? null, tokens?.out ?? null],
  );
  await query('UPDATE conversations SET updated_at = now() WHERE id = $1', [conversationId]);
}

/**
 * Streams an assistant reply for a conversation. Persists the user message
 * first and the full assistant message after the stream completes.
 */
export async function* streamReply(
  userId: string,
  conversationId: string,
  userMessage: string,
): AsyncGenerator<string> {
  const conversation = await getConversation(userId, conversationId);
  await appendMessage(conversationId, 'user', userMessage);

  const history = await getHistory(conversationId);
  const provider = getProvider(conversation.provider);
  const generator = provider.stream({
    model: conversation.model ?? undefined,
    messages: [
      { role: 'system', content: 'You are Nexus AI, a helpful productivity assistant. Answer in the language of the user.' },
      ...history,
    ],
  });

  let full = '';
  let result: IteratorResult<string, { content: string; tokensOut?: number }>;
  while (!(result = await generator.next()).done) {
    full += result.value;
    yield result.value;
  }
  await appendMessage(conversationId, 'assistant', full, { out: result.value.tokensOut });
}
