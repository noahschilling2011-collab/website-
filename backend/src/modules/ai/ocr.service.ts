/**
 * OCR via multimodal models: the image is sent to the selected provider's
 * vision endpoint with an extraction prompt. Works for photos, scans and
 * screenshots and handles handwriting far better than classic OCR.
 */
import { config } from '../../config/index.js';
import { AppError } from '../../utils/errors.js';

const OCR_PROMPT =
  'Extract ALL text from this image exactly as written, preserving layout with line breaks. '
  + 'Output only the extracted text, no commentary. If there is no text, output "(kein Text erkannt)".';

export async function ocrImage(
  image: Buffer,
  mimeType: string,
  provider: 'openai' | 'anthropic' = config.anthropicApiKey ? 'anthropic' : 'openai',
): Promise<{ text: string }> {
  if (!['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(mimeType)) {
    throw AppError.badRequest(`Unsupported image type: ${mimeType}`, 'unsupported_media');
  }
  const b64 = image.toString('base64');
  return provider === 'anthropic' ? ocrAnthropic(b64, mimeType) : ocrOpenai(b64, mimeType);
}

async function ocrAnthropic(b64: string, mimeType: string): Promise<{ text: string }> {
  if (!config.anthropicApiKey) throw AppError.badRequest('ANTHROPIC_API_KEY not configured', 'provider_unconfigured');
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': config.anthropicApiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-5',
      max_tokens: 4096,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mimeType, data: b64 } },
          { type: 'text', text: OCR_PROMPT },
        ],
      }],
    }),
  });
  if (!res.ok) throw new AppError(502, 'provider_error', `OCR: ${res.status} ${await res.text()}`);
  const data = await res.json() as { content: { type: string; text?: string }[] };
  return { text: data.content.filter((b) => b.type === 'text').map((b) => b.text).join('') };
}

async function ocrOpenai(b64: string, mimeType: string): Promise<{ text: string }> {
  if (!config.openaiApiKey) throw AppError.badRequest('OPENAI_API_KEY not configured', 'provider_unconfigured');
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${config.openaiApiKey}` },
    body: JSON.stringify({
      model: 'gpt-4o',
      max_completion_tokens: 4096,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: OCR_PROMPT },
          { type: 'image_url', image_url: { url: `data:${mimeType};base64,${b64}` } },
        ],
      }],
    }),
  });
  if (!res.ok) throw new AppError(502, 'provider_error', `OCR: ${res.status} ${await res.text()}`);
  const data = await res.json() as { choices: { message: { content: string } }[] };
  return { text: data.choices[0]?.message.content ?? '' };
}
