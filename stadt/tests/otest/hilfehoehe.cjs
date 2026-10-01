// Misst die Hilfe bei 1280×800: Höhe, scrollHeight/clientHeight und Zeilen je Legendenpunkt
const H = require('./h.cjs');
(async () => {
  const b = await H.start();
  const s = await H.seite(b, { viewport: { width: 1280, height: 800 } }, { warten: false });
  const r = await s.page.evaluate(() => { const d = document.getElementById('hilfe-dialog'); d.showModal();
    const zeilen = [...d.querySelectorAll('.legende li span, dd, p.leise')].map(e => { const lh = parseFloat(getComputedStyle(e).lineHeight) || 20; return [Math.round(e.getBoundingClientRect().height / lh), e.innerText.slice(0, 50)]; });
    return { sh: d.scrollHeight, ch: d.clientHeight, h: Math.round(d.getBoundingClientRect().height), zeilen }; });
  console.log(JSON.stringify(r, null, 0));
  const ok = r.sh <= r.ch;                                   // die Hilfe passt ohne Scrollen
  console.log(`${ok ? 'OK' : 'FEHL'} Hilfe bei 1280 × 800 ohne Überlauf: ${r.sh} von ${r.ch} px`);
  await b.close();
  process.exit(ok ? 0 : 1);
})();
