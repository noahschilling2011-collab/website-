# Ordner ki/ – trainierte Policies für die Bewohner

Hier liegen die Policies, die das Spiel auf Wunsch lädt, und das Schema, auf das sie trainiert sind. **Seit Version 10 (Etappe 2) ist keine
gültige Policy hier:** `policy_v9_lokal_1.json` ist auf Stadt-Version 9 trainiert und wird abgelehnt („Policy ungültig: trainiert auf
Stadt-Version 9, diese Stadt ist Version 10 (neu trainieren)“, `berichte/etappe2/mess/schritt5/ki_v9_ablehnung.txt`); es entscheiden die
Regeln. Sie bleibt als Beleg und in `policies.json`, damit das Spiel die Ablehnung mit Grund zeigt. Die Regeln (`entscheide` im sim-Block)
bleiben Standard. Keine Policy steckt in `stadt.html`, solange keine die Auswertung bestanden hat.

| Datei | Was |
|---|---|
| `policies.json` | Liste der Policy-Dateien, die das Spiel anbietet. Schreibt `node tools/ki_liste.mjs` (nimmt nur Dateien auf, die die `stadt.html` daneben annimmt; seit Version 10 schriebe es die Liste deshalb leer, `--nur-pruefen` prüft nur) |
| `policy_v9_lokal_1.json` | Lauf `v9_lokal_1` (155.648 Schritte, Belohnung v2, Version 9; seit Version 10 abgelehnt). Status **experimentell**, Auswertung **nicht bestanden** (Feld `auswertung`, Bericht `berichte/v9_lokal_1/abschluss.md`). Das Feld `hinweis` nennt seit dem 29.09.2026 auch die gemessene Stadtwirkung; das Spiel zeigt `auswertung.urteil` und `hinweis` im Fenster |
| `schema_v2.json` | Beobachtungsschema 2 (57 Merkmale) und Aktionen (warten + 12), Hash `e85eca0c`. Schreibt `node tools/ki_schema.mjs` |

## Wie das Spiel eine Policy lädt

- Einstellungen (Zahnrad) → „Entscheidungen: Regeln ›“ → „Trainierte Policy (experimentell)“. Erst dann holt das Spiel `ki/policies.json`
  und die dort genannten Dateien per `fetch` mit relativer URL. Die Seite muss dafür über einen Server laufen (`python3 -m http.server 8000
  --bind 127.0.0.1` im Ordner `stadt/`); als `file://` geht es nicht, dann gibt es einen Hinweis und es entscheiden die Regeln.
- Andere Datei: im selben Fenster „Policy-Datei laden …“; angenommen oder abgelehnt (mit Grund) steht oben im Fenster. Sie bleibt im
  Browser (`localStorage['stadt-policy-v1']`), nicht im Spielstand; „Geladene Datei entfernen“ löscht sie (war sie gewählt: Regeln).
- Jede Datei wird streng geprüft (`Sim.KI.policyPruefen`): Format `stadt-policy` 2, `simVersion` = Version der Stadt (seit Etappe 2: 10), Schema-Hash,
  Merkmale, Aktionen, endliche Zahlen, Streuung > 0, Schichten, Inhalts-Hash (SHA-256 über Kopf, Normalisierung, Gewichte, nachgerechnet).
  Was nicht passt, wird mit Grund abgelehnt. Gewichte, Bias und `clip` müssen auch nach dem Runden auf float32 endlich sein (ein Wert wie
  `1e39` wird abgelehnt; die frühere Lücke ist seit der Vorarbeit zu Etappe 2 geschlossen, `docs/GRENZEN.md`). Die Maske gilt immer, eine
  gesperrte Aktion ist nie möglich.
- Im Spielstand steht nur ein Verweis: `ui.entscheidungen = { v: 1, art, name, hash, schema }`. Beim Laden zählt nur der Hash. Fehlt genau
  diese Policy oder passt sie nicht, entscheiden die Regeln, und das Spiel sagt es (Rückfall). Nie still ein anderes Modell. Nach einem
  Rückfall speichert das Spiel die Regeln als Wahl; liegt die Policy später wieder in `ki/`, im Fenster neu wählen. Kommt der Stand aus
  Version 9 (Übernahme oder Import), sagt die Meldung „stammt aus Version 9 und gilt in Version 10 nicht mehr (neu trainieren)“; neu wählen
  hilft dann nicht.
- Die Policy entscheidet nur für Erwachsene unter 67, die keine Hauptfigur und nicht Bürgermeister sind, an deren normalen
  Entscheidungszeitpunkten. Alles andere bleibt bei den Regeln.

## Format einer Policy-Datei (Format 2)

`format`, `formatVersion`, `name`, `status` (`experimentell`; eingebettet würde nur `freigegeben`), `hinweis`, `simVersion`, `schemaHash`,
`beobachtung` (Schema-Version, Länge, Merkmale), `aktionen.liste` (Index = Aktionscode, 0 = warten), `normalisierung` (Mittel, Streuung, clip,
nur aus Trainingsdaten), `netz.schichten` (je Schicht Gewichte als float32-Werte, Bias, Aktivierung `tanh`/`relu`/`linear`; letzte Schicht
linear = Logits), `auswahl` (größter Logit unter den erlaubten Aktionen), `herkunft` (Lauf, Checkpoint mit sha256, Schritte, Versionen),
`hash`. `auswertung` ist frei (nicht im Hash) und steht nur bei ausgewerteten Policies. Schreibt `training/exportiere.py`.

Beim Lauf `v9_lokal_1` zeigt `herkunft.manifest` auf den Laufordner `training/laeufe/v9_lokal_1/`. Der liegt nicht im Repo; sein Manifest
steht in `berichte/v9_lokal_1/manifest.json`, der Checkpoint `bester.zip` (sha256 `aecd97d4c6c4a087…`) nicht.

## Eine neue Policy hierher legen

```bash
python training/exportiere.py --lauf training/laeufe/<lauf> --checkpoint bester    # schreibt ki/policy_<lauf>_bester.json
node tools/ki_liste.mjs                                                            # nimmt sie in ki/policies.json auf
```

Vorher Parität und Auswertung (`docs/EXPERIMENTE.md`). Ins Repo gehören nur Policies, deren Auswertung dokumentiert ist, und immer mit
Status `experimentell`, bis eine Auswertung nach `training/AUSWERTUNG_V9.md` bestanden ist.

## Was die Policy sieht (Schema 2) und was nicht

57 Zahlen über die eigene Lage: Bedürfnisse, Zufriedenheit, Rücklage in Tagen, Alter, Persönlichkeit, Arbeit, Lohn, öffentliche Zahlen der
Stadt (freie Stellen `n/(n+200)`, freie Wohnungen `n/(n+20)`, Arbeitslosenquote von gestern, Lohnsteuersatz), Wohnen, Partner, Kinder,
Freunde, Belastungen und Ereignisse der letzten 30 Tage, Ziel, Tageszeit, Anlass. Die Liste mit Skalen steht in `schema_v2.json`. **Nicht** darin: Namen, Personen-ID, Generation, Geschlecht,
Herkunfts- oder Einzugsmerkmale (Einzug, Sparbeginn, Eltern), Bezüge aus dem Gedächtnis, Zukunft, Zufallszustand, Privates anderer. Auch
Erfahrung, offene Handlung und Plan aus Etappe 2 sieht Schema 2 nicht; ein Schema 3 mit diesen Merkmalen ist für Etappe 3 vorgesehen
(`docs/EXPERIMENTE.md` Abschnitt 8).
`simtest --kipolicy` prüft das statisch, durch Verändern dieser Felder (Beobachtung bitgleich) und je Personenfeld.

Die Maske ist `erlaubteAktionen` der Regeln. Sie nutzt mehr, als die Person weiß (Marktdaten, Zufriedenheit des Partners, in Version 9
auch den Weltmarkt bei Gründungen). Das ist indirektes Wissen: Die Policy erfährt nur, welche Aktionen erlaubt sind.

Schema 1 (Version 8, 56 Merkmale, Hash `29e54073`) unterschied sich in drei Punkten: kein `lohnsteuer`, `stellen_frei` und
`wohnungen_frei` mit Sättigung bei 50 (in Version 9 war `stellen_frei` dadurch immer 1). Policies für Version 8 lehnt das Spiel ab.
