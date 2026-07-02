export type ProviderName = 'openai' | 'anthropic' | 'gemini';

export interface ChatMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface ChatRequest {
  model?: string;
  messages: ChatMessage[];
  maxTokens?: number;
  temperature?: number;
}

export interface ChatResult {
  content: string;
  tokensIn?: number;
  tokensOut?: number;
}

export interface AiProvider {
  name: ProviderName;
  defaultModel: string;
  /** Non-streaming completion. */
  complete(req: ChatRequest): Promise<ChatResult>;
  /** Streaming completion; yields text deltas. */
  stream(req: ChatRequest): AsyncGenerator<string, ChatResult, void>;
}
