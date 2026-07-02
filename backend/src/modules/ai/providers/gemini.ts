import { config } from '../../../config/index.js';
import { AppError } from '../../../utils/errors.js';
import type { AiProvider, ChatRequest, ChatResult } from './types.js';
import { parseSseStream } from './sse.js';

const BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

function toGeminiBody(req: ChatRequest) {
  const system = req.messages.filter((m) => m.role === 'system').map((m) => m.content).join('\n');
  return {
    systemInstruction: system ? { parts: [{ text: system }] } : undefined,
    contents: req.messages
      .filter((m) => m.role !== 'system')
      .map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
    generationConfig: { maxOutputTokens: req.maxTokens ?? 4096, temperature: req.temperature },
  };
}

function requireKey(): string {
  if (!config.geminiApiKey) throw AppError.badRequest('GEMINI_API_KEY not configured', 'provider_unconfigured');
  return config.geminiApiKey;
}

type GeminiChunk = {
  candidates?: { content?: { parts?: { text?: string }[] } }[];
  usageMetadata?: { promptTokenCount: number; candidatesTokenCount: number };
};

const textOf = (c: GeminiChunk) =>
  c.candidates?.[0]?.content?.parts?.map((p) => p.text ?? '').join('') ?? '';

export const geminiProvider: AiProvider = {
  name: 'gemini',
  defaultModel: 'gemini-2.0-flash',

  async complete(req: ChatRequest): Promise<ChatResult> {
    const model = req.model ?? geminiProvider.defaultModel;
    const res = await fetch(`${BASE}/${model}:generateContent?key=${requireKey()}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(toGeminiBody(req)),
    });
    if (!res.ok) throw new AppError(502, 'provider_error', `Gemini: ${res.status} ${await res.text()}`);
    const data = await res.json() as GeminiChunk;
    return {
      content: textOf(data),
      tokensIn: data.usageMetadata?.promptTokenCount,
      tokensOut: data.usageMetadata?.candidatesTokenCount,
    };
  },

  async *stream(req: ChatRequest) {
    const model = req.model ?? geminiProvider.defaultModel;
    const res = await fetch(`${BASE}/${model}:streamGenerateContent?alt=sse&key=${requireKey()}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(toGeminiBody(req)),
    });
    if (!res.ok || !res.body) throw new AppError(502, 'provider_error', `Gemini: ${res.status} ${await res.text()}`);
    let content = '';
    for await (const event of parseSseStream(res.body)) {
      const chunk = JSON.parse(event) as GeminiChunk;
      const delta = textOf(chunk);
      if (delta) {
        content += delta;
        yield delta;
      }
    }
    return { content };
  },
};
