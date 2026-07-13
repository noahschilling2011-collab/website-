# Entwicklungsplan v1.0 → v10.0

Jede Version ist auslieferbar. Frühe Versionen liefern echten Nutzen mit offenen
Daten; spätere fügen KI-Tiefe, Realtime und globale Skalierung hinzu.

## v1.0 — Fundament (Karte + Suche + Basis-Routing) — MVP
- Interaktive Vektorkarte (MapLibre + OSM), Zoom/Pan/Rotate, Dark/Light.
- Ortssuche & Reverse-Geocoding (Photon/Nominatim).
- Auto-/Fuß-/Rad-Routing (Valhalla) mit Turn-by-Turn-Liste.
- Standortanzeige (GPS), Favoriten lokal.
- Gateway, Docker-Compose, CI. *(Dieses Repo entspricht v1.0-Basis.)*

## v2.0 — Navigation & Sprachführung
- Aktive Turn-by-Turn-Navigation mit Sprachansagen (TTS).
- Live-ETA (freie Reisezeit), Re-Routing bei Abweichung, Map-Matching.
- Tempolimit-Anzeige & Warnungen (OSM maxspeed).
- Konto + Sync (Favoriten/Verlauf) über Geräte.

## v3.0 — Echtzeitverkehr
- Verkehr-Ingest (offene Feeds + kommerziell), Stau-/Baustellen-/Unfall-Layer.
- Verkehrsbewusstes Routing & realistische ETA.
- Passkeys/WebAuthn, E2E für sensible Favoriten.

## v4.0 — KI-Routenintelligenz
- KI-Reranking (schnellste/angenehmste/eco/scenic) mit Erklärung.
- NL-Suche & Sprachbefehle (STT→LLM-NLU→Aktion).
- Personalisierte Präferenzen (Learning-to-Rank).

## v5.0 — Reichhaltiger Kontext
- Wetter auf der Strecke, POIs entlang der Route (Tankstelle/Restaurant/Hotel).
- Ladesäulen (Open Charge Map) + EV-Routing (Reichweite, Ladestopps).
- Tank-/Ladepreise, Öffnungszeiten, Bewertungen.

## v6.0 — ÖPNV & Multimodal
- Transit-Routing (GTFS + GTFS-RT), Echtzeit-Abfahrten.
- Multimodale Ketten (Fuß→Bahn→Rad/Sharing), Ticketing-Deeplinks.
- GraphQL-Gateway für aggregierte Client-Queries.

## v7.0 — 3D, Satellit, Straßenbilder
- 3D-Städte (Gebäude-Extrusion + Terrain), Satelliten-Layer.
- Street-View-ähnlich (Mapillary), Schilder-/Fahrspur-Anzeige.
- Realistische Landmarken; sanfte 3D-Navigationsansicht.

## v8.0 — Offline & Robustheit
- Offline-Regionen (PMTiles + Offline-Routing + lokale Suche).
- Nahtloser Online/Offline-Wechsel, Hintergrund-Updates.
- Multi-Region-Backend, SLOs, Chaos-Testing.

## v9.0 — Plattform & Ökosystem
- Öffentliche Entwickler-API & SDKs (Web/iOS/Android), API-Keys/Quotas.
- CarPlay/Android Auto, Wear/Watch, Widgets.
- Beitrags-Tools (POI-Korrekturen, Foto-Beiträge → zurück nach OSM/Mapillary).

## v10.0 — Autonome, proaktive Assistenz
- Proaktive KI (Abfahrtsvorschläge, Verzögerungs-Alerts, „jetzt losfahren“).
- Vorhersage-Routing (Verkehr t+30 min), globale Echtzeit-Verkehrsabdeckung.
- Fahrer-Coaching (eco), Flotten-/Business-Funktionen, tiefe AR-Navigation.

---

### Querschnitt (laufend über alle Versionen)
Datenschutz-by-Design · Barrierefreiheit · Performance-Budgets · Test-Abdeckung
· Beobachtbarkeit · Datenqualität (OSM-Feedback-Loop) · Kostenoptimierung.
