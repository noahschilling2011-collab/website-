// Test-Ollama (KI-Nachbau für tests/p4test.cjs): /api/tags und /api/chat im Format der Ollama-Doku. Kein Sprachmodell.
// tests/alle.sh startet ihn, wenn auf Port 11434 nichts antwortet, und beendet ihn danach per PID. Umschalten per POST /modus.
// MODUS=gut (Standard) | kaputt (kein JSON) | falsch (Aktion nicht erlaubt) | langsam (35 s) | aus (antwortet 500)
// VERZOEGERUNG=ms, PROTOKOLL=datei (jede Anfrage als JSON-Zeile), KI_PORT (Standard 11434; das Spiel fragt immer 11434, ein anderer Port
// dient nur zum Prüfen von tests/alle.sh)
import http from 'node:http';
import fs from 'node:fs';
const PORT = Number(process.env.KI_PORT || 11434), VZ = Number(process.env.VERZOEGERUNG || 600), PROT = process.env.PROTOKOLL;
let modus = process.env.MODUS || 'gut', n = 0;
const erlaubtAus = (sys) => [...sys.matchAll(/^- ([a-z_]+): /gm)].map(m => m[1]);
function antwort(body) {
  const sys = body.messages.find(m => m.role === 'system').content, user = body.messages.find(m => m.role === 'user').content;
  n++;
  if (modus === 'kaputt') return 'Ich denke, ich gehe arbeiten.';
  if (sys.includes('Noah spricht mit dir')) {
    const ehrgeizig = /sehr ehrgeizig|eher ehrgeizig/.test(sys);
    const rat = /laden/i.test(user);
    return JSON.stringify(rat && ehrgeizig ? { antwort: 'Ein eigener Laden? Genau das will ich. Ich fange an zu sparen.', neues_ziel: 'eigener_laden' }
      : rat ? { antwort: 'Ein Laden ist mir zu viel Risiko. Ich bleibe, wo ich bin.', neues_ziel: null }
      : { antwort: `Danke der Nachfrage. (${n})`, neues_ziel: null });
  }
  if (sys.includes('Tagebucheintrag')) return JSON.stringify({ eintrag: 'Während Noah weg war, ist bei mir nicht viel passiert. Ich habe gearbeitet und geschlafen.' });
  const erlaubt = erlaubtAus(sys);
  if (modus === 'falsch') return JSON.stringify({ aktion: 'fliegen', gedanke: 'Ich will fliegen.', neues_ziel: null });
  // Charakter entscheidet: fleißig → Arbeit/Wechsel, gesellig → Freunde, sonst frei
  const vorzug = /sehr fleißig|eher fleißig/.test(sys) ? ['job_suchen', 'job_wechseln', 'laden_gruenden'] :
    /sehr gesellig|eher gesellig/.test(sys) ? ['freunde_treffen', 'partner_suchen'] : ['freinehmen', 'freunde_treffen'];
  const aktion = vorzug.find(a => erlaubt.includes(a)) || erlaubt[n % erlaubt.length];
  if (n % 25 === 0) return '{"aktion": "' + aktion + '", "gedanke": ';        // jede 25. Antwort kaputt (Prüfung testen)
  return JSON.stringify({ aktion, gedanke: `Ich nehme ${aktion}, weil es zu mir passt.`, neues_ziel: n % 7 === 0 ? 'freunde' : null });
}
http.createServer((req, res) => {
  if (modus === 'aus' && req.url !== '/modus') { req.socket.destroy(); return; }   // wie ein beendetes Ollama: Verbindung weg
  const origin = req.headers.origin || '';
  if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {       // wie Ollamas Standard: localhost:* erlaubt
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,HEAD,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Authorization,Content-Type,User-Agent,Accept,X-Requested-With');
    res.writeHead(204); res.end(); return;
  }
  if (req.url === '/modus' && req.method === 'POST') { let b = ''; req.on('data', c => b += c); req.on('end', () => { modus = b.trim(); res.end('ok'); }); return; }
  if (req.url === '/api/tags' && req.method === 'GET') {
    if (modus === 'aus') { res.writeHead(500); res.end(); return; }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ models: [{ name: 'test-modell:latest', model: 'test-modell:latest', size: 1 }] }));
    return;
  }
  if (req.url === '/api/chat' && req.method === 'POST') {
    let b = '';
    req.on('data', c => b += c);
    req.on('end', () => {
      let body;
      try { body = JSON.parse(b); } catch { res.writeHead(400); res.end(JSON.stringify({ error: 'invalid JSON' })); return; }
      if (PROT) fs.appendFileSync(PROT, JSON.stringify(body) + '\n');
      if (modus === 'aus') { res.writeHead(500, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ error: 'aus' })); return; }
      if (body.model !== 'test-modell:latest') { res.writeHead(404, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ error: `model '${body.model}' not found` })); return; }
      if (body.stream !== false || body.format !== 'json' || !Array.isArray(body.messages)) { res.writeHead(400); res.end(JSON.stringify({ error: 'Testserver: unerwartetes Format' })); return; }
      const warten = modus === 'langsam' ? 35000 : VZ;
      setTimeout(() => {
        if (res.destroyed) return;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ model: body.model, created_at: '2026-01-01T00:00:00Z', message: { role: 'assistant', content: antwort(body) },
          done_reason: 'stop', done: true, total_duration: warten * 1e6 }));
      }, warten);
    });
    return;
  }
  res.writeHead(404); res.end();
}).listen(PORT, () => console.log('Test-Ollama auf', PORT, 'Modus', modus));
