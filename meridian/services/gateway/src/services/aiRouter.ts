// KI-Routen-Reranking: deterministischer Score + optionale LLM-Erklärung.
import type { Route, RouteScore, RoutePreference, WeatherSample } from '@meridian/shared';
import { config } from '../config.js';
import { fetchJson } from '../lib/http.js';

// Gewichte je Präferenz. Höheres Gewicht => Faktor zählt stärker negativ
// (außer "scenic", das positiv gewertet wird).
const WEIGHTS: Record<RoutePreference, Record<keyof Omit<RouteScore, 'total'>, number>> = {
  fastest:     { time: 1.0, traffic: 0.6, complexity: 0.1, comfort: 0.1, weatherRisk: 0.2, scenic: 0.0 },
  comfortable: { time: 0.5, traffic: 0.5, complexity: 0.6, comfort: 0.8, weatherRisk: 0.5, scenic: 0.2 },
  eco:         { time: 0.4, traffic: 0.4, complexity: 0.2, comfort: 0.2, weatherRisk: 0.2, scenic: 0.1 },
  scenic:      { time: 0.3, traffic: 0.3, complexity: 0.3, comfort: 0.5, weatherRisk: 0.3, scenic: 1.0 },
};

interface ScoreContext {
  weather?: WeatherSample[];
}

// Normalisiert Routen relativ zueinander und berechnet einen Gesamtscore.
// Niedriger Score = besser.
export function scoreRoutes(routes: Route[], preference: RoutePreference, ctx: ScoreContext = {}): Route[] {
  if (routes.length === 0) return routes;
  const w = WEIGHTS[preference];

  const maxTime = Math.max(...routes.map((r) => r.duration)) || 1;
  const maxManeuvers = Math.max(...routes.map((r) => countManeuvers(r))) || 1;

  const weatherRisk = ctx.weather ? weatherRiskFactor(ctx.weather) : 0;

  for (const r of routes) {
    const timeN = r.duration / maxTime;
    const trafficN = r.freeDuration ? (r.duration - r.freeDuration) / (r.freeDuration || 1) : 0;
    const complexityN = countManeuvers(r) / maxManeuvers;
    const comfortN = comfortPenalty(r);
    const scenicN = scenicBonus(r);

    const score: RouteScore = {
      total: 0,
      time: timeN,
      traffic: Math.max(0, trafficN),
      complexity: complexityN,
      comfort: comfortN,
      weatherRisk,
      scenic: scenicN,
    };
    score.total =
      w.time * score.time +
      w.traffic * score.traffic +
      w.complexity * score.complexity +
      w.comfort * score.comfort +
      w.weatherRisk * score.weatherRisk -
      w.scenic * score.scenic;
    r.score = score;
  }
  return routes;
}

export function pickRecommended(routes: Route[]): number {
  let best = 0;
  for (let i = 1; i < routes.length; i++) {
    if ((routes[i].score?.total ?? Infinity) < (routes[best].score?.total ?? Infinity)) best = i;
  }
  return best;
}

// Kurze Erklärung. Nutzt LLM, wenn konfiguriert; sonst deterministischer Text.
export async function explainRecommendation(
  routes: Route[],
  recommended: number,
  preference: RoutePreference,
): Promise<string> {
  const rec = routes[recommended];
  const facts = routes.map((r, i) => ({
    idx: i,
    minutes: Math.round(r.duration / 60),
    km: +(r.distance / 1000).toFixed(1),
    delayMin: Math.round(((r.duration - (r.freeDuration ?? r.duration)) / 60)),
    maneuvers: countManeuvers(r),
    recommended: i === recommended,
  }));

  if (config.ai.provider === 'anthropic' && config.ai.anthropicKey) {
    try {
      return await llmExplain(facts, preference);
    } catch {
      // Fallback
    }
  }
  const others = routes.length - 1;
  const parts = [
    `Empfohlen: Route ${recommended + 1} (${Math.round(rec.duration / 60)} Min, ${(rec.distance / 1000).toFixed(1)} km)`,
  ];
  if (preference === 'fastest') parts.push('als schnellste Option');
  if (preference === 'comfortable') parts.push('mit den wenigsten Manövern und ruhigerem Verlauf');
  if (preference === 'eco') parts.push('mit gutem Verbrauch/Zeit-Verhältnis');
  if (preference === 'scenic') parts.push('für die landschaftlich reizvollere Strecke');
  if (others > 0) parts.push(`— gegenüber ${others} Alternative(n) bevorzugt.`);
  return parts.join(' ');
}

// -------- Heuristiken --------
function countManeuvers(r: Route): number {
  return r.legs.reduce((n, l) => n + l.maneuvers.length, 0);
}
function comfortPenalty(r: Route): number {
  // mehr Manöver pro km => unkomfortabler
  const km = r.distance / 1000 || 1;
  return Math.min(1, countManeuvers(r) / km / 3);
}
function scenicBonus(r: Route): number {
  // Platzhalter: längere, manöverärmere Strecken gelten als "landschaftlicher".
  const km = r.distance / 1000 || 1;
  return Math.min(1, km / (countManeuvers(r) + 1) / 20);
}
function weatherRiskFactor(w: WeatherSample[]): number {
  if (w.length === 0) return 0;
  const score = w.reduce((s, x) => s + (x.risk === 'high' ? 1 : x.risk === 'moderate' ? 0.5 : 0), 0);
  return score / w.length;
}

async function llmExplain(facts: unknown, preference: RoutePreference): Promise<string> {
  const res = await fetchJson<{ content: { text: string }[] }>(
    'anthropic',
    'https://api.anthropic.com/v1/messages',
    {
      method: 'POST',
      headers: {
        'x-api-key': config.ai.anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: {
        model: config.ai.model,
        max_tokens: 120,
        messages: [
          {
            role: 'user',
            content:
              `Nutzerpräferenz: ${preference}. Routen (JSON): ${JSON.stringify(facts)}. ` +
              `Erkläre in 1-2 kurzen deutschen Sätzen, warum die empfohlene Route passt. Keine Aufzählung.`,
          },
        ],
      },
    },
  );
  return res.content?.[0]?.text?.trim() ?? '';
}
