# Meridian — Offene Karten- & Navigationsplattform

> Eine vollständige, selbst-hostbare Alternative zu Apple Karten und Google Maps —
> aufgebaut auf offenen Daten (OpenStreetMap), offenem Rendering (MapLibre) und
> moderner KI für Routenplanung, Suche und Sprachsteuerung.

Meridian ist bewusst **daten- und anbieterunabhängig** entworfen: Alle Kernfunktionen
(Karte, Routing, Suche, Offline) laufen ohne einen einzigen proprietären Dienst.
Wo eigene Daten (noch) fehlen — z. B. Echtzeitverkehr oder Satellitenbilder —
dokumentieren wir konkrete, einbindbare Datenquellen und APIs (siehe
[`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md)).

---

## Funktionsumfang

| Bereich | Umsetzung in Meridian |
| --- | --- |
| Eigene interaktive Weltkarte | MapLibre GL + Vektorkacheln aus OpenStreetMap (Dev: OpenFreeMap ohne Key) ✅ |
| Extrem präzises GPS | Client-Sensorfusion + Map-Matching (Valhalla `trace_attributes`), SBAS/RTK-fähig |
| KI-Routenplanung (Auto/Rad/Fuß/ÖPNV) | Valhalla (multimodal) + OpenTripPlanner (GTFS) + KI-Reranking ✅ |
| Echtzeit-Verkehr, Staus, Baustellen, Unfälle | Ingest-Pipeline für TomTom/HERE/MDM + eigenes Floating-Car-Data |
| 3D-Städte & realistische Gebäude | OSM `building`+`height`-Extrusion + Terrarium-Gelände, Kamera-Neigung ✅ |
| Satellitenansicht | Esri World Imagery / Sentinel-2 / MapTiler Satellite (Layer-Umschalter) ✅ |
| Street-View-ähnlich | Mapillary (offene Straßenbilder), Klick-auf-Karte-Viewer ✅ |
| Offline-Karten | PMTiles/MBTiles-Regionen, MapLibre Offline, Routing-Tiles lokal |
| Sprachsteuerung & -führung | STT (Whisper) → NLU (LLM) → Intent; TTS-Ansagen |
| KI wählt schnellste/angenehmste Route | Learned-Ranking + LLM-Erklärung (`ai-router`) |
| Live-Ankunftszeiten | ETA-Modell auf Verkehrs-Zeitreihen (TimescaleDB) |
| Tankstellen/Restaurants/Hotels/Ladesäulen an der Route | Overpass-POIs + Open Charge Map, Korridor-Suche |
| Wetter auf der Strecke | Open-Meteo Sampling entlang der Polyline |
| Tempolimits & Warnungen | OSM `maxspeed` + clientseitige Warnlogik |
| Favoriten & Sammlungen | PostGIS + geräteübergreifende Sync |
| Sync Smartphone/Tablet/PC | Konto-basiert, WebSocket + REST, Last-Writer-Wins/CRDT |
| Design auf Apple-Niveau | Design-Tokens, reduziertes UI, Dark/Light, Haptik |
| Hohe Datenschutzstandards | On-Device-first, E2E für Privatdaten, DSGVO, Differential Privacy |

## Monorepo-Struktur

```
meridian/
├── apps/
│   ├── web/                # React + Vite + MapLibre GL (Karten-Frontend)
│   └── mobile/             # Flutter/React-Native (MapLibre Native) — Struktur & Plan
├── services/
│   └── gateway/            # API-Gateway (Fastify/TS): Routing, Suche, KI, POI, Wetter …
├── packages/
│   └── shared/             # Geteilte TypeScript-Typen & Utilities
├── db/
│   └── migrations/         # PostGIS-Schema (SQL)
├── infra/
│   └── k8s/                # Kubernetes-Manifeste
├── docs/                   # Architektur, Datenquellen, DB, API, Security, Scaling, Roadmap, KI
└── docker-compose.yml      # Lokale Umgebung: Gateway, Postgres/PostGIS, Redis, Valhalla, Photon, Martin
```

## Schnellstart (lokal)

```bash
# 1. Umgebung starten (DB, Cache, Routing, Geocoding, Tile-Server, Gateway)
cd meridian
cp services/gateway/.env.example services/gateway/.env
docker compose up --build

# 2. Web-App
cd apps/web
npm install
npm run dev            # http://localhost:5173  (spricht mit Gateway auf :8090)
```

Das Gateway läuft **auch ohne** externe Routing/Geocoding-Dienste: Fehlt Valhalla
oder Photon, liefern die Services deterministische Fallback-Daten (Luftlinie,
Demo-POIs), sodass die App sofort startklar ist. Für Produktionsdaten die in
[`docs/DATA_SOURCES.md`](docs/DATA_SOURCES.md) beschriebenen Extrakte laden.

### Karten-Ansichten im Web-Client
Oben rechts auf der Karte: **Karte ⇄ Satellit**, **2D ⇄ 3D** (Gebäude-Extrusion +
Gelände-Relief + Kamera-Neigung) und **Street View**. Basiskarte und 3D-Gebäude
kommen im Dev-Modus schlüssellos von OpenFreeMap; Satellit von Esri World Imagery.
Street View nutzt Mapillary — dafür einen kostenlosen Token in
`apps/web/.env` (`VITE_MAPILLARY_TOKEN`) setzen; ohne Token bleiben Karte und 3D
voll nutzbar. Konfiguration: [`apps/web/.env.example`](apps/web/.env.example).

### Konto & Sicherheit
Oben im Panel: **Anmelden**. Vollständiges Konto-System mit E-Mail/Passwort
(scrypt), **Social Login** (Google/Apple/Microsoft, config-gated), **2FA (TOTP)** mit
Backup-Codes, **Passkey/WebAuthn-Flow**, **Geräteverwaltung** mit Fern-Abmeldung,
Auto-Sperre nach Fehlversuchen, **Login-Warnung bei neuem Gerät**, rotierende
Refresh-Tokens mit **Reuse-Detection**, **Sicherheitsprotokoll**, **Datenschutz-
Dashboard** (Berechtigungen einzeln), **E2E-Vault** (WebCrypto, Server sieht nur
Chiffrat), DSGVO-Export und Konto-Löschung. Läuft ohne DB (In-Memory, swap-fähig
gegen `db/migrations/003_accounts.sql`) und ohne externe Krypto-Libs. Details:
[`docs/ACCOUNTS.md`](docs/ACCOUNTS.md).

### Freunde, Live-Standort & Karten-Designs
Über der Karte: **👥 Teilen** und **🎨 Design**.
- **Live-Standort teilen:** Freunde per E-Mail einladen, Live-Position in Echtzeit
  teilen (SSE-Stream, Freunde erscheinen als Marker auf der Karte) oder per Link
  auch mit Nicht-Nutzern (`/v1/share/start` → öffentlicher Code). Backend mit zwei
  Nutzern verifiziert: Freund empfängt die Position live.
- **Eigene Karten-Designs (Premium):** 7 Vorlagen (Nacht, Mono, Retro, Natur,
  Kontrast, Blaupause…) plus eigener Editor (Farbton/Sättigung/Helligkeit/Kontrast/
  Invert) — live angewandt, lokal gespeichert.

### KI-Assistent, Reiseplanung & Gemeinschaft
Unten links auf der Karte: der **Sprachassistent** („🎙 Assistent"). Er versteht
natürliche Befehle per Text **oder Stimme** (Web Speech API, Deutsch) und führt sie aus:

- „Bring mich **ohne Autobahn** nach Köln" → plant die Route und meidet die Autobahn
- „Finde den **günstigsten Supermarkt auf dem Weg**" → Korridor-Suche
- „Plane einen **Zwischenstopp zum Essen**" · „Plane einen **Tagesausflug**"
- „Zeig mir die **Satellitenansicht in 3D**" → steuert die Kartenansicht

Dahinter arbeiten echte Gateway-Endpunkte: `/v1/assistant/command` (Sprache→Absicht),
`/v1/trip/plan` (Tagesausflug mit Sehenswürdigkeiten/Pausen), `/v1/assistant/briefing`
(proaktiver KI-Begleiter), `/v1/reports` (Gefahrenmeldungen mit KI-Glaubwürdigkeits­prüfung),
`/v1/parking` und `/v1/predict/traffic`. Alle laufen ohne LLM-Key (deterministische
Parser/Heuristiken); mit `AI_PROVIDER=anthropic` schaltet sich das Feinverständnis dazu.
Vollständige Einordnung aller Wunschfunktionen: [`docs/FEATURES.md`](docs/FEATURES.md).

## Dokumentation

- [Architektur](docs/ARCHITECTURE.md) · [Datenquellen & APIs](docs/DATA_SOURCES.md)
- [**Erweiterte Funktionen (Feature-Mapping)**](docs/FEATURES.md) · [**Konto & Sicherheit**](docs/ACCOUNTS.md)
- [Datenbank](docs/DATABASE.md) · [API](docs/API.md) · [KI-Module](docs/AI.md)
- [Sicherheit & Datenschutz](docs/SECURITY.md) · [Skalierung](docs/SCALING.md)
- [Entwicklungsplan v1.0 → v10.0](docs/ROADMAP.md)

## Lizenz & Datenlizenzen

Code: MIT. Kartendaten: © OpenStreetMap-Mitwirkende (ODbL) — Namensnennung
erforderlich. Weitere Quellen mit ihren jeweiligen Lizenzen in `docs/DATA_SOURCES.md`.
