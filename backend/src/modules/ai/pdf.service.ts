/** Extracts plain text from an uploaded PDF (pdf-parse / pdf.js). */
import { PDFParse } from 'pdf-parse';
import { AppError } from '../../utils/errors.js';

export async function extractPdfText(pdf: Buffer): Promise<string> {
  let parser: PDFParse | null = null;
  try {
    parser = new PDFParse({ data: new Uint8Array(pdf) });
    const result = await parser.getText();
    const text = result.text.trim();
    if (!text) throw AppError.badRequest('PDF contains no extractable text (scanned? try OCR)', 'pdf_no_text');
    return text;
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw AppError.badRequest(`Could not parse PDF: ${(err as Error).message}`, 'pdf_invalid');
  } finally {
    await parser?.destroy().catch(() => undefined);
  }
}
