# FIX-09 — Was ein JARVIS wirklich braucht

> Noah, 05.09.2026: „mach da Sachen rein, was du denkst, was für einen JARVIS
> richtig wichtig ist" — und: „nenn ihn Mehmet".
> Die Vorschlagsrunde (drei Blickwinkel, zwei Richter) ist am Sitzungslimit
> gescheitert; nur der Blickwinkel *Automatisierung zu Ende denken* kam durch.
> Was hier steht, ist deshalb **meine** Auswahl, mit dieser Begründung: es
> läuft **ohne** die Keys, die Noah nicht hat, und es macht die Zeitpläne aus
> FIX-08 erst wirklich nützlich.

## Das Paket

| # | Was | Warum |
|---|---|---|
| 1 | **Der Assistent heißt Mehmet.** `ASSISTENT_NAME` (Vorgabe `Mehmet`) steht im Titel, in der Kopfzeile, in jedem Reaktor-Text und in jedem Systemprompt (`{name}` in `core/agents.py` und `core/config.py`). Projekt, Code und Doku heißen weiter JARVIS. | Noahs Wunsch. Ein Name, der in HTML und JavaScript landet, wird geprüft: Buchstaben, Ziffern, Leerzeichen, Punkt, Bindestrich, höchstens 40 Zeichen. |
| 2 | **Herkunft im Verlauf.** Tabelle `nachricht_herkunft` (additiv, `messages` bleibt). Was ein Zeitplan angestoßen hat, trägt im Chat „Zeitplan „Morgenlage" hat das angestoßen" bzw. „Ergebnis von „Morgenlage"". Das letzte Ereignis eines Auftrags trägt die Herkunft mit. | Vorher sah ein Auftrag von 07:00 im Chat aus wie etwas, das Noah getippt hat (FIX-08, „Was ein Zeitplan im Verlauf hinterlässt"). |
| 3 | **Zustellung: „seit du weg warst".** Ein Strom, der bei jedem fertigen Zeitplan-Auftrag den Chat neu holt — oder, wenn der Chat nicht offen ist, eine Zahl an den Chat-Tab schreibt. Die zuletzt gesehene Nachricht merkt sich der Browser (`localStorage`, ein Komfort, keine Wahrheit). | Ein Ergebnis, das niemand sieht, ist keins. |
| 4 | **Einmalige Erinnerungen.** Dritte Regelform `einmal 2026-09-06 18:00` (Ortszeit; das Wort „einmal" darf fehlen). Nach dem Lauf ist der Plan aus; verpasst heißt aus; in der Vergangenheit wird abgelehnt. | „Erinnere mich morgen um acht" ist die häufigste Automatisierung überhaupt. |
| 5 | **Erinnerungen aus dem Gespräch:** Werkzeug `erinnerung_anlegen(text, wann)` (LOCAL) beim Chat-Agenten. Legt einen Zeitplan an, dessen Auftrag die Erinnerung ist. Höchstens `MAX_PLAENE = 50` Pläne, egal wer sie anlegt. | JARVIS soll das selbst können, nicht nur das Formular. Ein Modell, das Pläne anlegt, braucht eine Obergrenze. |
| 6 | **Die Bremse.** Spalte `fehlschlaege` (additiv, `scripts/migrate.py` zieht nach). Nach `MAX_FEHLSCHLAEGE = 3` Fehlschlägen in Folge (`failed`, `aborted_budget`) schaltet sich der Plan aus und sagt warum; `done` setzt zurück, „An" auch. | Ein Plan, der jeden Morgen an einem fehlenden Kalender scheitert, verbrennt sonst täglich Planer-Token, und niemand merkt es. |
| 7 | **Wetter ohne Key:** Werkzeug `wetter(ort, tage)` (READ) über Open-Meteo, Doku nachgeschlagen (Endpunkte, Parameter, Wettercodes stehen im Modulkopf von `core/tools/wetter.py`). Deutsche Ausgabe, eine Stunde Cache in `lookups`, Quelle steht dran. `JARVIS_ORT` als Standardort. | Das eine, was jeder Assistent morgens gefragt wird — und Websuche braucht einen Key, den es hier nicht gibt. |
| 8 | **Vorlage „Morgenlage".** `GET /api/zeitplaene/vorlagen` baut den Auftragstext nur aus Bausteinen, die eingerichtet sind (Wetter nur mit `JARVIS_ORT`, Termine nur mit `KALENDER_QUELLE`, Gedächtnis immer) und sagt, was fehlt. Ein Knopf setzt sie ins Formular. | Eine Vorlage, die nach dem Kalender fragt, obwohl es keinen gibt, scheitert jeden Morgen — siehe Punkt 6. |

**Nicht gebaut:** ein Akzent für Mehmet. Noah schrieb „die Sprache mit deinem
Akzent"; ich lese das als „so, wie du mit mir redest" — Deutsch, per du,
direkt. Ein nachgemachter Akzent wäre eine Karikatur, kein Assistent.

## Ausgeführt

```
$ python -m pytest tests/test_fix09.py -p no:randomly -W ignore
36 passed
```

Fünf Tests gegen ihre Mutation geprüft (Schutz raus → Test rot):

```
MUTATION Bremse aus:                 2 failed
MUTATION einmalig laeuft weiter:     2 failed
MUTATION Herkunft nicht geschrieben: 1 failed
MUTATION ohne Obergrenze:            1 failed
MUTATION Name ungeprueft:            2 failed
```

Rauchtest im echten Chromium (uvicorn + FakeLLMProvider, `JARVIS_ORT=Berlin`):

```
1 Titel: Mehmet | Marke: Mehmet | aria: Mehmet ist bereit
2 Vorlage: Name: Morgenlage | Regel: taeglich 07:00
  Ziel: Erstelle meine Morgenlage: das Wetter heute in Berlin (Werkzeug wetter); was du dir ueber …
  Meldung: Vorlage eingesetzt. Enthaelt nur, was eingerichtet ist. Fehlt: Termine: KALENDER_QUELLE …
4 Erinnerung Pillen: ['aktiv', 'einmalig']
5 Zaehler am Chat-Tab: 1 | title: 1 neue Ergebnisse von Zeitplänen seit deinem letzten Blick
6 Herkunft im Chat: ['Zeitplan „Morgenlage“ hat das angestoßen', 'Ergebnis von „Morgenlage“']
  Zaehler weg: True
JS-Fehler: keine
```

Das Wetter-Werkzeug lief **nur gegen einen Mock** (`httpx.MockTransport` mit
den Antwortformen aus der Doku). Ein echter Aufruf gegen Open-Meteo ist in
Tests gesperrt und hier nicht ausgeführt — NICHT AUSGEFÜHRT. Was Noah dafür
tun muss: nichts außer `JARVIS_ORT` eintragen; einen Key gibt es nicht.

## Grenzen, die bleiben

- Eine Erinnerung ist ein Auftrag mit LOCAL-Grenze: sie erscheint im Chat
  (und am Tab), sie klingelt nicht, sie schickt keine Mail.
- „einmal" rechnet in der Ortszeit des Rechners — dieselbe UNSICHER-Note
  wie in FIX-08 (fester Versatz, Zeitumstellung).
- Der Zähler „seit du weg warst" lebt im Browser. Ein anderer Browser
  zählt von vorn.
- Der Wetterbericht rundet Grade auf ganze Zahlen und Regen auf eine
  Nachkommastelle; mehr Genauigkeit gibt der Dienst nicht sinnvoll her.

## Definition of Done

| # | Kriterium | Beleg |
|---|---|---|
| 1 | Name aus `ASSISTENT_NAME` in Seite, Weltlage-Titel und jedem Prompt; unbrauchbare Namen abgelehnt | `test_der_assistent_heisst_mehmet_*`, `test_der_name_steht_in_jedem_prompt`, `test_ein_name_der_die_seite_bricht_wird_abgelehnt` |
| 2 | Zeitplan-Nachrichten tragen Herkunft, getippte nicht; alte Verläufe bleiben lesbar | `test_ein_zeitplan_auftrag_traegt_seine_herkunft`, `test_alte_verlaeufe_bleiben_lesbar` |
| 3 | Fertiger Zeitplan-Auftrag erreicht den Chat live oder als Zahl am Tab | `test_das_letzte_ereignis_traegt_die_herkunft`, Rauchtest 5/6 |
| 4 | `einmal …` läuft genau einmal, dann aus; Vergangenheit abgelehnt; verpasst heißt aus | `test_einmal_*`, `test_die_schleife_fuehrt_eine_erinnerung_genau_einmal_aus` |
| 5 | `erinnerung_anlegen` legt Pläne an, lehnt Unbrauchbares ab, hält `MAX_PLAENE` | `test_erinnerung_anlegen_*`, `test_hoechstens_max_plaene` |
| 6 | Nach 3 Fehlschlägen in Folge pausiert der Plan mit Grund; „An" setzt zurück; Migration ergänzt die Spalte | `test_nach_drei_fehlschlaegen_pausiert_der_plan`, `test_die_bremse_greift_ueber_den_echten_lauf`, `test_migration_ergaenzt_die_fehlschlaege_spalte` |
| 7 | Wetter liefert einen deutschen Bericht, cacht, verrät bei Fehlern nichts | `test_wetter_*` |
| 8 | Vorlage nur aus eingerichteten Bausteinen, über HTTP und in der Oberfläche | `test_vorlage_*` |
