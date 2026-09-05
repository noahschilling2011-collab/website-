# FIX-08 — Zeitpläne: JARVIS wiederholt eigene Aufträge

> Auftrag von Noah, 05.09.2026: „dass er auch Aufgaben automatisieren kann".
> Gebaut ist die kleinste Form davon, die ohne Aufsicht sicher ist: ein
> Auftragstext plus eine Regel, wann er läuft. Diese Datei hält fest, was
> geprüft und gemessen wurde, nicht den Wunsch.

## Was das ist — und was nicht

Ein **Zeitplan** ist ein Auftragstext plus eine von genau zwei Regeln:

| Regel | Bedeutung |
|---|---|
| `taeglich 07:00` | jeden Tag um 07:00 **Ortszeit des Rechners** (auch `täglich 7:00`) |
| `alle 6 stunden` | im festen Takt ab dem letzten Lauf, 1 bis 168 Stunden |

Alles andere (`jeden Morgen`, Cron-Syntax, Wochentage) ist ein Fehler mit
klarer Absage, kein Ratespiel. Zur Zeit legt JARVIS daraus einen ganz
normalen Task an und schickt ihn durch dieselbe Kette wie einen getippten:
Planer, Runner, Agenten, Werkzeuge, Budgets. **Es gibt keinen zweiten
Runner für Zeitpläne** — `tests/test_zeitplan.py::test_die_regel_steht_an_einer_stelle`
fällt, sobald `api/zeitplan.py` etwas anderes als `starte_task` ruft.

Es ist **kein Computer-Agent**. `CLAUDE.md` streicht „Programme oder UI
steuern" dauerhaft, und daran ändert FIX-08 nichts: JARVIS wiederholt seine
*eigenen* Aufträge, mehr nicht.

## Die drei Regeln, und der Test zu jeder

**1. Obergrenze LOCAL, egal was `MAX_PERMISSION` sagt.**
Ein getippter Auftrag darf bis EXTERNAL gehen, weil der Nutzer vor dem
Bildschirm sitzt und `send_email` per Rückfrage freigibt. Ein Zeitplan läuft
um 07:00, während der Nutzer schläft. Deshalb ist die Grenze hart in
`core/zeitplan.py` (`PERMISSION_DECKEL = Permission.LOCAL`) — keine
`.env`-Zeile, die man um drei Uhr nachts hochdreht.
Test: `test_regel_1_die_obergrenze_ist_local_egal_was_die_env_sagt` setzt
`MAX_PERMISSION=4` und misst, was beim Runner ankommt — Schleife und
„Jetzt"-Knopf beide LOCAL. Gegenprobe
`test_getippte_auftraege_behalten_ihre_obergrenze`: getippt bleibt EXTERNAL.

**2. Ein Deckel über ALLE Pläne, über 24 Stunden, in Läufen UND Token.**
Ein Plan, der jede Stunde läuft und jedes Mal 8.000 Token kostet, frisst das
Tageskontingent der freien Groq-Stufe (200.000) still in einem Tag. Der
Verbrauch wird über die echten Tasks gerechnet (`zeitplan_laeufe` ⋈ `tasks`),
nicht über einen Zähler, den jemand pflegt. Vorgaben `ZEITPLAN_MAX_LAEUFE_24H=24`,
`ZEITPLAN_MAX_TOKEN_24H=50000`; `test_der_deckel_ist_nicht_stillschweigend_erhoeht_worden`
hält beide gegen `.env.example` und gegen das Groq-Kontingent.
Am Deckel wird **übersprungen, nicht gewartet**: der Plan bekommt einen
neuen Termin und den Grund als Status — sonst stünde er in einer Minute
wieder an (`test_runde_ueberspringt_am_deckel_und_bleibt_nicht_haengen`).

**3. Verpasste Läufe werden gezählt, nicht nachgeholt.**
War der Rechner um 07:00 aus, läuft der Auftrag um 07:00 am nächsten Tag —
nicht „sofort beim nächsten Start". Nachholen klingt freundlich, ist aber
genau die Überraschung, die Regel 2 verhindern will: der Rechner startet,
drei Pläne feuern gleichzeitig. Toleranz: zwei Minuten (`TOLERANZ`).
Tests: `test_regel_3_verpasst_wird_gezaehlt_nicht_nachgeholt`,
`test_stundentakt_zaehlt_ab_dem_letzten_lauf_und_holt_nicht_nach`,
`test_einschalten_rechnet_den_termin_neu_statt_sofort_zu_feuern` (die
Stelle, an der man Regel 3 am leichtesten vergisst).

Dazu: **kein Doppellauf.** Läuft der vorige Task eines Plans noch, wird
übersprungen (`test_hindernis_wenn_der_vorige_lauf_noch_laeuft`). Ohne
eingerichteten Anbieter wird übersprungen, nicht abgestürzt
(`test_hindernis_ohne_anbieter`).

## Was gebaut ist

| Datei | Was |
|---|---|
| `core/zeitplan.py` | Regeln, Terminberechnung, Buchung, Deckel — alle drei Regeln an EINER Stelle |
| `api/zeitplan.py` | `GET/POST /api/zeitplaene`, `DELETE /api/zeitplaene/{id}`, `POST …/schalten`, `POST …/jetzt`; die Schleife `zeitplan_schleife` |
| `api/app.py` | Schleife startet nach „JARVIS bereit", wird beim Herunterfahren **vor** `stop_alle()` abgebrochen |
| `api/tasks.py` | `starte_task(app, ziel, max_permission=, am_ende=)` — additiv; `baue_laufzeit(app, …)` statt `request` |
| `core/schema.sql` | `zeitplaene`, `zeitplan_laeufe` (Fremdschlüssel auf `tasks`: ein Lauf ohne Task wird abgelehnt) |
| `core/config.py`, `.env.example` | `ZEITPLAN_MAX_LAEUFE_24H`, `ZEITPLAN_MAX_TOKEN_24H`, `ZEITPLAN_TAKT_S` (0 = Schleife aus, „Jetzt" geht trotzdem) |
| `index.html` | Block „Zeitpläne" oben in *Aufträge*: anlegen, an/aus, Jetzt, löschen; Verbrauchszeile; Deckel-Hinweis. Nur `textContent`. |
| `tests/test_zeitplan.py` | 102 Tests, alle gegen `FakeLLMProvider` — 65 beim Bauen, 19 aus der ersten, 18 aus der zweiten Prüfrunde |

Der Knopf **Jetzt** löst sofort aus — mit denselben Grenzen wie die Schleife —
und **verschiebt den Termin nicht**: ein Probelauf um 15:00 macht aus
„taeglich 07:00" nichts anderes (`test_ein_handlauf_verschiebt_den_termin_nicht`).
Er zählt aber für den Deckel: Token sind Token.

## Ausgeführt

```
$ python -m pytest tests/test_zeitplan.py -p no:randomly -W ignore
102 passed in 7.8s   (dreimal hintereinander, keine Flackerer)
```

Rauchtest im echten Browser (uvicorn + Chromium, FakeLLMProvider), gekürzt:

```
1 Block sichtbar: Zeitpläne
2 Meldung bei falscher Regel: 'jeden Morgen' verstehe ich nicht. Erlaubt sind genau zwei Formen: …
  Plaene: 0
3 Plan angelegt: Morgenlage aktiv taeglich 07:00
  Zeile: nächster Lauf 06.09.2026 07:00:00
4 Aus: kein nächster Lauf   /   An: aktiv
5 Meldung nach Jetzt: Zeitplan „Morgenlage" läuft jetzt (Auftrag bc5a3c36caee).
  Zeile danach: nächster Lauf 06.09.2026 07:00:00  zuletzt 05.09.2026 11:15:01  done
  Verbrauch: Letzte 24 h: 1 von 24 Läufen, 448 von 50000 Token
6 Fokusringe: 6 von 6 Elementen solid 2px rgb(240, 180, 92)
7 Geloescht: True
```

Der erste Fehler beim Bauen: mein Test erfand Task-IDs (`"task-1"`), und
die Datenbank lehnte sie ab — `FOREIGN KEY constraint failed`. Das war
richtig so. Der Fremdschlüssel ist jetzt selbst getestet
(`test_ein_lauf_ohne_task_wird_abgelehnt`), die Tests legen echte Tasks an.

## UNSICHER, bewusst dokumentiert

Die Ortszeit für `taeglich` kommt aus `datetime.now().astimezone()` — ein
**fester Versatz** zum Zeitpunkt der Berechnung, keine IANA-Zone. Der nächste
Lauf wird nach jedem Lauf neu gerechnet, also stimmt die Uhrzeit ab dem
zweiten Lauf nach einer Zeitumstellung wieder. **Der eine Lauf direkt nach
dem Wechsel kann eine Stunde danebenliegen.** Eine IANA-Zone bräuchte den
Zonennamen des Systems, den die Standardbibliothek unter Windows nicht
hergibt. Getestet ist die Ortszeit-Behauptung in vier Zonen
(`UTC`, `Europe/Berlin`, `America/Los_Angeles`, `Asia/Kolkata`) über
`TZ` + `time.tzset()` — auf Linux; unter Windows fällt der Test hart, statt
zu überspringen.

## Was ein Zeitplan im Verlauf hinterlässt

Der Auftragstext erscheint im Chat-Verlauf als Nutzer-Nachricht, genau wie
ein getippter — `starte_task` schreibt ihn dorthin, damit die Antwort einen
Anlass hat. Wer um 08:00 den Chat öffnet, sieht also „Sag guten Morgen." um
07:00, ohne es getippt zu haben. Woher es kam, steht in *Aufträge* am
Zeitplan (`letzter_task_id`) und in `zeitplan_laeufe`. Eine Markierung im
Verlauf selbst wäre eine Änderung an `messages` — nicht in diesem Auftrag.

## Definition of Done

| # | Kriterium | Beleg |
|---|---|---|
| 1 | Ein Plan mit `taeglich HH:MM` oder `alle N stunden` lässt sich anlegen, schalten, löschen — über API und Oberfläche | `test_anlegen_listen_schalten_loeschen_ueber_http`, Rauchtest 3/4/7 |
| 2 | Die Schleife startet fällige Pläne über denselben Runner wie getippte Aufträge | `test_runde_startet_faellige_und_bucht_verpasste`, `test_die_regel_steht_an_einer_stelle` |
| 3 | Obergrenze LOCAL, unabhängig von `MAX_PERMISSION` | `test_regel_1_…`, Gegenprobe `test_getippte_auftraege_…` |
| 4 | Tagesdeckel über alle Pläne, Läufe und Token — auch für gleichzeitig laufende; kein Lauf bekommt mehr als den Rest des Tages; Vorgaben nicht stillschweigend geändert | `test_verbrauch_zaehlt_alle_plaene_ueber_24_stunden`, `test_deckel_…`, `test_der_deckel_ist_nicht_…`, `test_fund5_*`, `test_starte_task_laesst_ein_budget_nur_nach_unten` |
| 5 | Verpasste Läufe werden gezählt, nie nachgeholt — auch beim Einschalten | `test_regel_3_…`, `test_einschalten_rechnet_den_termin_neu_…` |
| 6 | Kein Doppellauf (auch nicht Schleife + Knopf gleichzeitig), kein Absturz ohne Anbieter, kein Hängenbleiben am Deckel, ein kaputter Plan reißt die anderen nicht mit | `test_hindernis_*`, `test_runde_ueberspringt_am_deckel_…`, `test_fund1_*`, `test_fund2_*` |
| 7 | Schleife lebt mit der App und stirbt mit ihr; ein Fehler in einer Runde tötet sie nicht | `test_die_schleife_lebt_mit_der_app_…`, `test_ein_fehler_in_einer_runde_…` |
| 8 | Kein Modellaufruf, kein Netz in den Tests | `FakeLLMProvider`, Netzsperre in `tests/conftest.py` |
| 9 | Jede Route hat einen Nutzer in der Oberfläche | `tests/test_routen_haben_einen_nutzer.py` grün, `test_die_oberflaeche_ruft_jede_route` |

## Erste Prüfrunde — zwei Skeptiker, 18 bestätigte Funde, alle behoben

Zwei Agenten, einer auf die Kernlogik, einer mit Chromium auf die
Oberfläche, jeder mit dem Auftrag, jede Behauptung dieser Datei zu
widerlegen. Ergebnis: **6 Kernfunde, 12 Oberflächenfunde**, alle mit
ausgeführtem Beleg. Die wichtigsten, und was daraus wurde:

| # | Fund (belegt) | Behoben durch | Test, der jetzt kippt |
|---|---|---|---|
| K1 | **Doppelstart.** Schleife und „Jetzt" lasen den Plan, sahen beide „kein Hindernis", starteten beide — 20 von 20 Versuchen. Der Handlauf schrieb dazu den alten, vergangenen Termin zurück → dritter Start in der nächsten Runde. | `versuche_start`: Plan **erst beanspruchen** (synchron, ohne `await` dazwischen — auf einer Event-Loop atomar), dann frisch lesen, prüfen, starten. `verbuche_start` schreibt nur noch die Spalten, die sich ändern. | `test_fund1_schleife_und_knopf_starten_denselben_plan_nur_einmal` (10× `gather`), `test_fund1_buchung_schreibt_keine_alten_werte_zurueck` |
| K2 | Eine Ausnahme bei Plan A brach die ganze Runde ab; Plan B verlor seinen Lauf, A blieb fällig ohne Grund — nach zwei Minuten beide „verpasst". | try/except **je Plan**; A bekommt `Start fehlgeschlagen (Typ)` als Status (über `core/fehlertexte.ohne_geheimnis`, kein Pfad, kein Text der Ausnahme) und einen neuen Termin. | `test_fund2_ein_kaputter_plan_kostet_den_naechsten_nicht_seinen_lauf` |
| K3 | `TOLERANZ` fest 2 min, `ZEITPLAN_TAKT_S` nach oben offen: ab Takt 180 s wäre jeder Lauf „verpasst" — täglich. | `toleranz_fuer(takt)` = max(2 min, 2 Takte); die Runde nimmt sie. | `test_fund3_*` |
| K4 | „alle N stunden" **driftete** um die Schleifenverzögerung — 18 min am Tag —, obwohl der Docstring das Gegenteil versprach. | Der nächste Takt zählt ab dem **Soll**-Termin, nicht ab dem Zeitpunkt, an dem die Schleife ihn bemerkt. | `test_fund4_der_stundentakt_driftet_nicht` (24 Läufe à 45 s spät → exakt +24 h) |
| K5 | Der Token-Deckel zählte **laufende** Tasks mit 0 (ihre Token stehen erst am Ende in der DB). Drei gleichzeitig fällige Pläne: 180.000 gegen 50.000. Dazu: `BUDGET_MAX_TOKENS` 60.000 > Deckel 50.000 — ein Lauf durfte mehr als der ganze Tag. | `reserviert(app)`: was laufende Zeitplan-Tasks **noch ausgeben dürfen**, zählt schon. Und jeder Lauf bekommt als Budget höchstens den **Rest** des Tagesdeckels — `starte_task` lässt ein Budget nur nach unten ändern (Regel 6 gilt auch im eigenen Haus). | `test_fund5_gleichzeitige_plaene_reissen_den_token_deckel_nicht` (erster Plan 50.000, zwei weitere „Tagesdeckel"), `test_fund5_ein_lauf_bekommt_hoechstens_den_rest_des_tages`, `test_starte_task_laesst_ein_budget_nur_nach_unten` |
| K6 | `hindernis()` lief in der Schleife synchron auf der Event-Loop, mit SQLite-Abfrage (bis 10 s busy-timeout) — blockierte jede HTTP-Antwort. | in `versuche_start` über `to_thread`. | — (Struktur) |
| K7 | `MAX_PERMISSION=9` fiel erst beim ersten Auftrag auf: 500 im Browser, `ValueError` in der Runde. | Validator in `core/config.py`: keine Stufe → Start verweigert, mit den erlaubten Werten im Text. | `test_max_permission_muss_eine_stufe_sein` |
| U1 | **Jede Meldung des Blocks war unsichtbar** — Fehler und Erfolg. `meldung()` schreibt in `#hint`, das im Composer liegt, und der ist außerhalb des Chats versteckt. Der erste Rauchtest las den Text per `text_content()` und merkte es deshalb nicht. | Eigene `role="status"`-Zeile **im Block**. | `test_ui_der_block_meldet_im_block_nicht_im_versteckten_composer` |
| U2 | Doppelklick auf „Jetzt" → zwei Aufträge, doppelte Token. | Knopf sperrt sich bis zur Antwort; dazu K1 im Backend. | Rauchtest: `dblclick` → 1 POST |
| U3 | 422 zeigte rohes pydantic-JSON **samt der ganzen Eingabe** (10.141 Zeichen); kein `maxlength`; danach scrollte die Seite horizontal. | `api()` macht aus einer pydantic-Liste „Feld: Satz", nie `input`; `maxlength` 80/40/10000; Regel-Absage zitiert höchstens 40 Zeichen. | `test_ui_api_zeigt_nie_die_eingabe_aus_einer_pydantic_liste`, `test_regelabsage_zitiert_hoechstens_40_zeichen` |
| U4 | Text ohne Leerzeichen sprengte die Karte (scrollWidth 102.492 px). | `overflow-wrap: anywhere` auf Name, Auftrag, Meldung, Grund. | Rauchtest: 900/900, mobil 390/390 |
| U5 | „Löschen" ohne Rückfrage. | `window.confirm`, wie bei Gedächtnis-Fakten. | `test_ui_knoepfe_sperren_sich_und_loeschen_fragt` |
| U6 | Nach jeder Aktion: Fokus weg, Scrollposition weg, halb getippte Eingabe weg — die ganze Ansicht wurde neu gebaut. | Der Block wird **einmal** gebaut, danach tauscht nur die Liste; der Fokus springt auf den neu gebauten Knopf (`data-plan`/`data-aktion`). | Rauchtest: Eingabe bleibt, Fokus auf „An" |
| U7 | „Aus" dimmte den ganzen Eintrag inklusive Knöpfen auf 2,5:1 Kontrast; Tap-Ziele 21 px. | Nur der Text wird gedimmt; eigene `.zeitplan-knopf` mit 28 px Mindesthöhe. | Rauchtest: Knopffarbe `--text`, Höhe 30,75 px |
| U8 | „verpasst" doppelt, einmal mit rohem UTC-Stempel; „aktiv" sah aus wie „läuft"; übersprungene Läufe ohne Farbe. | Pillen: `läuft` (Akzent), `done/failed/…`, `verpasst`, `übersprungen` + Grund in Rot; „aktiv/aus" neutral. | — (Rauchtest, Screenshot) |
| U9 | „Jetzt" blieb am Deckel klickbar, die 409 unsichtbar. | Knopf gesperrt mit dem Deckeltext als Tooltip; Warnung im Block. | Rauchtest: `disabled: True` |
| U10 | Nicht-JSON-Fehlerseiten (Proxy-HTML mit Pfaden) gingen ungefiltert in die Oberfläche. | `api()`: bei HTML-Körper nur `HTTP <Status>`. | — |
| U11 | `/api/tasks` 500 → der Zeitplan-Block verschwand mit. | Block zuerst, Aufträge in eigenem Container mit eigenem Fehlertext. | — |
| U12 | Keine Hierarchie (Blocktitel = Auftragstitel = Planname), das leere Formular dominierte die Ansicht, drei Zahlenformate („50000" / „50,000" / „50.000"). | Versalien-Label als Titel; Formular in `<details>`, offen nur ohne Pläne; eine Zahlschreibweise (`ccZahl`, de-DE, und `_de()` im Backend). | `test_deckeltext_schreibt_deutsche_tausender` |

Drei der neuen Tests gegen ihre Mutation geprüft (Schutz entfernt → Test rot):

```
MUTATION ohne Anspruch:      1 failed   (Doppelstart-Test)
MUTATION ohne Reservierung:  1 failed   (Token-Deckel-Test)
MUTATION mit Drift:          1 failed   (Stundentakt-Test)
```

Zweiter Rauchtest im Browser nach den Änderungen, gekürzt:

```
2 Fehler SICHTBAR: True | 'jeden Morgen' verstehe ich nicht. …
  Formular behaelt Eingabe: Morgenlage
3 Erfolg sichtbar: True | Zeitplan „Morgenlage“ angelegt, taeglich 07:00.
  maxlength: [80, 40, 10000]
4 Aus: Eingabe bleibt: halb getippt | Fokus auf: An | Knopffarbe bei aus: rgb(232, 232, 236)
5 Doppelklick Jetzt -> POST /jetzt: 1
6 Deckel: Tagesdeckel erreicht: 2 von 2 Laeufen … | Jetzt disabled: True
7 Loeschen abgebrochen -> Plaene: 1 / bestaetigt -> Plaene: 0
8 Langtext: view scrollWidth/clientWidth: [900, 900]  mobil: [390, 390] | Knopfhoehe: 30.75
JS-Fehler: keine
```

Zwei Beobachtungen der Prüfer, bewusst so gelassen und dokumentiert:
„Jetzt" geht auch bei einem **ausgeschalteten** Plan — „aus" heißt „läuft
nicht von selbst", nicht „darf nie laufen" (`test_beobachtung7_jetzt_geht_auch_bei_aus`).
Und: es gibt keinen Löschpfad für Tasks; würde jemand per SQL löschen,
bliebe `letzter_status` auf „laeuft" stehen (`ON DELETE SET NULL`).

Was diese Runde **nicht** angefasst hat: die Zeitzonen-Behauptung wurde vom
Prüfer über ein Jahr gegen `zoneinfo` gesweept — genau die dokumentierte
Abweichung (±1 h an den ~1,5 Tagen vor jedem Wechsel), kein Doppel-, kein
ausgelassener Lauf. Regel 1 (LOCAL) hielt jedem Umgehungsversuch stand.

## Zweite Prüfrunde — acht Blickwinkel, 20 Rohfunde, 15 behoben

Acht Prüfer mit je einem Blickwinkel (Regel 1 in der Tiefe, Regel 2, Regel 3
und Zeit, Lebenszyklus, HTTP-Vertrag, Oberfläche, Testqualität, Doku). Vier
davon kamen durch, vier und alle Skeptiker scheiterten am Sitzungslimit —
die Funde unten habe ich deshalb **selbst** gegen Tests gehalten statt gegen
Widerleger. Jeder behobene Fund hat einen Test, sieben davon sind gegen ihre
Mutation geprüft (Schutz entfernt → Test rot).

| Fund (belegt vom Prüfer) | Behoben durch | Test |
|---|---|---|
| **Start vor Buchung.** Absturz oder Fehler zwischen `starte_task` und der Buchung → Doppelstart nach Neustart, Task-Leiche „pending" für immer, erster Lauf zählt nie für den Deckel. | **Der Termin ist die Sperre:** `termin_weiter` schiebt ihn in EINER Anweisung weiter, nur wenn er noch der gelesene ist (`WHERE naechster_lauf = alt AND aktiv = 1`). Task-Zeile und Protokoll stehen VOR dem Start. Beim nächsten Start räumt `abgleich` tote Tasks auf. | `test_r2_gebucht_wird_vor_dem_start`, `test_r2_die_sperre_haelt_ueber_prozessgrenzen`, `test_r2_abgleich_nach_neustart` |
| **Zweiter Plan auf derselben Minute verhungerte.** Die Reservierung des ersten füllte den ganzen Tagesrest, der zweite wurde auf morgen geschoben — jeden Tag. Dazu: zwei Pläne gleichzeitig bekamen beide den ganzen Rest. | **Zeitpläne laufen nacheinander.** Die Runde wartet auf das Ende eines Laufs, bevor der nächste startet; jeder bekommt den echten Rest. Der Knopf antwortet währenddessen 409 „ein anderer Zeitplan läuft gerade". | `test_fund5_gleichzeitige_plaene_laufen_nacheinander_und_halten_den_deckel` (A 50.000, B 30.000, C 10.000), `test_r2_jetzt_wartet_wenn_ein_anderer_zeitplan_laeuft` |
| `reserviert()` zog den LIVE-Verbrauch vom Budget ab, die Datenbank hatte den alten Stand → ein laufender Task zählte weniger als sein Budget. | Ein laufender Task zählt mit `max(DB-Stand, Budget)` (`verbrauch_24h(reserviert=…)`). | `test_r2_laufende_tasks_zaehlen_mit_ihrem_budget` |
| Plan löschen löschte seine Läufe (`ON DELETE CASCADE`) → Tagesdeckel per Löschen und Neuanlegen zurücksetzbar. | `zeitplan_id` wird NULL statt gelöscht; `verbrauch_24h` joint nicht mehr über `zeitplaene`. Alte Datenbanken baut `scripts/migrate.py` um. | `test_r2_das_protokoll_ueberlebt_das_loeschen_des_plans`, `test_r2_migration_baut_alte_laeufe_tabelle_um` |
| 1 Token Rest: der Lauf startete, bezahlte den Planungszug, brach ab. | `MINDEST_REST = 2.000`: darunter „Tagesdeckel fast erreicht", kein Start. | `test_fund2r2_der_mindestrest_greift_vor_dem_start` |
| Toleranz ohne Obergrenze: `ZEITPLAN_TAKT_S=3600` machte aus „verpasst" ein Nachholen. | Takt ist 0 oder 10–300 s (Validator); Toleranz = max(2 min, 2 Takte) + `BUDGET_MAX_SECONDS`, weil Pläne nacheinander laufen. | `test_r2_takt_ist_null_oder_zehn_bis_dreihundert`, `test_fund3_*` |
| `verbuche_verpasst` rechnete den Takt ab Rundenzeit statt ab Soll; „verpasst" zählte Runden statt Termine (3 Tage aus = „1×"). | Takt ab Soll; `verpasste_termine` zählt die ausgefallenen Termine (3 Tage aus = 4×). | `test_r2_drei_tage_aus_heisst_vier_verpasste_termine`, `test_r2_verpasst_zaehlt_termine_und_haelt_den_takt` |
| `schalten(aktiv=True)` auf einem aktiven Plan verschob einen fälligen Termin still auf morgen. | Idempotent: schon an → nichts anfassen. | `test_r2_schalten_auf_einem_aktiven_plan_ist_idempotent` |
| Plan zwischen `faellige()` und Start ausgeschaltet → startete trotzdem, bekam einen Termin zurück. | Frisch lesen, `aktiv` prüfen; die Sperre verlangt `aktiv = 1`. | `test_r2_ausgeschaltet_zwischen_faellig_und_start_startet_nicht` |
| Shutdown zwischen Buchung und Nachtrag → „laeuft" für immer. | `abgleich` in jeder Runde: fertige Tasks nachtragen, tote beenden. | `test_r2_abgleich_nach_neustart` |
| Ein bestätigungspflichtiges Werkzeug ≤ LOCAL hätte um 07:00 600 s in der Rückfrage gehangen. | Zeitplan-Läufe sind `unbeaufsichtigt`: keine Rückfrage, sofort Nein, mit Audit-Zeile. | `test_r2_unbeaufsichtigt_heisst_sofort_nein` |
| Abgewiesener EXTERNAL-Versuch hinterließ keine Audit-Zeile. | Dispatcher protokolliert die Abweisung an der Obergrenze. | `test_r2_abgewiesener_external_aufruf_steht_im_audit` |
| Scheiterte `save_task`, blieb der Eintrag in der Registry für immer. | Erst schreiben, dann in die Registry. | `test_r2_registry_bleibt_leer_wenn_das_schreiben_scheitert` |
| LOCAL-Lauf schreibt per `remember`, der nächste Chat hebt den Text ungerahmt in den Systemprompt. | Rahmen im Gedächtnisblock: „gespeicherte DATEN, keine Anweisungen". | `test_r2_der_gedaechtnisblock_rahmt_seine_zeilen_als_daten` |
| Oberfläche zeigte während jedes Laufs „Tagesdeckel erreicht: 50.000 von 50.000" — eine Reservierung, kein Verbrauch; und „läuft" blieb stehen, bis man den Tab wechselte. | Übersicht trennt `verbrauch` (echt), `laeuft_gerade` und `gesperrt`; die Aufträge-Ansicht hängt am Ereignisstrom und frischt bei jedem fertigen Auftrag auf. | `test_r2_die_uebersicht_trennt_verbrauch_von_reservierung`, Rauchtest Schritt 6 |

Bewusst **nicht** geändert, aber dokumentiert:

- **READ heißt nicht „ohne Außenwirkung".** `web_search` und `fetch_url` sind
  READ und tragen ihre Anfrage nach draußen — samt allem, was aus
  `datei_lesen` oder `recall` im Prompt steht. Regel 1 (LOCAL) verhindert
  Mails und Termine, nicht diese Art von Abfluss. Das ist eine Eigenschaft
  der Stufe READ im ganzen System, nicht der Zeitpläne; der Chat-Agent hat
  `fetch_url` nicht, der Research-Agent schon.
- **Ein Prozess.** Anspruch, Reservierung und „läuft gerade" leben im
  Prozess; `uvicorn --workers 2` hieße zwei Schleifen. Die Terminsperre
  verhindert den Doppelstart auch dann, der Rest nicht. README und
  `.env.example` sagen es.
- Ein Fehler in `verbuche_verpasst` heißt jetzt „Verpasst-Buchung
  fehlgeschlagen", nicht „Start fehlgeschlagen".

Mutationen (Schutz raus → Test rot), alle ausgeführt:

```
MUTATION Sperre ohne Bedingung:        2 failed
MUTATION ohne Mindestrest:             2 failed
MUTATION Rueckfrage trotz unbeaufsichtigt: 1 failed
MUTATION Buchung nach dem Start:       1 failed
MUTATION ohne Reservierung:            1 failed
MUTATION ohne Audit bei Abweisung:     1 failed
MUTATION Verbrauch haengt am Plan:     2 failed
```

Und ein Fund, den erst die Sperre sichtbar gemacht hat: die Tests riefen
die Runde selbst, während die Hintergrundschleife nebenher lief — beide
sahen denselben fälligen Plan, nur einer durfte starten, der Test bekam
„startet gerade" (1 von 3 Läufen). Vorher wäre das ein stiller Doppelstart
gewesen. Die Tests schalten die Schleife jetzt ab, wenn sie die Runde
selbst rufen.

## Nebenfund: die Backup-Prüfung kannte vier Tabellen nicht

`scripts/backup.py pruefen` zählte Zeilen für eine Liste von Hand — acht
Tabellen. `core/schema.sql` hat zwölf eigene (ohne Volltextindizes).
`lookups`, `vault_notizen`, `weltlage_cache`, `weltlage_zaehler` fehlten
still, und `zeitplaene`, `zeitplan_laeufe` hätten auch gefehlt. Dieselbe
Fehlerklasse wie die von Hand gezählten Settings-Felder in STATUS.md: eine Zahl oder Liste,
die niemand nachzählt. Jetzt wird abgeleitet, was in der Datei ist;
`tests/test_backup_zaehlt_alles.py` hält es gegen das Schema.

## Nicht gebaut, mit Absicht

- **Wochentage, Cron, „jeden Montag"** — zwei Formen reichen für den Anfang;
  jede weitere braucht einen Test für die Terminberechnung.
- **Nachholen verpasster Läufe** — siehe Regel 3.
- **EXTERNAL im Zeitplan** („schick mir jeden Morgen eine Mail") — geht erst,
  wenn es eine Freigabe *im Voraus* gibt, und die ist ein eigener Auftrag
  mit eigenen Risiken (0.4.6: Bestätigung ohne Ausnahme).
