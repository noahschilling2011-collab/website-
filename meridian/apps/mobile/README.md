# Meridian Mobile (iOS / Android / Tablet)

Die mobile App teilt sich API & Design-Tokens mit dem Web-Client und rendert mit
**MapLibre Native**. Empfohlener Stack: **Flutter** (`maplibre_gl`) oder
**React Native** (`@maplibre/maplibre-react-native`) — ein Codebase für iOS,
Android und Tablet.

## Geplante Struktur (Flutter-Variante)

```
apps/mobile/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── api/            # Gateway-Client (identische Endpunkte wie Web)
│   │   ├── location/       # GPS-Fusion: GNSS + IMU + Map-Matching (Kalman)
│   │   ├── offline/        # PMTiles-Download, Offline-Routing-Tiles
│   │   ├── voice/          # STT (Whisper) + TTS-Ansagen
│   │   └── theme/          # Design-Tokens (Apple-Niveau, Dark/Light)
│   ├── features/
│   │   ├── map/            # MapLibre-View, 3D-Kamera, Layer-Umschalter
│   │   ├── search/         # Typeahead + NL-Suche
│   │   ├── navigate/       # Turn-by-Turn, Sprachführung, Re-Routing
│   │   ├── favorites/      # Favoriten & Sammlungen (Sync)
│   │   └── settings/       # Datenschutz-Schalter, Konto, Einheiten
│   └── sync/               # Delta-Sync über REST + WebSocket
└── pubspec.yaml
```

## Kernpunkte
- **Präzises GPS:** Fusion aus GNSS (Dual-Frequency/SBAS wo verfügbar),
  Beschleunigung/Kompass und Kartenzuordnung; Kalman-Glättung. Roh-Fixes
  werden lokal verarbeitet, nur aggregiert (opt-in) übertragen.
- **Offline:** Regionen als PMTiles + Offline-Routing; nahtloser Wechsel.
- **Sprachführung:** TTS-Manöveransagen; Sprachbefehle über `/v1/voice/command`.
- **Sync:** dieselben Konto-Endpunkte wie Web (`/v1/favorites`, `/v1/sync`).
- **Plattform-Integrationen (Roadmap v9):** CarPlay, Android Auto, Widgets, Watch.

> Dieses Verzeichnis enthält vorerst nur die Architektur-Skizze. Der Web-Client
> (`apps/web`) ist die Referenz-Implementierung der UI- und API-Muster.
