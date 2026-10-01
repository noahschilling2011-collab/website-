// Unterkante der Kennzahlen am Handy quer (und hochkant), Schritt 2 gegen den Stand vorher (stadt.orig.html), Teststadt Seed 2, Tag 200
const U = require('./umgebung.cjs');
const { chromium } = U;
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const datei of ['stadt.orig.html', 'stadt.html']) {
    const zeilen = [];
    for (const [w, h] of [[568, 320], [680, 345], [740, 360], [844, 390], [926, 428], [400, 820]]) {
      const ctx = await b.newContext({ viewport: { width: w, height: h }, hasTouch: true });
      await U.three(ctx);
      await U.fassungUnter(ctx, 'v8');   // stadt.orig.html = Version 8 (Git 31ce452) per git show
      await ctx.route('http://localhost:11434/**', (r) => r.abort());
      const page = await ctx.newPage();
      await page.goto(`${U.HOST}/${datei}?seed=2&tage=200&neu`, { timeout: 600000 });
      await page.waitForTimeout(1500);
      const r = await page.evaluate(() => { const k = document.getElementById('kennzahlen').getBoundingClientRect(); return Math.round(k.bottom); });
      zeilen.push(`${w}×${h}: ${r} px`);
      await ctx.close();
    }
    console.log(datei.padEnd(16), zeilen.join(' | '));
  }
  await b.close();
})();
