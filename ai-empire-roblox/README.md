# AI Empire – Roblox-Tycoon (Arbeitstitel, Vorschlag: „AI Founder Tycoon“)

Du startest in einer Garage und baust eine KI-Firma bis zum großen Hauptquartier auf.

## Welche Datei öffnen?

| Datei | Stand | Geprüft? |
|---|---|---|
| `AIEmpire_Stand_2026-10-04_geprueft.rbxlx` | 4.10. abends | 39/39 Test-Suites grün im Headless-Mock, Roundtrip OK. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-10.rbxlx` | 10.10. morgens, **Zwischenstand** | Nur Roundtrip OK (139 Skripte). Die Test-Suites sind auf diesem Stand nicht gelaufen. Mitarbeiter-Alltag, Handy, Apps und die Welt-Fixes sind hier halb fertig. |

Öffnen: Roblox Studio → File → Open from File → `.rbxlx` auswählen.

`game_description.txt` ist die Spielbeschreibung. Erst veröffentlichen, wenn Fahrer, Firmenjet und Geschäftsreise eingebaut sind (Runde 2b), sonst verspricht sie Dinge, die noch fehlen.

## Ordner `projekt/` (alles, um weiterzubauen)

- `work/src/` – der komplette Spielcode (Luau, Ordner = Roblox-Struktur: ReplicatedStorage, ServerScriptService, StarterPlayer …)
- `LOGIC_BRIEF.md` – alle Wünsche (1–24) und Entscheidungen
- `design/CORE_SPEC.md` – das verbindliche Wirtschaftsdesign; `design/requests/` – offene Aufgaben zwischen den Paketen
- `notes_integration.md` – Bau-Logbuch
- `tests/`, `harness/` – Headless-Roblox-Mock und Test-Suites (laufen ohne Studio)
- `tools/guiprev`, `tools/blenderprev` – Vorschau-Werkzeuge für UI- und 3D-Bilder
- `agents/stable/pack_stable.py` – baut aus `work/src` wieder eine `.rbxlx`
- `orig.rbxlx/` – die unveränderte Ausgangsdatei

## Was nur Studio prüfen kann

Echte Physik und Kamera-Gefühl, Touch-Bedienung auf dem Handy, Performance auf echten Geräten und der KI-Chat mit eigenen Modellen (Roblox TextGenerator: läuft nur im veröffentlichten Spiel bzw. Team Test; sonst antwortet eine klar markierte Demo).
