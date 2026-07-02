import { describe, expect, it } from 'vitest';
import { parseSseStream } from '../src/modules/ai/providers/sse.js';

function streamOf(chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const c of chunks) controller.enqueue(encoder.encode(c));
      controller.close();
    },
  });
}

async function collect(stream: ReadableStream<Uint8Array>): Promise<string[]> {
  const out: string[] = [];
  for await (const event of parseSseStream(stream)) out.push(event);
  return out;
}

describe('parseSseStream', () => {
  it('parses complete events', async () => {
    const events = await collect(streamOf(['data: {"a":1}\n\ndata: {"b":2}\n\n']));
    expect(events).toEqual(['{"a":1}', '{"b":2}']);
  });

  it('handles events split across chunks', async () => {
    const events = await collect(streamOf(['data: {"a"', ':1}\n', '\ndata: [DONE]\n\n']));
    expect(events).toEqual(['{"a":1}', '[DONE]']);
  });

  it('ignores non-data lines like event: and comments', async () => {
    const events = await collect(streamOf(['event: ping\n: keepalive\ndata: x\n\n']));
    expect(events).toEqual(['x']);
  });
});
