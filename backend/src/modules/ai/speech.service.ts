/**
 * Speech-to-text via the OpenAI Whisper API. The app records short audio
 * chunks and posts them here; chaining chunk transcriptions gives
 * near-realtime captions in the voice chat UI.
 */
import { config } from '../../config/index.js';
import { AppError } from '../../utils/errors.js';

export async function transcribeAudio(
  audio: Buffer,
  filename: string,
  language?: string,
): Promise<{ text: string }> {
  if (!config.openaiApiKey) {
    throw AppError.badRequest('OPENAI_API_KEY not configured', 'provider_unconfigured');
  }
  const form = new FormData();
  form.append('file', new Blob([new Uint8Array(audio)]), filename || 'audio.webm');
  form.append('model', 'whisper-1');
  if (language) form.append('language', language);

  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { authorization: `Bearer ${config.openaiApiKey}` },
    body: form,
  });
  if (!res.ok) throw new AppError(502, 'provider_error', `Whisper: ${res.status} ${await res.text()}`);
  const data = await res.json() as { text: string };
  return { text: data.text };
}
