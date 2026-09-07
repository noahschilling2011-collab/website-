import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handleAus, parseEingang, pdfText } from './eingang';

/** Baut ein minimales, gueltiges PDF mit korrektem xref-Verweis. */
function bauePdf(inhalt: string | null): Uint8Array {
  const objekte: string[] = [];
  const strom = inhalt === null ? '' : `BT /F1 12 Tf 72 720 Td (${inhalt}) Tj ET`;

  objekte.push('<< /Type /Catalog /Pages 2 0 R >>');
  objekte.push('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  objekte.push(
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
  );
  objekte.push(`<< /Length ${strom.length} >>\nstream\n${strom}\nendstream`);
  objekte.push('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objekte.forEach((objekt, i) => {
    offsets.push(pdf.length);
    pdf += `${i + 1} 0 obj\n${objekt}\nendobj\n`;
  });

  const xrefStart = pdf.length;
  pdf += `xref\n0 ${objekte.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) {
    pdf += `${String(offset).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objekte.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF\n`;

  return new TextEncoder().encode(pdf);
}

function baueMime(teile: {
  von: string;
  an: string;
  betreff: string;
  text: string;
  messageId: string;
  inReplyTo?: string;
  referenzen?: string;
  anhang?: { name: string; typ: string; base64: string };
}): string {
  const grenze = '----grenze12345';
  const kopf = [
    `From: ${teile.von}`,
    `To: ${teile.an}`,
    `Subject: ${teile.betreff}`,
    `Message-ID: <${teile.messageId}>`,
    teile.inReplyTo ? `In-Reply-To: <${teile.inReplyTo}>` : null,
    teile.referenzen ? `References: ${teile.referenzen}` : null,
    'MIME-Version: 1.0',
  ].filter((z) => z !== null);

  if (!teile.anhang) {
    return [...kopf, 'Content-Type: text/plain; charset=utf-8', '', teile.text].join('\r\n');
  }

  return [
    ...kopf,
    `Content-Type: multipart/mixed; boundary="${grenze}"`,
    '',
    `--${grenze}`,
    'Content-Type: text/plain; charset=utf-8',
    '',
    teile.text,
    `--${grenze}`,
    `Content-Type: ${teile.anhang.typ}; name="${teile.anhang.name}"`,
    'Content-Transfer-Encoding: base64',
    `Content-Disposition: attachment; filename="${teile.anhang.name}"`,
    '',
    teile.anhang.base64.replace(/(.{76})/g, '$1\r\n'),
    `--${grenze}--`,
    '',
  ].join('\r\n');
}

test('Einfache Mail wird zerlegt', async () => {
  const roh = baueMime({
    von: 'Sabine Berger <berger@example.de>',
    an: 'katrin@assistent.example',
    betreff: 'Termin Jonas verschieben',
    text: 'Guten Tag, koennen wir den Donnerstag verschieben?',
    messageId: 'erste@example.de',
  });

  const mail = await parseEingang(roh);
  assert.equal(mail.von, 'berger@example.de');
  assert.equal(mail.vonName, 'Sabine Berger');
  assert.equal(mail.betreff, 'Termin Jonas verschieben');
  assert.match(mail.text, /Donnerstag verschieben/);
  assert.equal(mail.messageId, 'erste@example.de');
  assert.equal(mail.threadKey, 'erste@example.de');
  assert.deepEqual(mail.an, ['katrin@assistent.example']);
});

test('Antwort im Thread bekommt denselben Thread-Schluessel', async () => {
  const roh = baueMime({
    von: 'berger@example.de',
    an: 'katrin@assistent.example',
    betreff: 'Re: Termin Jonas verschieben',
    text: 'Dienstag passt.',
    messageId: 'dritte@example.de',
    inReplyTo: 'zweite@example.de',
    referenzen: '<erste@example.de> <zweite@example.de>',
  });

  const mail = await parseEingang(roh);
  assert.equal(mail.threadKey, 'erste@example.de');
  assert.equal(mail.inReplyTo, 'zweite@example.de');
});

test('Handle wird aus der Empfaengeradresse gezogen', () => {
  assert.equal(handleAus(['katrin@assistent.example'], 'assistent.example'), 'katrin');
  assert.equal(handleAus(['KATRIN@Assistent.Example'], 'assistent.example'), 'katrin');
  assert.equal(handleAus(['fremd@woanders.de'], 'assistent.example'), null);
  assert.equal(
    handleAus(['fremd@woanders.de', 'katrin@assistent.example'], 'assistent.example'),
    'katrin',
  );
});

test('PDF mit Textschicht wird ausgelesen', async () => {
  const pdf = bauePdf('Verordnung gueltig bis 18.08.2026 Betrag 312,00 EUR');
  const ergebnis = await pdfText(pdf);
  assert.equal(ergebnis.extraktionFehlgeschlagen, false);
  assert.match(ergebnis.textExtrakt ?? '', /18\.08\.2026/);
});

test('Gescanntes PDF ohne Textschicht wird abgelehnt statt geraten', async () => {
  // Kein OCR: lieber einmal zu oft nachfragen als eine Frist erfinden.
  const pdf = bauePdf(null);
  const ergebnis = await pdfText(pdf);
  assert.equal(ergebnis.extraktionFehlgeschlagen, true);
  assert.equal(ergebnis.textExtrakt, null);
});

test('PDF-Anhang einer Mail landet als Textextrakt am Vorgang', async () => {
  const pdf = bauePdf('Folgeverordnung Ergotherapie Frist 18.08.2026');
  const roh = baueMime({
    von: 'praxis@kinderarzt.example',
    an: 'katrin@assistent.example',
    betreff: 'Folgeverordnung',
    text: 'Anbei die Verordnung.',
    messageId: 'verordnung@kinderarzt.example',
    anhang: {
      name: 'verordnung.pdf',
      typ: 'application/pdf',
      base64: Buffer.from(pdf).toString('base64'),
    },
  });

  const mail = await parseEingang(roh);
  assert.equal(mail.anhaenge.length, 1);
  const anhang = mail.anhaenge[0]!;
  assert.equal(anhang.dateiname, 'verordnung.pdf');
  assert.equal(anhang.mimeTyp, 'application/pdf');
  assert.equal(anhang.extraktionFehlgeschlagen, false);
  assert.match(anhang.textExtrakt ?? '', /18\.08\.2026/);
});

test('Unbekannte Anhangtypen werden nicht geraten', async () => {
  const roh = baueMime({
    von: 'a@b.de',
    an: 'katrin@assistent.example',
    betreff: 'Foto',
    text: 'siehe Anhang',
    messageId: 'foto@b.de',
    anhang: { name: 'bild.png', typ: 'image/png', base64: 'iVBORw0KGgo=' },
  });

  const mail = await parseEingang(roh);
  assert.equal(mail.anhaenge[0]!.extraktionFehlgeschlagen, true);
  assert.equal(mail.anhaenge[0]!.textExtrakt, null);
});
