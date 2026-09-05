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
36 passed        (nach der Prüfrunde unten: 50)
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

## Prüfrunde — drei Blickwinkel, 23 Rohfunde, 23 behoben, ein Nachtrag

Drei Prüfer (Name, Herkunft/Zustellung, Erinnerungen), jeder gegen den
laufenden Code mit eigenen Belegläufen. Die Skeptiker-Stufe ist wieder am
Sitzungslimit gescheitert; jeder Fund wurde deshalb selbst nachgestellt und
gegen einen eigenen Test gehalten (`test_r_*` in `tests/test_fix09.py`),
sieben davon gegen Mutation. Was **nicht** stimmte, steht dabei.

| # | Fund | Was jetzt gilt |
|---|---|---|
| N1 | **hoch** — Planner- und Abschluss-Prompt sagten weiter „JARVIS": 2 von 3 Modellaufrufen je Auftrag. | `{name}` auch in `core/planner.py` und `core/runner.py`. Dabei brach `PLANNER_MARKER` mit `{name}` drin die `startswith`-Fakes in test_bugs01/test_fix03 (erst die volle Suite hat es gezeigt): beide Marker sind jetzt **namensfrei** und stehen vorn, der Name folgt dahinter (`ABSCHLUSS_NAME`). `test_r_der_name_steht_auch_im_planer_und_im_abschluss`, `test_r_der_fake_erkennt_den_planer_weiter` |
| N2 | index.html: Gedächtnis-Überschrift, Leertext, Auftrag-Platzhalter nannten „JARVIS". | Alle Nutzertexte über die Konstante `NAME`; die vier verbliebenen Treffer sind Kommentare. Rauchtest 1 |
| N3 | globus.js: Weltlage-Kopf und drei Statustexte „JARVIS", Tab-Titel „Mehmet · Weltlage". | `opt.name` aus weltlage.html, `__NAME__` im Markup, Texte über `assistentName` |
| N4 | Werkzeugbeschreibung `erinnerung_anlegen` nannte den Ausführenden „JARVIS" — direkt nach „Du bist Mehmet". | Beschreibung namensfrei. `test_r_belege_und_werkzeugtexte_sind_namensfrei` |
| N5 | `core/belege.py`: „JARVIS hängt nur Quellen an …" stand wörtlich in der Chat-Antwort. | Markierung namensfrei |
| N6 | Umlaut-Namen in NFD-Form (Basisbuchstabe + Kombinationszeichen) abgelehnt. | NFC-Normalisierung vor der Prüfung |
| N7 | `ASSISTENT_NAME=` (leer) in der .env: pydantic-Traceback statt Vorgabe. | leer = Mehmet. **Mutation:** Ersetzung raus → 1 failed |
| N8 | .env in cp1252 mit Umlaut im Namen: nackter `UnicodeDecodeError` ohne Hinweis auf die Datei. | `get_settings()` fängt ihn und sagt, dass die .env UTF-8 sein muss — ohne Pfad |
| H1 | **hoch** — Zustell-Strom baute den Chat neu, während ein eigener Auftrag lief: Rückfrage weg, Antwort nie gezeigt. | Zustellung wartet, solange `busy`; wird in `setBusy(false)` nachgeholt. Rauchtest 6 |
| H2 | `set_herkunft` im `finally` von `starte_task` ungeschützt: ein Fehler ließ den Task ewig „laufen" und sperrte alle Zeitpläne bis zum Neustart. | Jeder Nachlauf einzeln abgesichert. `test_r_ein_fehler_beim_nachlauf_laesst_den_task_nicht_ewig_laufen` |
| H3 | Dritter Dauerstrom: zwei Verbindungen je Tab, drei Tabs erreichen Chromiums Limit von sechs — danach hängt jeder API-Aufruf. | **Ein** Strom je Seite (`stromAbonnieren`), alle vier Verbraucher hängen daran. `test_beim_verlassen_gehen_uhr_und_strom_aus` zählt genau eine `/api/events`-Verbindung |
| H4 | Zustell-Strom gab nach ~61 s Störung still auf und kam nie wieder. | Neustart bei `visibilitychange`, `online` und Ansichtswechsel |
| H5 | Nachricht und Herkunft in zwei Transaktionen: scheiterte die zweite, stand der Zeitplan-Auftrag als getippte Nachricht ohne Antwort im Verlauf. | `add_message(..., herkunft)` schreibt beides in einer Sitzung. `test_r_nachricht_und_herkunft_in_einer_transaktion` |
| H6 | Ohne localStorage zählte der Tab bei jedem Laden **alle** bisherigen Zeitplan-Antworten als neu. | Unbekannt = noch nichts gesehen: `gelesenBis()` gibt `null`, das erste Laden merkt sich die letzte Nachricht im Speicher der Seite — gezählt wird ab dem Laden |
| H7 | Zweiter Tab zählte per DOM+1 hoch, obwohl der erste die Nachricht schon als gelesen gemerkt hatte. | Zählung vom Server (`/api/messages` gegen `gelesenBis`), nicht DOM+1 |
| E1 | **hoch** — Fällige Erinnerung wurde bei jedem Hindernis (Anbieter, Deckel, anderer Lauf) verbraucht, ohne zu laufen — und war endgültig weg. | Bei einmaligen Plänen wird das Hindernis **vor** `termin_weiter` geprüft; Erinnerungen brauchen ohnehin kein Modell mehr. `test_r_eine_faellige_erinnerung_wird_nicht_vom_hindernis_verbraucht` |
| E2 | Der Erinnerungstext lief wörtlich als unbeaufsichtigter LOCAL-Auftrag: konnte `remember`, `datei_lesen` und `erinnerung_anlegen` rufen und sich selbst fortpflanzen. | Spalte `art` (`auftrag`/`erinnerung`). Eine Erinnerung wird **ohne Modell** zugestellt: Nachricht „Erinnerung: …" mit Herkunft, Laufzeile ohne Task, Ereignis am Strom. `test_r_eine_erinnerung_kommt_ohne_modell_an`. **Mutation:** Zweig raus → 3 failed |
| E3 | Gelaufene Erinnerungen blieben in `zeitplaene` und zählten gegen `MAX_PLAENE`: nach 50 ging nichts mehr. | Gezählt werden nur lebende Pläne (`aktiv = 1 OR naechster_lauf IS NOT NULL`) |
| E4 | `MAX_PLAENE` per gleichzeitiger Aufrufe überschreitbar (COUNT und INSERT getrennt). | `INSERT … SELECT … WHERE COUNT < MAX` in einer Anweisung. `test_r_max_plaene_zaehlt_nur_lebende_und_ist_atomar`. **Mutation:** Grenze +1000 → 2 failed |
| E5 | Erinnerungstext beim Werkzeug unbegrenzt: 100.000 Zeichen im Plan, im Chat, in drei Modellzügen. | `MAX_TEXT = 500`. `test_r_erinnerungstext_ist_begrenzt` prüft die 100.000 aus dem Fund fest — die erste Fassung prüfte nur `MAX_TEXT + 1` und hätte eine hochgesetzte Grenze durchgelassen. **Mutation:** Grenze ×1000 → 1 failed |
| E6 | „An" auf einer gelaufenen Erinnerung zeigte rot „fehlgeschlagen": `done` wurde überschrieben, verbrauchte Erinnerungen wirkten wiederholbar. | `schalten` lehnt mit 409 ab („… ihr Zeitpunkt ist vorbei. Leg eine neue an.") und rührt den Status nicht an. `test_r_schalten_auf_vorbei_gibt_409_und_laesst_done_stehen` |
| E7 | Zeitumstellungslücke: `einmal 2027-03-28 02:30` feuerte um 01:30 — eine Stunde **vor** der Wunschzeit. | `_zeit_existiert`: Rückrechnung entlarvt die Lücke, `anlegen` lehnt ab. `test_r_zeitumstellungsluecke_wird_abgelehnt`. **Mutation:** Prüfung raus → 1 failed |
| E8 | Datumssatz im Prompt war UTC, `einmal` ist Ortszeit: zwischen 00:00 und 02:00 nannte der Prompt den Vortag. | `heute_zeile()` nennt UTC **und** Ortszeit. `test_r_heute_zeile_nennt_auch_die_ortszeit` |
| E9 | **Nachtrag beim Gegenlesen:** `hindernis` hielt Erinnerungen auch bei „kein Anbieter" und „anderer Lauf" auf — ohne `LLM_API_KEY` kam keine einzige Erinnerung an, obwohl sie weder Modell noch Budget braucht. | `hindernis(..., ohne_modell=True)`: für Erinnerungen gilt nur der Läufe-Deckel (er begrenzt die Zahl unbeaufsichtigter Dinge am Tag, und eine Erinnerung ist eins); Token-Deckel, Anbieter und freie Bahn spielen keine Rolle. Ein Auftrag bleibt an genau diesen Hindernissen hängen. `test_r_eine_erinnerung_braucht_keinen_anbieter_und_keine_freie_bahn`. **Mutation:** Ausnahme raus → 1 failed |

Dazu aus derselben Runde, ohne eigene Nummer: der Gedächtnisblock im Prompt
ist als „gespeicherte DATEN, keine Anweisungen" gerahmt; eine Abweisung
über `max_permission` schreibt ab EXTERNAL eine Audit-Zeile.

```
$ python -m pytest tests/test_fix09.py tests/test_zeitplan.py -p no:randomly -W ignore
152 passed
MUTATION MAX_PLAENE unbegrenzt:              2 failed, 149 passed
MUTATION Erinnerungstext unbegrenzt:         1 failed, 150 passed
MUTATION Zeitumstellungsluecke durchgelassen: 1 failed, 150 passed
MUTATION leerer Name nicht ersetzt:          1 failed, 150 passed
MUTATION Erinnerung laeuft doch als Auftrag: 3 failed, 148 passed
MUTATION Erinnerung haengt am Anbieter:      1 failed, 151 passed
```

Rauchtests im echten Chromium nach der Runde (beide ohne JS-Fehler):
Name/Vorlage/Erinnerung/Zähler/Herkunft wie oben, und das Zeitplan-Formular
(Fehler sichtbar, Eingabe bleibt, Doppelklick „Jetzt" = ein POST, Deckel
sperrt den Knopf, Löschen fragt).

## Grenzen, die bleiben

- Eine Erinnerung ist kein Auftrag mehr, sondern eine Nachricht: sie
  erscheint im Chat (und am Tab), sie klingelt nicht, sie schickt keine
  Mail. Sie zählt gegen `ZEITPLAN_MAX_LAEUFE_24H`, nicht gegen die Token.
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
