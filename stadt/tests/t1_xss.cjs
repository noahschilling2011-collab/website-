// T1: HTML/Script in code, titel, sprache, gedanke → nur Text; Code-Zäune; kaputte Antworten; einmal pro Tag
const U = require('./umgebung.cjs');
const { starte, mitStand, BASIS, INFO } = require('./hilfe.cjs');
const fs = require('fs');
const info = JSON.parse(fs.readFileSync(INFO, 'utf8'));
const ok = (bed, text) => { console.log((bed ? 'OK   ' : 'FEHL ') + text); if (!bed) process.exitCode = 1; };
const BOESE = {
  titel: '<img src=x onerror="alert(\'titel\')">Titel',
  sprache: '"><svg onload=alert(\'sprache\')>',
  gedanke: '<iframe srcdoc="<script>alert(4)</script>"></iframe> & &amp;',
  code: '</code></pre><img src=x onerror="alert(\'code\')"><script>alert(1)</script>\n  x = "\u0000\u001b[31m" & y\n‮abc',
};
(async () => {
  const { b, ctx, page, st, ev, log, dialoge } = await starte({ codeAntwort: JSON.stringify(BOESE) });
  await mitStand(ctx, fs.readFileSync(BASIS, 'utf8'));
  await page.goto(U.HOST + '/stadt.html?debug');
  await page.waitForFunction(() => globalThis.__stadt && globalThis.__stadtDebug);
  await ev(() => __stadt.setzeTempo(0));
  await page.waitForFunction(() => __stadt.ki.status === 'bereit', null, { timeout: 20000 });
  // Nachfolge-Dialog wegklicken, falls offen
  for (let i = 0; i < 12; i++) { if (!(await ev(() => document.getElementById('nachfolge-dialog').open))) break; await page.click('#nachfolge-knoepfe button:last-child'); await page.waitForTimeout(200); }
  await ev(() => { const a = __stadt, S = a.S(); while (S.stunde !== 10) a.schritt(); a.nachSchritten(); });
  const k = info.p + '/' + info.gen;
  await page.waitForFunction((k) => (__stadt.S().ki.tagebuch[k] || []).some(e => e.art === 'code'), k, { timeout: 30000 }).catch(() => {});
  const r = await ev((k) => ({ eintrag: (__stadt.S().ki.tagebuch[k] || []).filter(e => e.art === 'code').at(-1), stat: __stadt.ki.stat, fehler: __stadt.ki.letzterFehler }), k);
  console.log('Eintrag:', JSON.stringify(r.eintrag));
  ok(!!r.eintrag, 'Code-Eintrag mit bösen Feldern angenommen (Text)');
  await ev((p) => document.querySelector(`#haupt-liste .haupt-zeile[data-p="${p}"]`).click(), info.p);
  await page.waitForTimeout(300);
  const d = await ev(() => {
    const k = document.getElementById('karte-inhalt'), l = document.getElementById('haupt-liste');
    const pre = [...k.querySelectorAll('pre.code')].at(-1);
    return { fremd: k.querySelectorAll('img,svg:not(.sym),iframe,script').length + l.querySelectorAll('img,svg:not(.sym),iframe,script').length,
      pre: pre ? pre.textContent : null, meta: [...k.querySelectorAll('.tagebuch .meta')].at(-1).textContent,
      p: [...k.querySelectorAll('.tagebuch li')].at(-1).querySelector('p')?.textContent, leiste: l.innerText, aria: pre && pre.getAttribute('aria-label') };
  });
  console.log(JSON.stringify(d, null, 1));
  ok(d.fremd === 0 && dialoge.length === 0, `keine eingeschleusten Elemente, keine Dialoge (${d.fremd}, ${dialoge.join('|')})`);
  ok(d.pre && d.pre.includes('<script>alert(1)</script>') && d.pre.includes('</code></pre>'), 'Code wörtlich im <pre>');
  // Code-Zäune und kaputte Antworten (codeTag zurücksetzen, damit dieselbe Figur heute noch einmal dran ist)
  const faelle = [
    ['Zaun', JSON.stringify({ titel: 'Liste', sprache: 'Python', code: '```python\ndef f():\n    return 1\n```', gedanke: 'Kurz.' })],
    ['kaputt', '{"titel": "x", "code": "abc'],
    ['code-zahl', JSON.stringify({ titel: 'x', code: 42 })],
    ['code-leer', JSON.stringify({ titel: 'x', code: '  \n\t\n ' })],
    ['code-array', JSON.stringify({ titel: 'x', code: ['a'] })],
    ['titel-objekt', JSON.stringify({ titel: { a: 1 }, sprache: 7, code: 'x = 1', gedanke: null })],
    ['nur-zaun-gesamt', '```json\n{"titel":"t","code":"a"}\n```'],
    ['lang', JSON.stringify({ titel: 'L'.repeat(200), sprache: 'S'.repeat(50), code: Array.from({ length: 40 }, (_, i) => String(i).padEnd(150, 'x')).join('\n'), gedanke: 'G'.repeat(400) })],
  ];
  for (const [name, antwort] of faelle) {
    st.codeAntwort = antwort;
    const vor = await ev((k) => ({ n: (__stadt.S().ki.tagebuch[k] || []).length, s: { ...__stadt.ki.stat } }), k);
    const vorCalls = st.chat.filter(c => c.art === 'code').length;
    await ev(() => __stadt.ki.codeTag.clear());
    await page.waitForFunction((n) => true, 0);
    const t0 = Date.now();
    while (st.chat.filter(c => c.art === 'code').length === vorCalls && Date.now() - t0 < 15000) await page.waitForTimeout(100);
    await page.waitForFunction(() => !__stadt.ki.laeuft, null, { timeout: 15000 });
    await page.waitForTimeout(100);
    const nach = await ev((k) => ({ n: (__stadt.S().ki.tagebuch[k] || []).length, e: (__stadt.S().ki.tagebuch[k] || []).at(-1), s: { ...__stadt.ki.stat }, f: __stadt.ki.letzterFehler }), k);
    console.log(`  ${name}: Einträge ${vor.n}→${nach.n}, gültig +${nach.s.gueltig - vor.s.gueltig}, ungültig +${nach.s.ungueltig - vor.s.ungueltig}, code +${nach.s.code - vor.s.code}` + (nach.n > vor.n ? '  → ' + JSON.stringify({ titel: nach.e.titel, sprache: nach.e.sprache, text: nach.e.text.slice(0, 60), codeZeilen: nach.e.code.split('\n').length, codeLen: nach.e.code.length, code: nach.e.code.slice(0, 80) }) : '  Fehler: ' + nach.f.slice(0, 80)));
  }
  // einmal pro Spieltag: codeTag nicht anfassen, mehrere Stunden und Takte laufen lassen
  st.codeAntwort = null;
  const vorCalls = st.chat.filter(c => c.art === 'code').length;
  await ev(() => { __stadt.ki.codeTag.clear(); });
  await page.waitForTimeout(3000);
  await ev(() => { const a = __stadt, S = a.S(); for (let i = 0; i < 3; i++) a.schritt(); a.nachSchritten(); });
  await page.waitForTimeout(3000);
  const heute = st.chat.filter(c => c.art === 'code').length - vorCalls;
  ok(heute === 1, `einmal am Tag: ${heute} Code-Aufrufe in mehreren Stunden desselben Tages`);
  await ev(() => { const a = __stadt, S = a.S(); const t = S.tag; while (!(S.tag === t + 1 && S.stunde === 10)) a.schritt(); a.nachSchritten(); });
  await page.waitForTimeout(3000);
  const morgen = st.chat.filter(c => c.art === 'code').length - vorCalls - heute;
  ok(morgen === 1, `nächster Tag: ${morgen} Code-Aufruf`);
  console.log('Konsole:', log.filter(l => !/ERR_CONNECTION_REFUSED/.test(l)).join('\n  ') || 'leer');
  await page.screenshot({ path: U.ordner('bilder_t1') + 't1.png' });
  await b.close();
})().catch(e => { console.error('Testfehler:', e); process.exit(1); });
