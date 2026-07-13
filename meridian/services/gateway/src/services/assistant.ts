// Sprachassistent: natürliche Sprache -> Absicht (Intent) -> Aktion.
// Deterministischer Parser (funktioniert ohne LLM); LLM als optionale Verbesserung.
import type { LonLat, Place, RoutePreference, TravelMode } from '@meridian/shared';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';
import { search } from './search.js';

export interface AssistantContext {
  near?: LonLat;
  from?: Place;
  to?: Place;
  hasRoute?: boolean;
}

export interface AssistantAction {
  type: 'navigate' | 'search' | 'add_stop' | 'set_pref' | 'ui' | 'plan_trip' | 'briefing' | 'report' | 'none';
  place?: Place; // aufgelöstes Ziel/POI
  destinationQuery?: string;
  category?: string;
  alongRoute?: boolean;
  cheapest?: boolean;
  avoid?: string[];
  mode?: TravelMode;
  preference?: RoutePreference;
  ui?: { view?: 'streets' | 'satellite'; threeD?: boolean; streetView?: boolean };
  reportKind?: string;
}

export interface AssistantResult {
  reply: string;
  action: AssistantAction;
}

const CATEGORY: Record<string, string> = {
  supermarkt: 'supermarket', supermarket: 'supermarket', einkaufen: 'supermarket', lebensmittel: 'supermarket',
  tankstelle: 'fuel', tanken: 'fuel', benzin: 'fuel', sprit: 'fuel',
  restaurant: 'restaurant', essen: 'restaurant', imbiss: 'restaurant',
  hotel: 'hotel', übernachten: 'hotel', unterkunft: 'hotel',
  ladestation: 'charging', laden: 'charging', ladesäule: 'charging', strom: 'charging',
  parkplatz: 'parking', parken: 'parking', stellplatz: 'parking',
  café: 'cafe', cafe: 'cafe', kaffee: 'cafe',
  apotheke: 'pharmacy', sehenswürdigkeit: 'attraction', attraktion: 'attraction', aussicht: 'viewpoint',
};

function detectCategory(t: string): string | undefined {
  for (const [word, cat] of Object.entries(CATEGORY)) if (t.includes(word)) return cat;
  return undefined;
}

function detectMode(t: string): TravelMode | undefined {
  if (/\b(rad|fahrrad|velo)\b/.test(t)) return 'bicycle';
  if (/zu fuß|laufen|zu fuss/.test(t)) return 'pedestrian';
  // Wortgrenzen: "bahn" darf nicht in "autobahn" matchen.
  if (/\böpnv\b|\bbahn\b|\bbus\b|\bzug\b|\btram\b|nahverkehr|öffentliche/.test(t)) return 'transit';
  if (/\bauto\b|mit dem auto/.test(t)) return 'auto';
  return undefined;
}

function detectPreference(t: string): { preference?: RoutePreference; avoid?: string[] } {
  const avoid: string[] = [];
  let preference: RoutePreference | undefined;
  if (/ohne autobahn|keine autobahn|autobahn vermeiden|nicht über die autobahn/.test(t)) {
    avoid.push('motorway');
    preference = 'comfortable';
  }
  if (/schnellste|am schnellsten|schnell/.test(t)) preference = 'fastest';
  else if (/angenehm|entspannt|ruhig|bequem/.test(t)) preference = 'comfortable';
  else if (/sparsam|eco|verbrauch|sprit sparen|akku sparen/.test(t)) preference = 'eco';
  else if (/landschaft|schöne strecke|schöner weg|panorama/.test(t)) preference = 'scenic';
  return { preference, avoid: avoid.length ? avoid : undefined };
}

// Zielausdruck nach "nach/zu/zum/zur" extrahieren.
function extractDestination(raw: string): string | undefined {
  if (/nach hause|heim|zuhause/i.test(raw)) return 'Zuhause';
  const m = raw.match(/\b(?:nach|zum|zur|zu|richtung|ziel)\s+(.+)$/i);
  if (!m) return undefined;
  return m[1]
    .replace(/\b(bitte|los|jetzt|ohne autobahn|mit dem (auto|rad|fahrrad)|zu fuß)\b/gi, '')
    .replace(/[.?!]+$/, '')
    .trim();
}

export async function handleCommand(text: string, ctx: AssistantContext = {}): Promise<AssistantResult> {
  const raw = text.trim();
  const t = raw.toLowerCase();
  const { preference, avoid } = detectPreference(t);
  const mode = detectMode(t);

  // UI-Befehle
  const ui: AssistantAction['ui'] = {};
  if (/satellit|luftbild/.test(t)) ui.view = 'satellite';
  if (/straßenkarte|karte anzeigen|normale karte/.test(t)) ui.view = 'streets';
  if (/\b3d\b|drei ?d|schräg/.test(t)) ui.threeD = true;
  if (/\b2d\b|flach|von oben/.test(t)) ui.threeD = false;
  if (/street ?view|straßenansicht|umschauen/.test(t)) ui.streetView = true;
  if (Object.keys(ui).length && !/nach|finde|suche|plan/.test(t)) {
    return { reply: 'Ansicht angepasst.', action: { type: 'ui', ui } };
  }

  // Gefahr melden
  const reportKind = /unfall/.test(t) ? 'accident' : /tier|wild/.test(t) ? 'animal' : /sperrung|gesperrt/.test(t) ? 'closure' : /baustelle/.test(t) ? 'roadworks' : /stau/.test(t) ? 'jam' : undefined;
  if (/(melde|melden|achtung|warnung)/.test(t) && reportKind) {
    return { reply: `Danke, ich prüfe und teile die Meldung (${reportKind}).`, action: { type: 'report', reportKind } };
  }

  // Tagesausflug / Reiseplanung
  if (/tagesausflug|ausflug|reiseplan|plane (mir )?(einen|den) tag|tagestour/.test(t)) {
    return {
      reply: ctx.from && ctx.to ? 'Ich stelle einen Tagesausflug mit Sehenswürdigkeiten, Pausen und Essen zusammen.' : 'Wohin soll der Ausflug gehen? Bitte Start und Ziel setzen.',
      action: { type: 'plan_trip' },
    };
  }

  // Briefing / „wann muss ich los"
  if (/wann.*(los|losfahren|aufbrechen)|muss ich los|briefing|wann sollte ich/.test(t)) {
    return { reply: 'Ich bereite dein Briefing vor.', action: { type: 'briefing' } };
  }

  // Zwischenstopp
  if (/zwischenstopp|zwischenstop|stopp|halt|pause/.test(t)) {
    const category = detectCategory(t) ?? 'restaurant';
    return { reply: `Ich suche einen passenden Zwischenstopp (${labelDe(category)}) auf deiner Route.`, action: { type: 'add_stop', category, alongRoute: true } };
  }

  // Suche nach POI
  if (/finde|suche|zeig|wo ist|wo gibt|nächste[rs]?/.test(t)) {
    const category = detectCategory(t);
    if (category) {
      const alongRoute = Boolean(/auf dem weg|entlang|unterwegs|auf der route|auf der strecke/.test(t) && ctx.hasRoute);
      const cheapest = /günstig|billig|preiswert|am günstigsten/.test(t);
      return {
        reply: `Ich suche ${labelDe(category)}${alongRoute ? ' auf deinem Weg' : ' in der Nähe'}${cheapest ? ' — günstigste zuerst' : ''}.`,
        action: { type: 'search', category, alongRoute, cheapest },
      };
    }
  }

  // Navigation
  if (/bring mich|navigier|route|fahr|nach hause|^nach |zum |zur /.test(t) || /nach\s+\w+/.test(t)) {
    const destQuery = extractDestination(raw);
    if (destQuery) {
      let place: Place | undefined;
      if (destQuery !== 'Zuhause') {
        const results = await search(destQuery, ctx.near, 1);
        place = results[0];
      }
      const dest = destQuery === 'Zuhause' ? 'Hause' : place?.name ?? destQuery;
      const extra = avoid?.includes('motorway') ? ' ohne Autobahn' : '';
      return {
        reply: place || destQuery === 'Zuhause' ? `Route${extra} nach ${dest} wird geplant.` : `Ich konnte „${destQuery}" nicht eindeutig finden — bitte präzisieren.`,
        action: { type: 'navigate', place, destinationQuery: destQuery, preference, avoid, mode },
      };
    }
  }

  // Präferenz allein („nimm die schnellste Route")
  if (preference || mode) {
    return { reply: 'Ich passe deine Routenpräferenz an.', action: { type: 'set_pref', preference, avoid, mode } };
  }

  // Optional: LLM-Feinparsing
  if (config.ai.provider === 'anthropic' && config.ai.anthropicKey) {
    const llm = await llmParse(raw).catch(() => null);
    if (llm) return llm;
  }

  return {
    reply: 'Das habe ich nicht verstanden. Sag z. B. „Bring mich ohne Autobahn nach Köln" oder „Finde den günstigsten Supermarkt auf dem Weg".',
    action: { type: 'none' },
  };
}

function labelDe(cat: string): string {
  const map: Record<string, string> = {
    supermarket: 'einen Supermarkt', fuel: 'eine Tankstelle', restaurant: 'ein Restaurant',
    hotel: 'ein Hotel', charging: 'eine Ladestation', parking: 'einen Parkplatz',
    cafe: 'ein Café', pharmacy: 'eine Apotheke', attraction: 'eine Sehenswürdigkeit', viewpoint: 'einen Aussichtspunkt',
  };
  return map[cat] ?? cat;
}

async function llmParse(text: string): Promise<AssistantResult | null> {
  const res = await fetchJson<{ content: { text: string }[] }>('anthropic', 'https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': config.ai.anthropicKey, 'anthropic-version': '2023-06-01' },
    body: {
      model: config.ai.model,
      max_tokens: 300,
      system:
        'Du bist ein Navigations-Assistent. Antworte NUR mit JSON ' +
        '{"reply":string,"action":{"type":"navigate|search|add_stop|set_pref|ui|plan_trip|briefing|report|none", ...}}.',
      messages: [{ role: 'user', content: text }],
    },
  });
  const txt = res.content?.[0]?.text ?? '';
  const match = txt.match(/\{[\s\S]*\}/);
  if (!match) return null;
  return JSON.parse(match[0]) as AssistantResult;
}
