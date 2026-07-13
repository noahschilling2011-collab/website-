# Erweiterte Funktionen — Engineering-Mapping

Jede Wunschfunktion ist hier einem **Modul**, einer **Datenquelle** und einer
**Reife** zugeordnet:

- ✅ **live** — im Repo lauffähig (Gateway-Endpoint und/oder Web-Client)
- 🟡 **heuristik** — funktionierender Endpoint mit Heuristik; ML-Modell folgt
- 🔵 **design** — Modul-Architektur + Schnittstelle definiert, Implementierung geplant

## Navigation
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Route nach Gewohnheiten | 🟡 | `habits` — Fahrtenhistorie → häufige Ziele/Zeiten; fließt als Gewichte ins KI-Reranking (`aiRouter`) |
| Staus erkennen, bevor sie entstehen | 🟡 | `predict` — `/v1/predict/traffic`: Vorhersage aus Tages-/Wochenmustern (Heuristik), später GBDT/TFT auf TimescaleDB |
| Automatisch bessere Alternativen | ✅ | `aiRouter` reranking + `/v1/assistant` löst Re-Route aus |
| Parkplätze mit hoher Wahrscheinlichkeit | 🟡 | `parking` — `/v1/parking`: OSM-Parkplätze + Belegungs-Heuristik (Tageszeit/Kapazität) |
| Lieblingsstrecken lernen | 🟡 | `habits` — Cluster wiederkehrender Routen; Vorschlag beim Start |

## Kamera + AR
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| AR-Pfeile auf der Straße | 🔵 | `apps/mobile` AR-Modul: ARKit/ARCore, Manöver aus Route → Weltanker; Kamera-Overlay |
| Verkehrszeichen in Echtzeit | 🔵 | On-Device-CV (TFLite/ONNX), Modell: Traffic-Sign-Detection; Vorschau aus **Mapillary**-Detektionen |
| Baustellen/Hindernisse erkennen | 🔵 | CV + Fusion mit `incidents`/Community-Meldungen |
| Schilder lesen & übersetzen | 🔵 | On-Device-OCR → Übersetzung (on-device MT), Fallback Cloud |

> CV-Modelle werden **on-device** ausgeführt (Datenschutz, Latenz). Trainingsdaten
> u. a. aus Mapillary (offene Schild-/Objekt-Detektionen). Schnittstelle:
> `VisionEvent { type, bbox, text?, confidence }` → Navigations-/Warn-Layer.

## Sprachassistent („Jarvis")
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Natürliches Gespräch | ✅ | `assistant` — `/v1/assistant/command`; Web-Client mit STT+TTS (Web Speech API) |
| „Günstigsten Supermarkt auf dem Weg" | ✅ | Intent `search` + `alongRoute` + `cheapest` → Korridor-POI |
| „Zwischenstopp zum Essen" | ✅ | Intent `add_stop` (category=restaurant) |
| „Ohne Autobahn nach Hause" | ✅ | Intent `navigate` + `avoid=[motorway]` + Heim-Ort |

## KI-Reiseplanung
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Komplette Tagesausflüge | ✅ | `trip` — `/v1/trip/plan`: Route + Sehenswürdigkeiten + Essen + Pausen + Hotel |
| Sehenswürdigkeiten entlang der Route | ✅ | `poisAlong('attraction'/'viewpoint')` im Korridor |
| Pausen automatisch berechnen | ✅ | Break-Logik: alle ~2 h Fahrzeit ein Stopp am nächsten geeigneten POI |
| Hotels/Restaurants nach Budget | 🟡 | POI + Budget-Heuristik (Preisklasse/`stars`); echte Preise via Partner-API |

## Auto
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Fahrstil erkennen | 🔵 | `vehicle` — IMU/OBD-Telemetrie → Fahrstil-Klassifikation (on-device) |
| Kraftstoff/Akku sparen | 🟡 | `eco`-Präferenz im `aiRouter` (Verbrauchsmodell), EV-Reichweite (Roadmap v5) |
| Vor gefährlichen Kurven warnen | 🔵 | OSM-Geometrie → Krümmungsanalyse; Warnung nach Geschwindigkeit |
| Schlaglöcher erkennen & melden | 🔵 | IMU-Anomalie (Beschleunigung z) → anonyme Meldung an `reports` |

## Gemeinschaft
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Freunde live teilen / Standortfreigabe | ✅ | `social` — `/v1/friends`, `/v1/share/start`, SSE `/v1/live/stream`; Freunde-Marker live auf der Karte |
| Standortfreigabe per Link (auch für Nicht-Nutzer) | ✅ | `/v1/share/start` → Code/Link; öffentlich `/v1/live/share/:code` |
| Gruppenreisen | 🔵 | Gruppen-Datenmodell + geteilte Live-Positionen (Erweiterung von `social`) |
| Gefahren per Sprache melden | ✅ | `reports` — `/v1/reports` POST; Assistant-Intent `report` |
| KI prüft Glaubwürdigkeit | ✅ | `scoreCredibility`: Korroboration (k nahe Meldungen), Reputationsgewicht, Alter, optionale LLM-Plausibilität |
| Live-Infos (Unfall/Tier/Sperrung) | ✅ | `/v1/reports?bbox=` liefert aktive, glaubwürdige Meldungen als Layer |
| Bewertungen / Fotos von Orten | 🔵 | POI-Bewertungen + Foto-Upload (Object Storage) — Roadmap |

## Zukunft
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Drohnen-Navigation | 🔵 | 3D-Korridor-Routing (Höhe, No-Fly-Zonen); Kosten-Modell in Valhalla-Erweiterung |
| Autonome Fahrzeuge | 🔵 | HD-Maps (Lanelet2), präzise Lokalisierung, Fahrspur-Routing; separates `av-routing` |
| Indoor-Navigation | 🔵 | IMDF/OGC-Indoor-Daten, BLE/UWB-Positionierung; Indoor-Tiles + Routing-Graph |
| Offline ohne Internet | 🔵→v8 | PMTiles + Offline-Valhalla-Tiles + lokaler Suchindex; nahtloser Wechsel |

## Premium
| Funktion | Reife | Modul / Umsetzung |
| --- | --- | --- |
| Eigene Karten-Designs | ✅ | `Design`-Panel: 7 Vorlagen (Nacht/Mono/Retro/Natur/…) + eigene Regler (Farbton/Sättigung/Helligkeit/Kontrast/Invert), live auf die Karte, lokal gespeichert |
| Proaktives Briefing („In 15 Min. losfahren …") | 🟡 | `/v1/assistant/briefing`: ETA + Verkehr/Vorhersage + Parkplatz + (opt.) Kalender → Handlungsempfehlung + vorbereitete Route |
| Erweiterte KI / weltweite Offline-Karten / unbegrenzter Cloud-Speicher | 🔵 | Tarif-Gating + Feature-Flags; Offline = v8 (PMTiles-Regionen) |
| Frühzeitiger Zugriff auf neue Funktionen | 🔵 | Feature-Flags pro Konto (Beta-Kanal) |

**Beispiel-Antwort** (`/v1/assistant/briefing`):
> „Du musst in 15 Minuten losfahren, sonst kommst du wegen eines Unfalls auf der
> A8 zu spät. Ich habe die schnellste Route (42 Min.) vorbereitet und einen
> Parkplatz 200 m vom Ziel gefunden (Belegung ~ niedrig)."

Kombiniert `predict` (Verkehr), `parking` (Stellplatz), `aiRouter` (Route) und
`habits` (typische Abfahrt) — Kalender-Anbindung optional und opt-in.

## Datenschutz-Leitplanken für diese Funktionen
Gewohnheiten, Fahrstil und Telemetrie werden **on-device** gelernt; nur aggregierte,
anonymisierte Signale (Verkehr, Schlaglöcher, Gefahren) verlassen das Gerät — mit
den in [`SECURITY.md`](SECURITY.md) beschriebenen Anonymisierungen (Trip-Chopping,
k-Anonymität, Differential Privacy).
