/**
 * Speicherbegrenzung (Art. 5 Abs. 1 lit. e DSGVO) als Code.
 *
 * Vorher wurde in dieser Anwendung nichts geloescht — kein Vorgang, keine
 * Nachricht, kein abgelaufener Anmelde-Token. Bei einem Produkt, in das
 * Therapeutinnen Verordnungen weiterleiten, heisst das: Gesundheitsdaten
 * liegen unbegrenzt in der Datenbank. Das ist kein Fall fuer eine
 * Datenschutzerklaerung, sondern fehlender Code.
 *
 * Alle Regeln hier sind rein und ohne Datenbank, damit die Grenzfaelle
 * pruefbar sind. Die Fristen sind bewusst Konstanten an einer Stelle: sie
 * stehen so auch im Loeschkonzept, und beides darf nicht auseinanderlaufen.
 *
 * ACHTUNG — die Laengen sind eine fachliche Entscheidung, keine
 * Rechtsauskunft. Sie sind mit Begruendung gewaehlt und im Loeschkonzept
 * dokumentiert, damit eine Anwaeltin sie pruefen und aendern kann, statt
 * sie erst aus dem Code rekonstruieren zu muessen.
 */

const TAG = 86_400_000;

export const FRISTEN = {
  /**
   * Ein Anmelde-Token hat seinen Zweck erfuellt, sobald er eingeloest ist
   * oder ablaeuft. Er verknuepft eine Mailadresse mit einem Zeitpunkt —
   * kein Grund, das aufzuheben.
   */
  anmeldeTokenTage: 1,

  /**
   * Ein abgeschlossener Vorgang mit allem daran: Mailverlauf, Anhangstext,
   * Termine, Ausgang. Drei Monate sind lang genug, um eine Rueckfrage
   * ("was hatten wir da ausgemacht?") zu beantworten, und kurz genug, dass
   * eine Praxis nicht ihr halbes Jahr an Korrespondenz hier liegen hat.
   */
  vorgangTage: 90,

  /**
   * Der WORTLAUT im Protokoll. Das Protokoll ist das Vertrauensversprechen
   * des Produkts ("nachvollziehen, im Wortlaut") und zugleich die
   * sensibelste Tabelle: dort steht der volle Text dessen, was rausging.
   * Deshalb zwei Stufen — erst faellt der Wortlaut weg, der Eintrag selbst
   * bleibt noch, damit nachvollziehbar bleibt, DASS etwas passiert ist.
   */
  protokollWortlautTage: 90,
  protokollTage: 180,

  /**
   * Eine widerrufene Kalenderverbindung. Der Zeiger auf das Geheimnis wird
   * sofort unbrauchbar gemacht; die Zeile bleibt kurz stehen, damit eine
   * Nutzerin nachvollziehen kann, wann sie was getrennt hat.
   */
  widerrufeneVerbindungTage: 30,

  /**
   * Ein Konto, das zwei Jahre lang niemand angefasst hat. Danach ist der
   * Zweck der Verarbeitung erkennbar entfallen. Die Nutzerin wird vorher
   * angeschrieben — Loeschen ohne Vorwarnung waere die schlechtere Sorte
   * Datenschutz.
   */
  kontoRuhendTage: 730,
  kontoVorwarnungTage: 700,
} as const;

function aelterAls(zeitpunkt: Date, tage: number, jetzt: Date): boolean {
  return jetzt.getTime() - zeitpunkt.getTime() > tage * TAG;
}

/** Eingeloest oder abgelaufen, und das lange genug her. */
export function tokenLoeschreif(
  token: { gueltigBis: Date; eingeloestAm: Date | null },
  jetzt: Date,
): boolean {
  const erledigt = token.eingeloestAm ?? token.gueltigBis;
  return aelterAls(erledigt, FRISTEN.anmeldeTokenTage, jetzt);
}

/**
 * Ein Vorgang ist loeschreif, wenn er abgeschlossen ist UND lange genug
 * nichts mehr passiert ist UND keine Frist mehr in der Zukunft liegt.
 *
 * Die letzte Bedingung ist der Grund, warum das hier eine Funktion ist und
 * keine SQL-Zeile: eine Verordnung kann ein Jahr im Voraus eingetragen
 * sein. Ein Vorgang, der laengst 'erledigt' heisst, dessen Termin aber noch
 * bevorsteht, darf nicht verschwinden — sonst kann die Nutzerin im
 * Zweifelsfall nicht mehr nachsehen, woher der Termin in ihrem Kalender
 * kommt.
 */
export function vorgangLoeschreif(
  vorgang: {
    zustand: string;
    geaendertAm: Date;
    faelligAm: Date | null;
  },
  jetzt: Date,
): boolean {
  const abgeschlossen =
    vorgang.zustand === 'erledigt' ||
    vorgang.zustand === 'abgebrochen' ||
    vorgang.zustand === 'fehler';
  if (!abgeschlossen) return false;
  if (vorgang.faelligAm && vorgang.faelligAm.getTime() > jetzt.getTime()) return false;
  return aelterAls(vorgang.geaendertAm, FRISTEN.vorgangTage, jetzt);
}

/** Der Wortlaut faellt weg, der Eintrag bleibt. */
export function protokollWortlautReif(
  eintrag: { zeitpunkt: Date; details: string | null },
  jetzt: Date,
): boolean {
  if (eintrag.details === null) return false;
  return aelterAls(eintrag.zeitpunkt, FRISTEN.protokollWortlautTage, jetzt);
}

/** Und irgendwann auch der Eintrag. */
export function protokollLoeschreif(eintrag: { zeitpunkt: Date }, jetzt: Date): boolean {
  return aelterAls(eintrag.zeitpunkt, FRISTEN.protokollTage, jetzt);
}

export function verbindungLoeschreif(
  verbindung: { widerrufenAm: Date | null },
  jetzt: Date,
): boolean {
  if (!verbindung.widerrufenAm) return false;
  return aelterAls(verbindung.widerrufenAm, FRISTEN.widerrufeneVerbindungTage, jetzt);
}

export type KontoStand = 'aktiv' | 'vorwarnen' | 'loeschreif';

/**
 * Ruhende Konten. `letzteAktivitaet` ist der spaeteste Zeitpunkt, an dem
 * irgendetwas passiert ist — Anmeldung, Mail, Klick. Wer bezahlt, gilt nie
 * als ruhend: ein laufendes Abonnement ist Aktivitaet genug, und ein Konto
 * unter der Hand zu loeschen, fuer das jemand zahlt, waere ein Fehler mit
 * Ansage.
 */
export function kontoStand(
  nutzer: { zahlendSeit: Date | null },
  letzteAktivitaet: Date,
  jetzt: Date,
): KontoStand {
  if (nutzer.zahlendSeit) return 'aktiv';
  if (aelterAls(letzteAktivitaet, FRISTEN.kontoRuhendTage, jetzt)) return 'loeschreif';
  if (aelterAls(letzteAktivitaet, FRISTEN.kontoVorwarnungTage, jetzt)) return 'vorwarnen';
  return 'aktiv';
}
