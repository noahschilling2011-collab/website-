import { config } from '../../../config/index.js';
import { AppError } from '../../../utils/errors.js';
import type { AiProvider, ChatRequest, ChatResult } from './types.js';
import { parseSseStream } from './sse.js';

const API_URL = 'https://api.openai.com/v1/chat/completions';

function headers() {
  if (!config.openaiApiKey) throw AppError.badRequest('OPENAI_API_KEY not configured', 'provider_unconfigured');
  return { 'content-type': 'application/json', authorization: `Bearer ${config.openaiApiKey}` };
}

function body(req: ChatRequest, stream: boolean) {
  return {
    model: req.model ?? openaiProvider.defaultModel,
    messages: req.messages,
    max_completion_tokens: req.maxTokens ?? 4096,
    temperature: req.temperature,
    stream,
  };
}

export const openaiProvider: AiProvider = {
  name: 'openai',
  defaultModel: 'gpt-4o',

  async complete(req: ChatRequest): Promise<ChatResult> {
    const res = await fetch(API_URL, { method: 'POST', headers: headers(), body: JSON.stringify(body(req, false)) });
    if (!res.ok) throw new AppError(502, 'provider_error', `OpenAI: ${res.status} ${await res.text()}`);
    const data = await res.json() as {
      choices: { message: { content: string } }[];
      usage?: { prompt_tokens: number; completion_tokens: number };
    };
    return {
      content: data.choices[0]?.message.content ?? '',
      tokensIn: data.usage?.prompt_tokens,
      tokensOut: data.usage?.completion_tokens,
    };
  },

  async *stream(req: ChatRequest) {
    const res = await fetch(API_URL, { method: 'POST', headers: headers(), body: JSON.stringify(body(req, true)) });
    if (!res.ok || !res.body) throw new AppError(502, 'provider_error', `OpenAI: ${res.status} ${await res.text()}`);
    let content = '';
    for await (const event of parseSseStream(res.body)) {
      if (event === '[DONE]') break;
      const data = JSON.parse(event) as { choices: { delta?: { content?: string } }[] };
      const delta = data.choices[0]?.delta?.content;
      if (delta) {
        content += delta;
        yield delta;
      }
    }
    return { content };
  },
};
