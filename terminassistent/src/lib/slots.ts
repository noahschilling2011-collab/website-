import type { Arbeitszeiten } from '../db/schema';
import { verschmelze } from './calendar/ics';
import type { BusyInterval, SourceCapabilities } from './calendar/types';
import { datumInZone, lokalZuUtc, parseUhrzeit } from './zeit';

export interface SlotAnfrage {
  von: Date;
  bis: Date;
  dauerMinuten: number;
  arbeitszeiten: Arbeitszeiten;
  zeitzone: string;
  /** Puffer vor und nach bestehenden Terminen, in Minuten. */
  pufferMinuten?: number;
  /** Fruehestens so viel Vorlauf, damit niemand in 20 Minuten anreisen muss. */
  vorlaufStunden?: number;
  /** Raster, auf dem Slots beginnen duerfen. 15 = viertelstuendlich. */
  rasterMinuten?: number;
  jetzt?: Date;
}

export interface Slot {
  start: Date;
  ende: Date;
}

/**
 * Freie Slots aus Belegtzeiten und Arbeitszeiten.
 *
 * Der interessante Teil ist `capabilities.maxStalenessSeconds`: bei einem
 * gepollten ICS-Feed sind die Belegtzeiten so alt wie der letzte Abruf.
 * Ein Slot, der genau in dieser Zeitspanne belegt worden sein koennte,
 * darf nicht vorgeschlagen werden — sonst schlaegt die App Termine vor,
 * die laengst weg sind. Beim Wechsel auf OAuth faellt der Wert auf 0 und
 * dieselbe Funktion wird ohne Codeaenderung praeziser.
 */
export function freieSlots(
  belegt: BusyInterval[],
  anfrage: SlotAnfrage,
  capabilities: SourceCapabilities,
): Slot[] {
  const jetzt = anfrage.jetzt ?? new Date();
  const puffer = (anfrage.pufferMinuten ?? 0) * 60_000;
  const raster = (anfrage.rasterMinuten ?? 15) * 60_000;
  const dauer = anfrage.dauerMinuten * 60_000;

  // Die zwei Untergrenzen: menschlicher Vorlauf und Datenalter.
  const vorlauf = (anfrage.vorlaufStunden ?? 24) * 3_600_000;
  const alterspuffer = capabilities.maxStalenessSeconds * 1000;
  const fruehestens = new Date(jetzt.getTime() + Math.max(vorlauf, alterspuffer));

  const start = new Date(Math.max(anfrage.von.getTime(), fruehestens.getTime()));
  if (start.getTime() >= anfrage.bis.getTime()) return [];

  const gesperrt = verschmelze(
    belegt.map((b) => ({
      start: new Date(b.start.getTime() - puffer),
      end: new Date(b.end.getTime() + puffer),
      source: b.source,
    })),
  );

  const slots: Slot[] = [];
  for (const fenster of arbeitsfenster(start, anfrage.bis, anfrage)) {
    let zeiger = aufRaster(Math.max(fenster.start.getTime(), start.getTime()), raster);
    while (zeiger + dauer <= fenster.ende.getTime()) {
      const ende = zeiger + dauer;
      const kollision = gesperrt.find(
        (b) => b.start.getTime() < ende && b.end.getTime() > zeiger,
      );
      if (kollision) {
        // Direkt hinter die Kollision springen statt Raster fuer Raster.
        zeiger = aufRaster(kollision.end.getTime(), raster);
        continue;
      }
      slots.push({ start: new Date(zeiger), ende: new Date(ende) });
      zeiger += raster;
    }
  }
  return slots;
}

/**
 * Aus vielen freien Slots die Vorschlaege waehlen, die man einem Menschen
 * schickt.
 *
 * Zwei Regeln, beide aus der Empfaengersicht:
 *
 *  1. Hoechstens einer pro Tag. Drei Termine am selben Vormittag sind fuer
 *     den Empfaenger ein Vorschlag, nicht drei.
 *  2. Verschiedene Tageszeiten. Immer den fruehesten Slot zu nehmen, ergibt
 *     "Montag 8:00, Dienstag 8:00, Mittwoch 8:00" — das wirkt maschinell und
 *     trifft niemanden, dem der Morgen nicht passt. Die Auswahl wandert
 *     deshalb ueber den Tag: frueh, Mitte, spaet.
 */
export function waehleVorschlaege(slots: Slot[], anzahl: number, zeitzone: string): Slot[] {
  const proTag = new Map<string, Slot[]>();
  for (const slot of slots) {
    const d = datumInZone(slot.start, zeitzone);
    const schluessel = `${d.jahr}-${d.monat}-${d.tag}`;
    const liste = proTag.get(schluessel);
    if (liste) liste.push(slot);
    else proTag.set(schluessel, [slot]);
  }

  const tage = [...proTag.values()].slice(0, anzahl);
  return tage.map((slotsDesTages, i) => {
    // i=0 -> Anfang, letzter -> Ende, dazwischen gleichmaessig verteilt.
    const anteil = tage.length === 1 ? 0 : i / (tage.length - 1);
    const position = Math.round(anteil * (slotsDesTages.length - 1));
    return slotsDesTages[position]!;
  });
}

/** Die Arbeitszeitfenster als UTC-Instants, Tag fuer Tag. */
function arbeitsfenster(
  von: Date,
  bis: Date,
  anfrage: SlotAnfrage,
): { start: Date; ende: Date }[] {
  const fenster: { start: Date; ende: Date }[] = [];
  const zone = anfrage.zeitzone;

  // Einen Tag Vorlauf, damit ein Fenster, das ueber Mitternacht UTC
  // beginnt, nicht verlorengeht.
  let cursor = new Date(von.getTime() - 86_400_000);
  const ende = new Date(bis.getTime() + 86_400_000);
  const gesehen = new Set<string>();

  while (cursor.getTime() <= ende.getTime()) {
    const d = datumInZone(cursor, zone);
    const schluessel = `${d.jahr}-${d.monat}-${d.tag}`;
    if (!gesehen.has(schluessel)) {
      gesehen.add(schluessel);
      for (const spanne of anfrage.arbeitszeiten[String(d.wochentag)] ?? []) {
        const a = parseUhrzeit(spanne.von);
        const b = parseUhrzeit(spanne.bis);
        const start = lokalZuUtc(d.jahr, d.monat, d.tag, a.stunde, a.minute, zone);
        const schluss = lokalZuUtc(d.jahr, d.monat, d.tag, b.stunde, b.minute, zone);
        if (schluss.getTime() > von.getTime() && start.getTime() < bis.getTime()) {
          fenster.push({ start, ende: schluss });
        }
      }
    }
    cursor = new Date(cursor.getTime() + 86_400_000);
  }
  return fenster.sort((x, y) => x.start.getTime() - y.start.getTime());
}

function aufRaster(zeit: number, raster: number): number {
  return Math.ceil(zeit / raster) * raster;
}
