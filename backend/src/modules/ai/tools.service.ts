/**
 * AI tool endpoints built on top of the chat providers: summarize URLs,
 * PDFs and YouTube videos, translate, write documents, build presentation
 * outlines and mindmaps. Each helper produces a single provider call with
 * a task-specific system prompt.
 */
import { getProvider, type ProviderName } from './providers/index.js';
import { AppError } from '../../utils/errors.js';

const MAX_INPUT_CHARS = 120_000;

async function run(provider: ProviderName | undefined, system: string, user: string): Promise<string> {
  const p = getProvider(provider ?? 'anthropic');
  const result = await p.complete({
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user.slice(0, MAX_INPUT_CHARS) },
    ],
  });
  return result.content;
}

/** Fetches a web page and strips tags to plain text (best effort, no headless browser). */
export async function fetchPageText(url: string): Promise<string> {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw AppError.badRequest('Invalid URL');
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) throw AppError.badRequest('Only http(s) URLs allowed');
  const res = await fetch(parsed, { headers: { 'user-agent': 'NexusAI/1.0 (+summarizer)' } });
  if (!res.ok) throw new AppError(502, 'fetch_failed', `Fetch failed: ${res.status}`);
  const html = await res.text();
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export async function summarizeUrl(url: string, provider?: ProviderName, language = 'de'): Promise<string> {
  const text = await fetchPageText(url);
  if (text.length < 100) throw AppError.badRequest('Page has no extractable text content');
  return run(provider,
    `Summarize the given web page content concisely in ${language}. Use short paragraphs and bullet points for key facts.`,
    `URL: ${url}\n\n${text}`);
}

export async function summarizeText(text: string, provider?: ProviderName, language = 'de'): Promise<string> {
  return run(provider,
    `Summarize the given document in ${language}: a short abstract, then the key points as bullets, then open questions if any.`,
    text);
}

export async function summarizeYoutube(videoUrl: string, provider?: ProviderName, language = 'de'): Promise<string> {
  // Uses the public transcript-less fallback: fetch the watch page and summarize
  // title/description metadata. For full transcripts plug in a captions service.
  const text = await fetchPageText(videoUrl);
  return run(provider,
    `You are given the scraped page content of a YouTube video. Extract title, channel and topic, and summarize what the video covers in ${language}. State clearly when information is not available from the page.`,
    text);
}

export async function translate(text: string, targetLanguage: string, provider?: ProviderName): Promise<string> {
  return run(provider,
    `Translate the user's text into ${targetLanguage}. Preserve formatting, tone and technical terms. Output only the translation.`,
    text);
}

export async function writeDocument(
  input: { topic: string; kind: string; language?: string; tone?: string; length?: string },
  provider?: ProviderName,
): Promise<string> {
  return run(provider,
    `Write a complete, well-structured ${input.kind} in ${input.language ?? 'de'} as Markdown. Tone: ${input.tone ?? 'professional'}. Length: ${input.length ?? 'medium'}.`,
    input.topic);
}

export interface PresentationSlide { title: string; bullets: string[]; speakerNotes?: string }

export async function createPresentation(
  topic: string,
  slideCount = 10,
  provider?: ProviderName,
  language = 'de',
): Promise<{ title: string; slides: PresentationSlide[] }> {
  const raw = await run(provider,
    `Create a presentation outline in ${language} as strict JSON matching {"title": string, "slides": [{"title": string, "bullets": string[], "speakerNotes": string}]} with exactly ${slideCount} slides. Output only JSON, no markdown fences.`,
    topic);
  return parseJson(raw);
}

export interface MindmapNode { label: string; children?: MindmapNode[] }

export async function createMindmap(topic: string, provider?: ProviderName, language = 'de'): Promise<MindmapNode> {
  const raw = await run(provider,
    `Create a mindmap in ${language} as strict JSON matching {"label": string, "children": [...recursive...]}. 3 levels deep, 4-6 branches per level where sensible. Output only JSON, no markdown fences.`,
    topic);
  return parseJson(raw);
}

function parseJson<T>(raw: string): T {
  const cleaned = raw.replace(/^```(json)?/m, '').replace(/```\s*$/m, '').trim();
  try {
    return JSON.parse(cleaned) as T;
  } catch {
    throw new AppError(502, 'provider_bad_output', 'Model returned malformed JSON');
  }
}
