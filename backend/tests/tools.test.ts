import { describe, expect, it } from 'vitest';
import { parseJson, stripHtml } from '../src/modules/ai/tools.service.js';
import { AppError } from '../src/utils/errors.js';

describe('stripHtml', () => {
  it('removes tags, scripts and styles', () => {
    const html = `<html><head><style>.x{color:red}</style></head>
      <body><script>alert(1)</script><h1>Titel</h1><p>Hallo  Welt</p></body></html>`;
    expect(stripHtml(html)).toBe('Titel Hallo Welt');
  });

  it('decodes common entities', () => {
    expect(stripHtml('<p>A &amp; B &lt;C&gt;&nbsp;D</p>')).toBe('A & B <C> D');
  });
});

describe('parseJson', () => {
  it('parses plain JSON', () => {
    expect(parseJson<{ a: number }>('{"a": 1}')).toEqual({ a: 1 });
  });

  it('strips markdown fences the model may add', () => {
    expect(parseJson<{ a: number }>('```json\n{"a": 1}\n```')).toEqual({ a: 1 });
  });

  it('throws a typed 502 on malformed output', () => {
    expect(() => parseJson('not json')).toThrowError(AppError);
    try {
      parseJson('not json');
    } catch (err) {
      expect((err as AppError).status).toBe(502);
      expect((err as AppError).code).toBe('provider_bad_output');
    }
  });
});
