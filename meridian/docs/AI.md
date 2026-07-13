# KI-Module

Meridian nutzt KI an vier Stellen. Jedes Modul ist ein Adapter; das Sprachmodell
(LLM) ist austauschbar (Standard: Claude), ML-Modelle laufen als eigener Service.

## 1. Routen-Reranking — „schnellste **oder** angenehmste Route“
**Ziel:** Aus N Alternativrouten die beste je nach Nutzerpräferenz wählen und
_erklären_.

**Zweistufig:**
1. **Deterministischer Score** (schnell, transparent, im Gateway):
   ```
   score = w_time · t̂  +  w_traffic · staus  +  w_complexity · manöver
         + w_comfort · (autobahn?, ampeln, kurven)  +  w_weather · risiko
         + w_eco · verbrauch  −  w_scenic · landschaft
   ```
   Gewichte `w_*` aus der gewählten Präferenz (`fastest`/`comfortable`/`eco`/`scenic`)
   und gelernten Nutzer-Vorlieben. Implementiert in
   `services/gateway/src/services/aiRouter.ts` (`scoreRoutes`).
2. **LLM-Erklärung** (optional): kompakter Prompt mit den Score-Faktoren →
   ein bis zwei Sätze Begründung („Route 2 ist 4 Min. länger, aber ohne Stau und
   mit weniger Ampeln — angenehmer bei Regen“). Kein LLM nötig für die _Wahl_,
   nur für die Sprache → funktioniert auch offline/ohne Key.

Später (Roadmap v4+): **Learning-to-Rank** (LambdaMART/GBDT) auf echten
Nutzerentscheidungen; personalisierte Gewichte.

## 2. Natürliche Suche & Sprachbefehle (NLU)
**STT → NLU → Intent → Aktion.**
- **STT:** Whisper (on-device klein, Server groß).
- **NLU:** LLM mit strukturiertem Output (Tool/JSON-Schema):
  ```json
  { "intent": "navigate|search|add_stop|set_pref|show_layer",
    "destination": "…", "constraints": ["wlan","günstig"],
    "mode": "auto", "along_route": true }
  ```
- **Aktion:** Gateway übersetzt Intent in bestehende Endpunkte (`/route`,`/poi`…).
- **Fallback:** Ohne LLM → Regel-/Keyword-Parser für Kernbefehle.

## 3. ETA-Prognose (Live-Ankunftszeiten)
- **Modell:** Gradient-Boosting/temporales NN auf Kanten-Geschwindigkeiten
  (TimescaleDB), Wochentag/Uhrzeit, Wetter, Events.
- **Serving:** eigener `eta`-Service; Gateway kombiniert freie Reisezeit
  (Valhalla) mit Verkehrsfaktor je Kante → realistische ETA + Konfidenz.
- **Kaltstart:** Ohne Historie → Verkehrsfaktor aus Live-Flow.

## 4. Zusammenfassung & Assistenz
- Routen-Briefing, Umgebungs-Erklärungen, POI-Empfehlungen entlang der Route.
- Kontext-Aggregation (Wetter + Verkehr + POIs) → LLM formuliert kurze Ansage.

## Datenschutz bei KI
- Sprach-/Standortdaten möglichst **on-device** verarbeiten; nur nötige, minimierte
  Kontexte an den Server. Prompts enthalten keine dauerhaften Identifikatoren.
- Kein Training auf Nutzerdaten ohne explizites Opt-in; Aggregation
  differential-private (s. `SECURITY.md`).

## Modell-Konfiguration
`AI_PROVIDER` (`anthropic`|`local`|`none`) und `AI_MODEL` in der Env. Bei `none`
werden deterministische Fallbacks genutzt — die App bleibt voll funktionsfähig.
