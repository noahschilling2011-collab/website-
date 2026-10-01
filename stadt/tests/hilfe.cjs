// Gemeinsame Hilfen: Chromium, Three.js per Route, Ollama-Attrappe per Route (Antwort per Funktion steuerbar)
const U = require('./umgebung.cjs');
const { chromium } = U;
// Teststand der KI-Code-Tests in der Version dieser Datei und seine Hauptfigur: von tests/basis.cjs erzeugt (Seed 2, Tag 420, über „Stadt
// übernehmen“ bis 10; bis Version 9 hieß er basis_v9.json)
const BASIS = U.basis('basis_v10.json'), INFO = U.basis('basis_info.json');
async function starte(opt = {}) {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await b.newContext({ viewport: opt.viewport || { width: 1280, height: 800 } });
  await U.three(ctx);
  const st = { modus: opt.modus || 'ok', chat: [], codeAntwort: opt.codeAntwort || null, verzoegerung: 0, aus: !!opt.aus };
  await ctx.route('http://localhost:11434/**', async (route) => {
    const req = route.request(), url = req.url(), h = { 'Access-Control-Allow-Origin': req.headers()['origin'] || '*', 'Content-Type': 'application/json' };
    if (st.aus) return route.abort('connectionrefused');
    if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: { ...h, 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'POST, GET' } });
    if (url.endsWith('/api/tags')) return route.fulfill({ status: 200, headers: h, body: JSON.stringify({ models: [{ name: 'attrappe:latest' }] }) });
    if (url.endsWith('/api/chat')) {
      const body = JSON.parse(req.postData()), sys = body.messages[0].content;
      const art = sys.includes('Stück Code') ? 'code' : sys.includes('Wähle genau eine') ? 'entscheidung' : sys.includes('Noah spricht') ? 'gespraech' : 'tagebuch';
      st.chat.push({ art, sys, user: body.messages[1].content, zeit: Date.now() });
      let content;
      if (art === 'code') {
        if (st.verzoegerung) await new Promise(r => setTimeout(r, st.verzoegerung));
        content = typeof st.codeAntwort === 'function' ? st.codeAntwort(st) : st.codeAntwort !== null ? st.codeAntwort
          : JSON.stringify({ titel: 'Akku-Anzeige', sprache: 'JavaScript', code: "function akku(p) {\n  return p + ' %';\n}", gedanke: 'Die Anzeige muss gut lesbar sein.' });
      } else if (art === 'entscheidung') { const e = [...sys.matchAll(/^- ([a-z_]+): /gm)].map(m => m[1]); content = JSON.stringify({ aktion: e[0], gedanke: 'Ich mache erst mal weiter.', neues_ziel: null }); }
      else content = JSON.stringify({ antwort: 'Hallo.', neues_ziel: null, eintrag: 'Nichts Besonderes.' });
      try { return await route.fulfill({ status: 200, headers: h, body: JSON.stringify({ model: 'attrappe:latest', message: { role: 'assistant', content }, done: true }) }); }
      catch { return; }
    }
    return route.fulfill({ status: 404, headers: h, body: '{"error":"nicht gefunden"}' });
  });
  const page = await ctx.newPage();
  const log = [], dialoge = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) log.push(m.type() + ': ' + m.text()); });
  page.on('pageerror', e => log.push('pageerror: ' + e.message));
  page.on('dialog', d => { dialoge.push(d.message()); d.dismiss().catch(() => {}); });
  return { b, ctx, page, st, log, dialoge, ev: (f, a) => page.evaluate(f, a) };
}
// Spielstand in localStorage legen, bevor die Seite lädt (zuletztGelaufen = jetzt, damit kein Aufholen)
async function mitStand(ctx, text, jetzt = true) {
  const d = JSON.parse(text); if (jetzt) d.zuletztGelaufen = Date.now(); d.tempo = 0;
  await ctx.addInitScript((t) => { try { if (!sessionStorage.getItem('gesetzt')) { localStorage.setItem('stadt-save-v1', t); sessionStorage.setItem('gesetzt', '1'); } } catch {} }, JSON.stringify(d));
}
module.exports = { starte, mitStand, BASIS, INFO };
