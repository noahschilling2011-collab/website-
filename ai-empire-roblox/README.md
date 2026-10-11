# AI Empire – Roblox-Tycoon (Arbeitstitel, Vorschlag: „AI Founder Tycoon“)

Du startest in einer Garage und baust eine KI-Firma bis zum großen Hauptquartier auf.

## Welche Datei öffnen?

| Datei | Stand | Geprüft? |
|---|---|---|
| `AIEmpire_Stand_2026-10-11_ki-studio.rbxlx` | 11.10. mittags, **neuester geprüfter Stand** | 99/99 Test-Suites grün im Headless-Mock (233.105 Checks, `projekt/run_all_2026-10-11_ki-studio.txt`), Roundtrip OK (155 Skripte). Neu: das KI-Studio im Stil von „Build a Phone Empire“ (6 Schritte mit Live-Vorschau, Kosten bei jedem Tipp, geheime Punktzahl, Enthüllung mit Konfetti, Launch Day, Nachfolger) – Bilder in `ki_studio_bilder/`. Wirtschaft unverändert (12/12 Simulationsläufe identisch, `projekt/design/LAB_BALANCE.md`). Außerdem: sichtbares Betriebspersonal entspricht jetzt genau dem bezahlten (CORE_SPEC 5.5), Ticket $700. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-10_abend.rbxlx` | 10.10. abends | 47/47 Test-Suites grün im Headless-Mock (`projekt/run_all_2026-10-10_abend.txt`), Roundtrip OK (141 Skripte). Enthält Mitarbeiter-Alltag (Urlaub, Nachtschicht, Azubis, IT repariert Server), Diensthandy mit KI-Chat, neue Apps, Flughafen innen, Port Meridian mit Menschen und Verkehr, Shuttle mit Piloten, Gästehaus. In Studio nicht getestet. |
| `AIEmpire_Stand_2026-10-04_geprueft.rbxlx` | 4.10. abends | Älterer Stand, 39/39 Test-Suites grün. |

Der Gesamttest (`run_all`) enthält seit dem 11.10. alle Paket-Suites (Handy, Mitarbeiter-Alltag, Apps, Flughafen, Stadt, Flug, Gästehaus, KI-Studio).

Noch nicht drin (in Arbeit): Fahrer + VIP-Limo, Hotelgäste, Firmenjet, Geschäftsreise (Runde 2b), Tutorial + einfacheres Menü + größerer Robux-Shop (Plan: `projekt/design/ONBOARDING_SPEC.md`), Umbau des Meridian Grand Hotels (Zimmer, Wellness-Etage, Personal). Die HUD-Meldung „Training complete! Overall …“ verrät die Punktzahl noch vor der Enthüllung – wird mit dem Menü-Paket behoben.

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
