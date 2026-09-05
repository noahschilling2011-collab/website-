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
| `tests/test_zeitplan.py` | 65 Tests, alle gegen `FakeLLMProvider` |

Der Knopf **Jetzt** löst sofort aus — mit denselben Grenzen wie die Schleife —
und **verschiebt den Termin nicht**: ein Probelauf um 15:00 macht aus
„taeglich 07:00" nichts anderes (`test_ein_handlauf_verschiebt_den_termin_nicht`).
Er zählt aber für den Deckel: Token sind Token.

## Ausgeführt

```
$ python -m pytest tests/test_zeitplan.py -p no:randomly -W ignore
65 passed in 3.75s
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
| 4 | Tagesdeckel über alle Pläne, Läufe und Token, Vorgaben nicht stillschweigend geändert | `test_verbrauch_zaehlt_alle_plaene_ueber_24_stunden`, `test_deckel_…`, `test_der_deckel_ist_nicht_…` |
| 5 | Verpasste Läufe werden gezählt, nie nachgeholt — auch beim Einschalten | `test_regel_3_…`, `test_einschalten_rechnet_den_termin_neu_…` |
| 6 | Kein Doppellauf, kein Absturz ohne Anbieter, kein Hängenbleiben am Deckel | `test_hindernis_*`, `test_runde_ueberspringt_am_deckel_…` |
| 7 | Schleife lebt mit der App und stirbt mit ihr; ein Fehler in einer Runde tötet sie nicht | `test_die_schleife_lebt_mit_der_app_…`, `test_ein_fehler_in_einer_runde_…` |
| 8 | Kein Modellaufruf, kein Netz in den Tests | `FakeLLMProvider`, Netzsperre in `tests/conftest.py` |
| 9 | Jede Route hat einen Nutzer in der Oberfläche | `tests/test_routen_haben_einen_nutzer.py` grün, `test_die_oberflaeche_ruft_jede_route` |

## Nebenfund: die Backup-Prüfung kannte vier Tabellen nicht

`scripts/backup.py pruefen` zählte Zeilen für eine Liste von Hand — acht
Tabellen. `core/schema.sql` hat zwölf eigene (ohne Volltextindizes).
`lookups`, `vault_notizen`, `weltlage_cache`, `weltlage_zaehler` fehlten
still, und `zeitplaene`, `zeitplan_laeufe` hätten auch gefehlt. Dieselbe
Fehlerklasse wie die „32 Settings-Felder": eine Zahl oder Liste von Hand,
die niemand nachzählt. Jetzt wird abgeleitet, was in der Datei ist;
`tests/test_backup_zaehlt_alles.py` hält es gegen das Schema.

## Nicht gebaut, mit Absicht

- **Wochentage, Cron, „jeden Montag"** — zwei Formen reichen für den Anfang;
  jede weitere braucht einen Test für die Terminberechnung.
- **Nachholen verpasster Läufe** — siehe Regel 3.
- **EXTERNAL im Zeitplan** („schick mir jeden Morgen eine Mail") — geht erst,
  wenn es eine Freigabe *im Voraus* gibt, und die ist ein eigener Auftrag
  mit eigenen Risiken (0.4.6: Bestätigung ohne Ausnahme).
