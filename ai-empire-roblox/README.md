# AI Empire – Roblox-Tycoon (Arbeitstitel, Vorschlag: „AI Founder Tycoon“)

Du startest in einer Garage und baust eine KI-Firma bis zum großen Hauptquartier auf.

## Welche Datei öffnen?

| Datei | Stand | Geprüft? |
|---|---|---|
| `AIEmpire_Stand_2026-10-10_abend.rbxlx` | 10.10. abends, **neuester geprüfter Stand** | 47/47 Test-Suites grün im Headless-Mock (`projekt/run_all_2026-10-10_abend.txt`), Roundtrip OK (141 Skripte). Enthält Mitarbeiter-Alltag (Urlaub, Nachtschicht, Azubis, IT repariert Server), Diensthandy mit KI-Chat, neue Apps, Flughafen innen, Port Meridian mit Menschen und Verkehr, Shuttle mit Piloten, Gästehaus. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-04_geprueft.rbxlx` | 4.10. abends | Älterer Stand, 39/39 Test-Suites grün. |

Hinweis: Der Gesamttest (`run_all`) enthält die eigenen Test-Suites von Handy, Mitarbeiter-Alltag, Apps, Flughafen, Stadt, Flug und Gästehaus noch nicht; die liefen einzeln in ihren Paketen grün. Sie werden im nächsten Schritt in den Gesamttest aufgenommen.

Noch nicht drin (in Arbeit): das neue KI-Studio im Stil von „Build a Phone Empire“ (Entwürfe in `entwurf_ki_studio/`), Fahrer, Hotelgäste, Firmenjet, Geschäftsreise.

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
