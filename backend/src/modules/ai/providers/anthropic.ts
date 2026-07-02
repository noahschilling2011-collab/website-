import { config } from '../../../config/index.js';
import { AppError } from '../../../utils/errors.js';
import type { AiProvider, ChatRequest, ChatResult } from './types.js';
import { parseSseStream } from './sse.js';

const API_URL = 'https://api.anthropic.com/v1/messages';

function toAnthropicBody(req: ChatRequest, stream: boolean) {
  const system = req.messages.filter((m) => m.role === 'system').map((m) => m.content).join('\n');
  return {
    model: req.model ?? anthropicProvider.defaultModel,
    max_tokens: req.maxTokens ?? 4096,
    temperature: req.temperature,
    system: system || undefined,
    messages: req.messages
      .filter((m) => m.role !== 'system')
      .map((m) => ({ role: m.role, content: m.content })),
    stream,
  };
}

function headers() {
  if (!config.anthropicApiKey) throw AppError.badRequest('ANTHROPIC_API_KEY not configured', 'provider_unconfigured');
  return {
    'content-type': 'application/json',
    'x-api-key': config.anthropicApiKey,
    'anthropic-version': '2023-06-01',
  };
}

export const anthropicProvider: AiProvider = {
  name: 'anthropic',
  defaultModel: 'claude-sonnet-5',

  async complete(req: ChatRequest): Promise<ChatResult> {
    const res = await fetch(API_URL, { method: 'POST', headers: headers(), body: JSON.stringify(toAnthropicBody(req, false)) });
    if (!res.ok) throw new AppError(502, 'provider_error', `Anthropic: ${res.status} ${await res.text()}`);
    const data = await res.json() as {
      content: { type: string; text?: string }[];
      usage?: { input_tokens: number; output_tokens: number };
    };
    return {
      content: data.content.filter((b) => b.type === 'text').map((b) => b.text).join(''),
      tokensIn: data.usage?.input_tokens,
      tokensOut: data.usage?.output_tokens,
    };
  },

  async *stream(req: ChatRequest) {
    const res = await fetch(API_URL, { method: 'POST', headers: headers(), body: JSON.stringify(toAnthropicBody(req, true)) });
    if (!res.ok || !res.body) throw new AppError(502, 'provider_error', `Anthropic: ${res.status} ${await res.text()}`);
    let content = '';
    let tokensOut: number | undefined;
    for await (const event of parseSseStream(res.body)) {
      const data = JSON.parse(event) as {
        type: string;
        delta?: { type: string; text?: string };
        usage?: { output_tokens: number };
      };
      if (data.type === 'content_block_delta' && data.delta?.text) {
        content += data.delta.text;
        yield data.delta.text;
      }
      if (data.type === 'message_delta' && data.usage) tokensOut = data.usage.output_tokens;
    }
    return { content, tokensOut };
  },
};
