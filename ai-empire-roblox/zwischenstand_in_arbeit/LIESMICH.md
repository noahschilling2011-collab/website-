# Zwischenstand in Arbeit (17.10., ca. 12:10 UTC)

Sicherung des Arbeitsstands, damit nichts verloren geht, falls der Cloud-Rechner gelöscht wird oder ein Nutzungslimit die Arbeit stoppt.

## Spielbare Datei
`AIEmpire_Zwischenstand_2026-10-17_runde2b_geprueft.rbxlx` – Runde 2b ist fertig und in der Testumgebung geprüft:
145 Test-Suites grün, Harness grün, End-to-End-Test mit zwei Spielern (Geschäftsreise komplett) 113/0, Roundtrip OK.
Enthalten: Fahrer + VIP-Limo, Hotelgäste + Firmenjet, Geschäftsreise-Planer, neues Menü + Tutorial, Robux-Shop (Stand vor dem Shop-Fix).

Noch nicht drin bzw. noch offen:
- Shop-Fix (Cash-Packs „einmal pro Büro“ jetzt auch serverseitig, Gamepad-Bedienung, zu kleine alte Tabs) – läuft gerade.
- Speicher-Fixes aus der Profi-Prüfung (`pruefberichte/`) – kommen im Fix-Paket.
- Nichts davon ist in Roblox Studio getestet. Studio-Testliste: `pruefberichte/runde2b_STUDIO_TESTS.md`.
- Alle Produkt- und Gamepass-IDs sind 0, im Shop kann man also noch nichts wirklich kaufen.

## Ordner
- `src/`, `tests/`, `design/`, `notes_integration.md`: Arbeitsstand (src ist mitten im Shop-Fix, nicht spielen)
- `design/airports/`, `design/logic2/`: Planung neue Flughäfen + bessere Spiel-Logik (in Arbeit)
- `pruefberichte/`: Profi-Prüfung, Plugin-Review (geprüft), Fix-Pläne, Studio-Testliste
- `plaene/`: Bau-Pläne (Workflow-Skripte)

Die Executive-Limo (Blender) liegt in `../assets/vehicles/executivelimo/`.
