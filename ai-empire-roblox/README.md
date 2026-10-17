# AI Empire – Roblox-Tycoon (Arbeitstitel, Vorschlag: „AI Founder Tycoon“)

Du startest in einer Garage und baust eine KI-Firma bis zum großen Hauptquartier auf.

## Welche Datei öffnen?

| Datei | Stand | Geprüft? |
|---|---|---|
| `AIEmpire_Stand_2026-10-17.rbxlx` | 17.10. abends, **neuester geprüfter Stand – nur zum Testen in Studio, noch nicht veröffentlichen** | 145/145 Test-Suites grün im Headless-Mock (239.287 Checks, `projekt/run_all_2026-10-17.txt`), Harness Stufe 0–4 grün, Geschäftsreise-Test mit 2 Spielern 113/0, Roundtrip OK (167 Skripte). Neu: Fahrer + VIP-Limo, Hotelgäste + Firmen-Jet, Geschäftsreisen mit der Assistentin, Anleitung „First steps“ + neues Menü, Robux-Shop (alle IDs noch 0, also nichts kaufbar; Bilder in `shop_bilder/`). Wirtschaft für Nicht-Käufer unverändert (Simulator byte-gleich). Was neu ist und was fehlt: `projekt/RELEASE_NOTES_2026-10-17.md`; Studio-Testliste: `projekt/STUDIO_TESTS_2026-10-17.md`. Noch offen: Speicher-Fixes DS-1 bis DS-4 und R3 (Fix-Paket läuft). In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-11_ki-studio.rbxlx` | 11.10. mittags | 99/99 Test-Suites grün im Headless-Mock (233.105 Checks, `projekt/run_all_2026-10-11_ki-studio.txt`), Roundtrip OK (155 Skripte). Neu: das KI-Studio im Stil von „Build a Phone Empire“ (6 Schritte mit Live-Vorschau, Kosten bei jedem Tipp, geheime Punktzahl, Enthüllung mit Konfetti, Launch Day, Nachfolger) – Bilder in `ki_studio_bilder/`. Wirtschaft unverändert (12/12 Simulationsläufe identisch, `projekt/design/LAB_BALANCE.md`). Außerdem: sichtbares Betriebspersonal entspricht jetzt genau dem bezahlten (CORE_SPEC 5.5), Ticket $700. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-10_abend.rbxlx` | 10.10. abends | 47/47 Test-Suites grün im Headless-Mock (`projekt/run_all_2026-10-10_abend.txt`), Roundtrip OK (141 Skripte). Enthält Mitarbeiter-Alltag (Urlaub, Nachtschicht, Azubis, IT repariert Server), Diensthandy mit KI-Chat, neue Apps, Flughafen innen, Port Meridian mit Menschen und Verkehr, Shuttle mit Piloten, Gästehaus. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-04_geprueft.rbxlx` | 4.10. abends | Älterer Stand, 39/39 Test-Suites grün. |

Der Gesamttest (`run_all`) enthält seit dem 11.10. alle Paket-Suites (Handy, Mitarbeiter-Alltag, Apps, Flughafen, Stadt, Flug, Gästehaus, KI-Studio).

Noch nicht drin (in Arbeit): Speicher- und Sicherheits-Fixes aus zwei Code-Prüfungen (`zwischenstand_in_arbeit/pruefberichte/`), Umbau des Meridian Grand Hotels, neue Flughäfen auf beiden Inseln, bessere Spiel-Logik (Pläne in `zwischenstand_in_arbeit/design/`).

Öffnen: Roblox Studio → File → Open from File → `.rbxlx` auswählen.

`game_description.txt` ist die Spielbeschreibung. Fahrer, Firmenjet und Geschäftsreise sind jetzt drin. Veröffentlichen aber erst nach den Speicher-Fixes und einem Test in Studio.

## Ordner `projekt/` (alles, um weiterzubauen)

- `work/src/` – der komplette Spielcode (Stand 17.10., genau der Code in `AIEmpire_Stand_2026-10-17.rbxlx`; die Test-Suites dazu liegen in `zwischenstand_in_arbeit/tests/`) (Luau, Ordner = Roblox-Struktur: ReplicatedStorage, ServerScriptService, StarterPlayer …)
- `LOGIC_BRIEF.md` – alle Wünsche (1–24) und Entscheidungen
- `design/CORE_SPEC.md` – das verbindliche Wirtschaftsdesign; `design/requests/` – offene Aufgaben zwischen den Paketen
- `notes_integration.md` – Bau-Logbuch
- `tests/`, `harness/` – Headless-Roblox-Mock und Test-Suites (laufen ohne Studio)
- `tools/guiprev`, `tools/blenderprev` – Vorschau-Werkzeuge für UI- und 3D-Bilder
- `agents/stable/pack_stable.py` – baut aus `work/src` wieder eine `.rbxlx`
- `orig.rbxlx/` – die unveränderte Ausgangsdatei

## Was nur Studio prüfen kann

Echte Physik und Kamera-Gefühl, Touch-Bedienung auf dem Handy, Performance auf echten Geräten und der KI-Chat mit eigenen Modellen (Roblox TextGenerator: läuft nur im veröffentlichten Spiel bzw. Team Test; sonst antwortet eine klar markierte Demo).
