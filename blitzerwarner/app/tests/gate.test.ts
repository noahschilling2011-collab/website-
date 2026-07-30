/**
 * Das Länder-Gate. Der Test, der über Bussgeld oder nicht entscheidet.
 *
 * Die wichtigste Prüfung hier ist die Invariante aus B.1:
 * `status !== 'belegt'` erzwingt `modus: 'aus'`. Ein Land, dessen Rechtslage
 * nicht belegt ist, warnt nicht.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { LAENDER_GATE, type LandCode } from '../src/config';
import { bannerFuerLand, brauchtBanner } from '../src/strings';
import { fahrerverbot, landHinweis, warnmodus, warnungErlaubt } from '../src/core/country';

const EINTRAEGE = Object.entries(LAENDER_GATE.LAENDER) as [LandCode, typeof LAENDER_GATE.LAENDER[LandCode]][];

test('DIE INVARIANTE: unbekannte Rechtslage warnt nicht', () => {
  // Die Schwelle liegt bei 'unklar', nicht mehr bei 'belegt'. Der Unterschied:
  // 'strittig' heisst, dass wir die Norm kennen und nur ihre Reichweite
  // umstritten ist — darüber kann der Fahrer entscheiden, wenn man ihm den
  // ungünstigeren Fall nennt. Bei 'unklar' wissen wir gar nichts, und dann
  // gibt es auch nichts vorzulegen.
  for (const [code, e] of EINTRAEGE) {
    if (e.status === 'unklar') {
      assert.equal(
        e.modus, 'aus',
        `${code} hat status 'unklar' und modus '${e.modus}' — was wir nicht wissen, warnt nicht`,
      );
    }
  }
});

test('warnmodus() setzt die Invariante durch, auch gegen die Tabelle', () => {
  // Nicht bloss in der Tabelle vorausgesetzt, sondern in der Funktion
  // erzwungen: Ein neuer Eintrag mit status 'unklar' und vergessenem
  // modus 'aus' darf nicht durchrutschen.
  for (const [code, e] of EINTRAEGE) {
    const modus = warnmodus(code);
    if (e.status === 'unklar') assert.equal(modus, 'aus', code);
    else assert.equal(modus, e.modus, code);
  }
});

test('jedes warnende Land benennt das Fahrerverbot — oder hat keins', () => {
  // Die neue Zusage. Vorher schwieg die App dort, wo dem Fahrer der Betrieb
  // untersagt ist. Jetzt warnt sie und legt ihm die Entscheidung vor — dann
  // muss sie ihm aber auch sagen, worüber er entscheidet.
  for (const [code, e] of EINTRAEGE) {
    if (warnmodus(code) === 'aus') continue;
    if (e.fahrerverbot === 'nein') continue;
    assert.equal(
      e.hinweisBanner, true,
      `${code} warnt, fahrerverbot ist '${e.fahrerverbot}', aber es gibt keinen Banner`,
    );
  }
});

test('fahrerverbot() und warnmodus() sind unabhängig voneinander', () => {
  // Die Trennung, um die es geht: Was die App tut, und was den Fahrer trifft,
  // sind zwei Fragen. Wären sie dasselbe Feld, wäre die Umstellung nicht
  // möglich gewesen, ohne die Rechtslage falsch darzustellen.
  assert.equal(warnmodus('DE'), 'punkt');
  assert.equal(fahrerverbot('DE'), 'ja');

  assert.equal(warnmodus('ES'), 'punkt');
  assert.equal(fahrerverbot('ES'), 'nein');

  // Und ohne bestimmtes Land wissen wir nichts über den Fahrer.
  assert.equal(fahrerverbot(null), 'unklar');
});

test('jeder Eintrag hat eine Begründung und einen Hinweistext', () => {
  for (const [code, e] of EINTRAEGE) {
    assert.ok(e.grund.length > 10, `${code}: grund zu kurz`);
    assert.ok(e.hinweis.length > 20, `${code}: hinweis zu kurz`);
  }
});

test('Quelle und Stand sind angegeben', () => {
  assert.match(LAENDER_GATE.QUELLE, /ADAC/);
  assert.match(LAENDER_GATE.QUELLE, /ohne Gewähr/);
  assert.match(LAENDER_GATE.STAND, /^\d{4}-\d{2}$/);
});

test('unbekanntes Land warnt nicht', () => {
  // Der sichere Standard. Der eine Fehler kostet eine Funktion, der andere
  // ein Bussgeld.
  assert.equal(LAENDER_GATE.FALLBACK_WARNUNG_ERLAUBT, false);
  assert.equal(warnmodus(null), 'aus');
  assert.equal(warnungErlaubt(null), false);
  assert.equal(landHinweis(null), null);
});

test('Deutschland, Schweiz und Österreich warnen — mit Banner', () => {
  // Die Umstellung. § 23 Abs. 1c StVO, § 98a KFG und Art. 57b SVG richten sich
  // an den FAHRZEUGFÜHRER, nicht an die App. Eine solche App zu bauen und
  // anzubieten ist nicht untersagt; untersagt ist dem Fahrer das Betreiben.
  // Die App warnt deshalb und legt ihm die Entscheidung vor.
  for (const code of ['DE', 'CH', 'AT'] as const) {
    assert.equal(warnmodus(code), 'punkt', code);
    assert.equal(warnungErlaubt(code), true, code);
    assert.notEqual(
      fahrerverbot(code), 'nein',
      `${code}: hier trifft den Fahrer sehr wohl ein Verbot oder es ist strittig`,
    );
    assert.equal(
      LAENDER_GATE.LAENDER[code].hinweisBanner, true,
      `${code} warnt trotz Fahrerverbot — ohne Banner wäre das eine Falle`,
    );
  }
});

test('der Hinweis in DE/AT/CH nennt das Verbot und schiebt es nicht weg', () => {
  // Der Text darf weder behaupten, es sei erlaubt, noch verschweigen, wen es
  // trifft. Beides wäre irreführend, und zwar in die teure Richtung.
  for (const code of ['DE', 'CH', 'AT'] as const) {
    const h = LAENDER_GATE.LAENDER[code].hinweis;
    assert.match(h, /untersagt|verbot|widersprechen/i, `${code}: nennt kein Verbot`);
    assert.match(h, /Entscheidung liegt bei dir/, `${code}: sagt nicht, wer entscheidet`);
  }
});

test('die Schweiz nennt den Geräteeinzug, Österreich den Strafrahmen', () => {
  // Nicht alle drei sind gleich teuer. Deutschland: 75 Euro und ein Punkt.
  // Die Schweiz verbietet schon das Mitführen und zieht das Gerät ein.
  // Österreich: bis 10.000 Euro, falls die strengere Lesart zutrifft.
  // Ein gemeinsamer Text für alle drei hätte den Unterschied verwischt.
  assert.match(LAENDER_GATE.LAENDER.DE.hinweis, /75 Euro/);
  assert.match(LAENDER_GATE.LAENDER.CH.hinweis, /Mitführen/);
  assert.match(LAENDER_GATE.LAENDER.CH.hinweis, /eingezogen/);
  assert.match(LAENDER_GATE.LAENDER.AT.hinweis, /10\.000 Euro/);
});

test('Österreich ist als strittig geführt, nicht als belegt', () => {
  // Die Quellen widersprechen sich: bisheriger Projekteintrag sagt verboten,
  // der ADAC beschreibt POI-Warner als erlaubt. Das aufzulösen braucht den
  // Gesetzestext. Bis dahin sichtbar offen halten statt entscheiden.
  const at = LAENDER_GATE.LAENDER.AT;
  assert.equal(at.status, 'strittig');
  // Der Widerspruch bleibt festgehalten — aber er trägt die Entscheidung
  // nicht mehr: Trifft die ADAC-Lesart zu, ist die Warnung erlaubt; trifft
  // die andere zu, ist sie dem Fahrer verboten, und das ist derselbe Fall
  // wie DE und CH. Beide Zweige führen zum selben Verhalten. Offen bleibt
  // allein die Höhe des Risikos, und die nennt der Hinweis.
  assert.equal(at.modus, 'punkt');
  assert.equal(at.fahrerverbot, 'unklar');
  assert.match(at.grund, /WIDERSPRUCH/);
  assert.match(at.grund, /98a KFG/);
  assert.match(at.grund, /ADAC/);
  // Der Hinweis darf nicht behaupten, es sei verboten — nur, dass es unklar
  // ist, und wie teuer der ungünstigere Fall wäre.
  assert.match(at.hinweis, /nicht geklärt|widersprechen/);
});

test('Frankreich läuft im Zonenmodus, nicht mit Punktwarnung', () => {
  // Der teuerste Fehler im Projekt, gemessen in Euro: bis 1500 Euro und
  // Einziehung des Geräts. Punktwarnung ist dort seit 03.01.2012 verboten.
  const fr = LAENDER_GATE.LAENDER.FR;
  assert.equal(fr.status, 'belegt');
  assert.equal(fr.modus, 'zone');
  assert.equal(warnmodus('FR'), 'zone');
  assert.equal(warnungErlaubt('FR'), true, 'gewarnt wird schon, nur anders');
  assert.match(fr.grund, /2012/);
  assert.match(fr.grund, /Gefahrenzonen|Gefahrenzone/);
});

test('kein Land warnt punktgenau, ohne dass die Quelle es hergibt', () => {
  const punktLaender = EINTRAEGE.filter(([, e]) => e.modus === 'punkt').map(([c]) => c);
  // Genau die acht Länder, für die die Quelle die POI-Funktion ausdrücklich
  // erlaubt. Wächst diese Liste, muss jemand die Quelle nachgelesen haben.
  assert.deepEqual(
    [...punktLaender].sort(),
    ['AT', 'BE', 'CH', 'CZ', 'DE', 'ES', 'FI', 'LU', 'NL', 'PT', 'RS'],
  );

  // Die acht ohne Fahrerverbot: Dort gibt die Quelle die POI-Funktion
  // ausdrücklich her. Wächst DIESE Liste, muss jemand die Quelle nachgelesen
  // haben — das ist die eigentliche Zusage dieses Tests.
  const ohneVerbot = punktLaender.filter((c) => fahrerverbot(c) === 'nein');
  assert.deepEqual(
    [...ohneVerbot].sort(),
    ['BE', 'CZ', 'ES', 'FI', 'LU', 'NL', 'PT', 'RS'],
  );
  for (const code of ohneVerbot) {
    assert.equal(LAENDER_GATE.LAENDER[code].status, 'belegt', code);
  }

  // Die drei mit Fahrerverbot warnen bewusst trotzdem — und tragen dafür
  // ausnahmslos einen Banner.
  const mitVerbot = punktLaender.filter((c) => fahrerverbot(c) !== 'nein');
  assert.deepEqual([...mitVerbot].sort(), ['AT', 'CH', 'DE']);
  for (const code of mitVerbot) {
    assert.equal(LAENDER_GATE.LAENDER[code].hinweisBanner, true, code);
  }
});

test('Länder mit Widerspruch benennen ihn, statt ihn aufzulösen', () => {
  for (const code of ['HR', 'RO', 'HU'] as const) {
    const e = LAENDER_GATE.LAENDER[code];
    assert.equal(e.status, 'unklar', code);
    assert.match(e.grund, /WIDERSPRÜCHLICH/, code);
  }
});

test('kein Hinweistext behauptet ein Verbot, wo nur Unklarheit besteht', () => {
  // Der Unterschied zählt: Die App soll nicht behaupten, was sie nicht weiss.
  for (const [code, e] of EINTRAEGE) {
    if (e.status !== 'unklar') continue;
    assert.match(
      e.hinweis, /nicht belegt/,
      `${code}: unklare Rechtslage muss als "nicht belegt" beschrieben werden`,
    );
    assert.ok(
      !/ist verboten|untersagt/.test(e.hinweis),
      `${code}: Hinweis behauptet ein Verbot, obwohl die Lage nur unklar ist`,
    );
  }
});

test('Zonenmodus gibt es nur, wo er auch begründet ist', () => {
  const zonen = EINTRAEGE.filter(([, e]) => e.modus === 'zone').map(([c]) => c);
  assert.deepEqual(zonen, ['FR'], 'Zonenmodus derzeit nur für Frankreich');
});

test('Zonenmodus erlaubt KEINE Punktwarnung', () => {
  // Die Regression, die dieser Test verhindert: warnungErlaubt() liefert für
  // Frankreich true, weil 'zone' ungleich 'aus' ist. Ein Ja/Nein-Gate im
  // Background-Task hätte daraus Punktwarnungen mit Entfernungsansage
  // gemacht — genau das, was in Frankreich seit 03.01.2012 verboten ist
  // (bis 1500 Euro, Einziehung des Geräts).
  //
  // Der Task fragt deshalb warnmodus() und warnt nur bei 'punkt'. Solange
  // Phase C fehlt, wird in Frankreich gar nicht gewarnt — keine Warnung
  // statt einer verbotenen.
  assert.equal(warnmodus('FR'), 'zone');
  assert.notEqual(warnmodus('FR'), 'punkt');

  // warnungErlaubt() bleibt absichtlich true: Es beantwortet die Frage
  // "wird hier überhaupt gewarnt", nicht "wie". Wer entscheidet, WAS
  // ausgegeben wird, muss warnmodus() fragen.
  assert.equal(warnungErlaubt('FR'), true);
});

test('nur der Punktmodus darf eine Entfernung ansagen', () => {
  // Zusammenfassung der Regel als Test, damit sie beim Bauen von Phase C
  // nicht verlorengeht.
  for (const [code, e] of EINTRAEGE) {
    const darfEntfernungAnsagen = warnmodus(code) === 'punkt';
    if (e.modus === 'zone') {
      assert.equal(darfEntfernungAnsagen, false, `${code}: Zone darf keine Entfernung`);
    }
    if (e.modus === 'aus') {
      // TypeScript weiss inzwischen, dass jeder Eintrag mit modus 'aus' auch
      // status 'unklar' hat — die Statusprüfung wäre hier tote Bedingung.
      // Der Test in "DIE INVARIANTE" haelt die Kopplung fest.
      assert.equal(darfEntfernungAnsagen, false, `${code}: darf gar nicht warnen`);
    }
  }
});

// --- Der Banner -----------------------------------------------------------

test('jedes Land mit hinweisBanner hat auch einen Bannertext', () => {
  // Der Banner ist eine rechtliche Anforderung, keine Verzierung. Ein Eintrag
  // mit hinweisBanner: true und ohne Text wäre ein stillschweigend fehlender
  // Hinweis — und genau das war der Zustand, als die UI die drei Ländercodes
  // selbst hartkodiert hatte und bannerFuerLand() toter Code war.
  for (const [code, e] of EINTRAEGE) {
    if (!e.hinweisBanner) continue;
    if (warnmodus(code) === 'aus') continue;
    const banner = bannerFuerLand(code);
    assert.ok(banner !== null, `${code}: hinweisBanner true, aber kein Text in strings.ts`);
    assert.ok(banner.kurz.length > 20, `${code}: Kurztext zu kurz`);
    assert.ok(banner.lang.length > 100, `${code}: Langtext zu kurz`);
  }
});

test('brauchtBanner() liest die Gate-Tabelle und nicht eine eigene Liste', () => {
  for (const [code, e] of EINTRAEGE) {
    assert.equal(brauchtBanner(code), e.hinweisBanner, code);
  }
  assert.equal(brauchtBanner(null), false);
});

test('kein Bannertext behauptet, die Warnung sei abgeschaltet', () => {
  // Sie ist es nicht mehr. Ein Text, der das noch sagt, wäre falsch — und
  // zwar in der Richtung, die den Fahrer in Sicherheit wiegt.
  for (const code of ['DE', 'AT', 'CH'] as const) {
    const banner = bannerFuerLand(code)!;
    for (const text of [banner.kurz, banner.lang]) {
      assert.ok(
        !/abgeschaltet|bleibt hier aus/i.test(text),
        `${code}: Bannertext behauptet noch, die Warnung sei abgeschaltet`,
      );
    }
    assert.match(banner.lang, /Entscheidung liegt bei dir|entscheidest du/);
  }
});
