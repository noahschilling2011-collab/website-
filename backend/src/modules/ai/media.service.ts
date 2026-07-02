/**
 * Media generation (image / video / music) via OpenAI Images and Replicate.
 * Long-running generations are tracked as ai_jobs rows; clients poll
 * GET /api/ai/jobs/:id or listen on the WebSocket channel `job:<id>`.
 */
import { config } from '../../config/index.js';
import { query, queryOne } from '../../db/pool.js';
import { AppError } from '../../utils/errors.js';
import { logger } from '../../utils/logger.js';

export type MediaKind = 'image' | 'video' | 'music';

export interface AiJobRow {
  id: string;
  user_id: string;
  kind: string;
  status: 'queued' | 'running' | 'done' | 'failed';
  input: Record<string, unknown>;
  output: Record<string, unknown> | null;
  error: string | null;
}

const REPLICATE_MODELS: Record<Exclude<MediaKind, 'image'>, string> = {
  video: 'minimax/video-01',
  music: 'meta/musicgen',
};

export async function createMediaJob(userId: string, kind: MediaKind, prompt: string): Promise<AiJobRow> {
  const job = await queryOne<AiJobRow>(
    `INSERT INTO ai_jobs (user_id, kind, input) VALUES ($1, $2, $3) RETURNING *`,
    [userId, kind, JSON.stringify({ prompt })],
  );
  // Fire and forget; failures are recorded on the job row.
  void runMediaJob(job!).catch((err) => logger.error({ err, jobId: job!.id }, 'Media job crashed'));
  return job!;
}

export async function getJob(userId: string, id: string): Promise<AiJobRow> {
  const job = await queryOne<AiJobRow>('SELECT * FROM ai_jobs WHERE id = $1 AND user_id = $2', [id, userId]);
  if (!job) throw AppError.notFound('Job not found');
  return job;
}

async function setJob(id: string, fields: { status: string; output?: unknown; error?: string }): Promise<void> {
  await query(
    'UPDATE ai_jobs SET status = $2, output = $3, error = $4 WHERE id = $1',
    [id, fields.status, fields.output ? JSON.stringify(fields.output) : null, fields.error ?? null],
  );
}

async function runMediaJob(job: AiJobRow): Promise<void> {
  await setJob(job.id, { status: 'running' });
  try {
    const prompt = String(job.input.prompt ?? '');
    const output = job.kind === 'image'
      ? await generateImage(prompt)
      : await generateViaReplicate(job.kind as 'video' | 'music', prompt);
    await setJob(job.id, { status: 'done', output });
  } catch (err) {
    await setJob(job.id, { status: 'failed', error: (err as Error).message });
  }
}

async function generateImage(prompt: string): Promise<{ url: string }> {
  if (!config.openaiApiKey) throw AppError.badRequest('OPENAI_API_KEY not configured', 'provider_unconfigured');
  const res = await fetch('https://api.openai.com/v1/images/generations', {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${config.openaiApiKey}` },
    body: JSON.stringify({ model: 'gpt-image-1', prompt, n: 1, size: '1024x1024' }),
  });
  if (!res.ok) throw new AppError(502, 'provider_error', `Image API: ${res.status} ${await res.text()}`);
  const data = await res.json() as { data: { url?: string; b64_json?: string }[] };
  const first = data.data[0];
  if (first?.url) return { url: first.url };
  if (first?.b64_json) return { url: `data:image/png;base64,${first.b64_json}` };
  throw new AppError(502, 'provider_error', 'Image API returned no image');
}

async function generateViaReplicate(kind: 'video' | 'music', prompt: string): Promise<{ url: string }> {
  if (!config.replicateApiToken) throw AppError.badRequest('REPLICATE_API_TOKEN not configured', 'provider_unconfigured');
  const create = await fetch(`https://api.replicate.com/v1/models/${REPLICATE_MODELS[kind]}/predictions`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${config.replicateApiToken}`,
      prefer: 'wait=60',
    },
    body: JSON.stringify({ input: { prompt } }),
  });
  if (!create.ok) throw new AppError(502, 'provider_error', `Replicate: ${create.status} ${await create.text()}`);
  let prediction = await create.json() as { id: string; status: string; output?: unknown; error?: string };

  // Poll until terminal state (prefer:wait already covers most cases).
  const pollUntil = Date.now() + 10 * 60_000;
  while (!['succeeded', 'failed', 'canceled'].includes(prediction.status)) {
    if (Date.now() > pollUntil) throw new AppError(504, 'provider_timeout', 'Generation timed out');
    await new Promise((r) => setTimeout(r, 3000));
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${prediction.id}`, {
      headers: { authorization: `Bearer ${config.replicateApiToken}` },
    });
    prediction = await poll.json() as typeof prediction;
  }
  if (prediction.status !== 'succeeded') {
    throw new AppError(502, 'provider_error', prediction.error ?? 'Generation failed');
  }
  const output = prediction.output;
  const url = Array.isArray(output) ? String(output[0]) : String(output);
  return { url };
}
