import type { AiProvider, ProviderName } from './types.js';
import { anthropicProvider } from './anthropic.js';
import { openaiProvider } from './openai.js';
import { geminiProvider } from './gemini.js';
import { AppError } from '../../../utils/errors.js';

const providers: Record<ProviderName, AiProvider> = {
  anthropic: anthropicProvider,
  openai: openaiProvider,
  gemini: geminiProvider,
};

export function getProvider(name: string): AiProvider {
  const p = providers[name as ProviderName];
  if (!p) throw AppError.badRequest(`Unknown provider: ${name}`, 'unknown_provider');
  return p;
}

export type { AiProvider, ChatMessage, ChatRequest, ChatResult, ProviderName } from './types.js';
