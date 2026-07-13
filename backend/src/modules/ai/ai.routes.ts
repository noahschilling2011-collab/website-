import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import * as chat from './chat.service.js';
import * as tools from './tools.service.js';
import * as media from './media.service.js';
import { transcribeAudio } from './speech.service.js';
import { ocrImage } from './ocr.service.js';
import { extractPdfText } from './pdf.service.js';
import { asyncHandler } from '../../utils/asyncHandler.js';
import { requireAuth } from '../../middleware/auth.js';
import { validateBody } from '../../middleware/validate.js';
import { rateLimit } from '../../middleware/rateLimit.js';
import { AppError } from '../../utils/errors.js';
import type { ProviderName } from './providers/index.js';

const memoryUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 },
});

export const aiRouter = Router();
aiRouter.use(requireAuth);
aiRouter.use(rateLimit({ windowSec: 60, max: 60, keyPrefix: 'ai' }));

const providerSchema = z.enum(['openai', 'anthropic', 'gemini']).optional();

// ---------- Conversations & Chat ----------

aiRouter.get('/conversations', asyncHandler(async (req, res) => {
  res.json({ conversations: await chat.listConversations(req.user!.id) });
}));

aiRouter.post('/conversations',
  validateBody(z.object({ title: z.string().max(200).optional(), provider: providerSchema, model: z.string().max(100).optional() })),
  asyncHandler(async (req, res) => {
    res.status(201).json({ conversation: await chat.createConversation(req.user!.id, req.body) });
  }));

aiRouter.get('/conversations/:id/messages', asyncHandler(async (req, res) => {
  await chat.getConversation(req.user!.id, req.params.id!);
  res.json({ messages: await chat.getHistory(req.params.id!) });
}));

/** Streaming chat: sends the assistant reply as SSE `data:` chunks. */
aiRouter.post('/conversations/:id/messages',
  validateBody(z.object({ content: z.string().min(1).max(100_000) })),
  asyncHandler(async (req, res) => {
    res.setHeader('content-type', 'text/event-stream');
    res.setHeader('cache-control', 'no-cache');
    res.setHeader('connection', 'keep-alive');
    res.flushHeaders();
    try {
      for await (const delta of chat.streamReply(req.user!.id, req.params.id!, req.body.content)) {
        res.write(`data: ${JSON.stringify({ delta })}\n\n`);
      }
      res.write('data: [DONE]\n\n');
    } catch (err) {
      res.write(`data: ${JSON.stringify({ error: (err as Error).message })}\n\n`);
    }
    res.end();
  }));

// ---------- Tools ----------

aiRouter.post('/summarize/url',
  validateBody(z.object({ url: z.string().url(), provider: providerSchema, language: z.string().max(20).optional() })),
  asyncHandler(async (req, res) => {
    res.json({ summary: await tools.summarizeUrl(req.body.url, req.body.provider, req.body.language) });
  }));

aiRouter.post('/summarize/text',
  validateBody(z.object({ text: z.string().min(1), provider: providerSchema, language: z.string().max(20).optional() })),
  asyncHandler(async (req, res) => {
    res.json({ summary: await tools.summarizeText(req.body.text, req.body.provider, req.body.language) });
  }));

aiRouter.post('/summarize/youtube',
  validateBody(z.object({ url: z.string().url(), provider: providerSchema, language: z.string().max(20).optional() })),
  asyncHandler(async (req, res) => {
    res.json({ summary: await tools.summarizeYoutube(req.body.url, req.body.provider, req.body.language) });
  }));

aiRouter.post('/translate',
  validateBody(z.object({ text: z.string().min(1).max(100_000), targetLanguage: z.string().min(2).max(40), provider: providerSchema })),
  asyncHandler(async (req, res) => {
    res.json({ translation: await tools.translate(req.body.text, req.body.targetLanguage, req.body.provider) });
  }));

aiRouter.post('/documents/write',
  validateBody(z.object({
    topic: z.string().min(1).max(5000),
    kind: z.string().min(1).max(100),
    language: z.string().max(20).optional(),
    tone: z.string().max(50).optional(),
    length: z.string().max(20).optional(),
    provider: providerSchema,
  })),
  asyncHandler(async (req, res) => {
    const { provider, ...input } = req.body;
    res.json({ document: await tools.writeDocument(input, provider) });
  }));

aiRouter.post('/presentations',
  validateBody(z.object({ topic: z.string().min(1).max(5000), slideCount: z.number().int().min(3).max(30).optional(), provider: providerSchema, language: z.string().max(20).optional() })),
  asyncHandler(async (req, res) => {
    res.json({ presentation: await tools.createPresentation(req.body.topic, req.body.slideCount, req.body.provider, req.body.language) });
  }));

aiRouter.post('/mindmaps',
  validateBody(z.object({ topic: z.string().min(1).max(5000), provider: providerSchema, language: z.string().max(20).optional() })),
  asyncHandler(async (req, res) => {
    res.json({ mindmap: await tools.createMindmap(req.body.topic, req.body.provider, req.body.language) });
  }));

aiRouter.post('/code',
  validateBody(z.object({
    instruction: z.string().min(1).max(10_000),
    code: z.string().max(200_000).optional(),
    language: z.string().max(50).optional(),
    action: z.enum(['explain', 'fix', 'refactor', 'generate', 'review', 'test']),
    provider: providerSchema,
  })),
  asyncHandler(async (req, res) => {
    const { provider, ...input } = req.body;
    res.json({ result: await tools.codeAssist(input, provider) });
  }));

// ---------- Uploads: PDF, OCR, Speech ----------

/** PDF analysieren: extract text, then summarize. Field name: "file". */
aiRouter.post('/summarize/pdf', memoryUpload.single('file'), asyncHandler(async (req, res) => {
  if (!req.file) throw AppError.badRequest('No file uploaded (field name: "file")');
  const text = await extractPdfText(req.file.buffer);
  const language = typeof req.body.language === 'string' ? req.body.language : undefined;
  res.json({ summary: await tools.summarizeText(text, undefined, language), characters: text.length });
}));

/** OCR: extract text from an image (photo, scan, screenshot). Field name: "file". */
aiRouter.post('/ocr', memoryUpload.single('file'), asyncHandler(async (req, res) => {
  if (!req.file) throw AppError.badRequest('No file uploaded (field name: "file")');
  res.json(await ocrImage(req.file.buffer, req.file.mimetype));
}));

/** Speech-to-text (voice chat transcription). Field name: "file". */
aiRouter.post('/transcribe', memoryUpload.single('file'), asyncHandler(async (req, res) => {
  if (!req.file) throw AppError.badRequest('No file uploaded (field name: "file")');
  const language = typeof req.body.language === 'string' ? req.body.language : undefined;
  res.json(await transcribeAudio(req.file.buffer, req.file.originalname, language));
}));

// ---------- Media generation ----------

const mediaLimiter = rateLimit({ windowSec: 3600, max: 30, keyPrefix: 'media' });

aiRouter.post('/media/:kind(image|video|music)',
  mediaLimiter,
  validateBody(z.object({ prompt: z.string().min(1).max(5000) })),
  asyncHandler(async (req, res) => {
    const job = await media.createMediaJob(req.user!.id, req.params.kind as media.MediaKind, req.body.prompt);
    res.status(202).json({ job });
  }));

aiRouter.get('/jobs/:id', asyncHandler(async (req, res) => {
  res.json({ job: await media.getJob(req.user!.id, req.params.id!) });
}));
