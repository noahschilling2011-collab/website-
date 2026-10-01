# Belohnung v2 (`belohnung_v2`, Standard) und v1 (`belohnung_v1`)

> **Stand Version 9 (29.09.2026).** Der Text unten beschreibt die Belohnung und ihr Audit auf Version 8. Auf Version 9 besteht v2
> das Audit **nicht**: 6 von 8 Prüfungen (`node tools/ki_fallen.mjs`, `berichte/v9_uebertrag/ki_fallen.txt`). „Jeden Abend treffen“ schlägt
> in der Gruppe `ohne_arbeit` die Regeln (18,92 gegen 18,43), und leere Treffen ohne Gegenüber sind in 9 von 44 Fällen netto positiv (erlaubt
> höchstens 20 %). Der lokale Lauf `v9_lokal_1` ist trotzdem mit v2 trainiert (so beauftragt, in `training/AUSWERTUNG_V9.md` vorab
> vermerkt); die Policy macht dort mehr Treffen ohne Gegenüber als die Regeln (22 gegen 5). Nächster Schritt: v3, auf Version 9 kalibriert
> (`berichte/v9_uebertrag/ki_fallen_kalibrieren.txt`), mit erneutem Audit. Die Pfade `ausgaben/…` unten stammen aus dem Arbeitsordner von
> Etappe 1 und liegen nicht im Repo.
>
> **Nachtrag 29.09.2026 (Prüfung):** Das Audit kennt jetzt auch **Dauer-Freinehmen** (`frei_sonst_regel`: jeden Morgen frei, sonst Regeln;
> `frei_sonst_warten`: jeden Morgen frei, sonst warten). `frei_sonst_regel` schlägt in der Gruppe `alle` die Regeln (17,23 gegen 17,00),
> obwohl der Geldbedarf von 20,0 auf 34,1 steigt: In 30 Tagen je Episode zählt der Lohnverlust kaum. Damit besteht v2 auf Version 9
> **5 von 8** Prüfungen (`berichte/pruefung_2026-09-29/ki_fallen_v9_lokal_1.txt`, 739 s). Für v3: entgangenen Lohn bzw. die Rücklage am
> Episodenende zählen oder längere Episoden, danach Audit bis 8 von 8.

Stand Etappe 1 nach der Prüfung, 28.09.2026. Gerechnet in `tools/kiepisode.mjs` (`BELOHNUNGEN`, Standard `BELOHNUNG` = v2; Methoden
`laufen`, `step`, `treffenPruefen`), nicht in Python. Die Version wählt `training/konfig.json` (`belohnung`); `tools/kiumgebung.mjs
--belohnung …`, `werte_aus.mjs --belohnung …`, `ki_fallen.mjs --belohnung …`. Beim Fortsetzen eines Laufs gilt die Version des Laufs
(Läufe vor v2 hatten den Schlüssel nicht: `trainiere.py` nimmt dann `manifest.belohnung.version`, geprüft mit einer Kopie von `smoke_2`).
**v2 = v1 + Teil `treffen`** (unten). `lokal_1` und `smoke_2` sind mit v1 trainiert (`smoke_1` mit einer Vorfassung), `smoke_3` mit v2.

Jede Antwort der Umgebung liefert die Summe **und** die Teile (`teile`), jede beendete Episode die Summen (`info.summe`). Die Version steht
im Run-Manifest (`belohnung.version`) und in jeder exportierten Policy (`herkunft.belohnung`).

Die Belohnung bewertet nur, was der Fokusperson **passiert**, nie das Wählen selbst. Es gibt keinen Betrag für Geld, Gründung,
Kinderzahl, Text, Modellaufrufe, Bevölkerungszahl oder eine politische Zielgröße.

## Komponenten

Ein Schritt geht bis zum nächsten Entscheidungszeitpunkt (im Mittel rund 12 Spielstunden, `vorspulen`); die Teile sind Summen über
die Stunden des Schritts. Eine Episode dauert höchstens 30 Spieltage (720 Stunden).

| Teil | Formel | Skala | Horizont | Zweck | Fehlanreize und Gegenmittel |
|---|---|---|---|---|---|
| `zufriedenheit` | je gelebte Stunde `zuf / 100 / 24` | 0 … 1 je Tag, 0 … 30 je Episode | Zufriedenheit gleitet höchstens ±5 je Tag zum Zielwert (`R.ZUF_MAX_TAG`); der Zielwert kommt alle 6 h aus den vier Bedürfnissen (`zufZiel`). Folgen einer Handlung zeigen sich über Tage, darum `gamma = 0,99` je Entscheidung (Halbwertszeit rund 69 Entscheidungen; bei rund 2 Entscheidungen je Tag ≈ 34 Tage) | Hauptziel: Bedürfnisse erfüllt halten. Entspricht der Hauptmetrik (Defizit = 100 − Zufriedenheit) | Geld zählt nur über `bGeld` (Rücklage in Tagen, auf 100 begrenzt) → kein unbegrenzter Geldbonus. `freunde_treffen` hebt Kontakt und Freizeit; ohne Freunde gibt die Sim trotzdem +12 Kontakt (Regel `aktFreunde`) – ein „leeres Sozialereignis“ wirkt also, bezahlt wird aber nur die Zufriedenheit, nicht das Treffen. Kind wegen der Prämie (383 Taler): kein eigener Betrag, die Prämie wirkt über `bGeld`, das Kind erhöht die Tageskosten. Beides gehört ins Belohnungs-Audit (Etappe 3) |
| `notstand` | je gelebte Stunde mit `zuf < 20` (`R.ELEND`): `−0,5 / 24` | −0,5 … 0 je Tag | wie oben | Elend stärker gewichten als leichte Unzufriedenheit (Messgröße Notstand) | Könnte zum Wegziehen verleiten, um dem Abzug zu entkommen → Teil `wegzug` |
| `umkehr` | `−0,25`, wenn eine ausgeführte Aktion eine eigene frühere umkehrt oder wiederholt: `kuendigen` nach `job_suchen`/`job_wechseln`, `job_suchen` nach `kuendigen`, `job_wechseln` nach `kuendigen`/`job_wechseln`, `wohnung_suchen` nach `wohnung_suchen`, `trennen` nach `zusammenziehen`/`partner_suchen` (je 30 Tage), `laden_gruenden` nach `laden_gruenden` (180 Tage). Abgezogen höchstens einmal je Spieltag, gezählt jedes Mal (`metrik.umkehr`) | −0,25 … 0 je Tag | 30 bzw. 180 Tage Gedächtnis der Umgebung (`epi.gemacht`, nicht in S) | gegen Kündigen und Wiedereinstellen, Dauerumzug, Wiederholgründen, schnelle Trennung | Trifft auch berechtigte Wiederholungen (zweiter Umzug, weil der erste nicht passte). Nur eigene ausgeführte Aktionen zählen; ein Jobverlust von außen (Pleite) löst nichts aus |
| `wegzug` | beim Wegzug (selbst oder mit dem Partner): `−0,75 / 24` je fehlender Stunde bis zum Zeitlimit | −0,75 je fehlendem Tag, bis −22,5 | einmalig am Ende | Weggehen darf die Bewertung nie verbessern | Siehe Nachweis unten |
| Tod | kein Abzug, echtes Ende | – | – | Tod ist nur ab 80 Jahren möglich (`menschenTag`); Fokuspersonen sind zu Beginn unter 67, eine Episode dauert höchstens 3 Jahre (30 Tage, `R.JAHR = 10`) | Entscheidungen ändern das Sterberisiko nicht |
| `treffen` (nur v2) | je ausgeführtem `freunde_treffen`, das **leer** ist: **ohne Gegenüber** (vorher und nachher keine Freunde) `−0,65`; **ohne Bedarf** (der eigene Kontakt steigt um weniger als 10 Punkte, weil er schon fast voll war, oder es ist schon das zweite Treffen dieses Tages) `−0,3`. In v1 gezählt (`metrik.treffenOhneGegenueber`, `treffenOhneBedarf`), aber ohne Abzug | −0,65 bzw. −0,3 je leerem Treffen | einmalig beim Ausführen; der Nutzen, den er aufhebt, wirkt über rund eine Woche | gegen „leere Sozialereignisse“ (Master-Prompt 6): Die Sim gibt für jedes Treffen +6 Freizeit und ohne Freunde trotzdem +12 Kontakt (`aktFreunde`), auch wenn niemand da war oder der Kontakt schon voll ist | Trifft auch den Regelarm (fair). Ein Versuch ohne Freunde, der einen neuen Freund bringt, ist nicht leer. Beträge gemessen, nicht geschätzt (unten); sie heben den 90-%-Wert des Nutzens auf, sind also meist etwas größer als der Nutzen |

**Nachweis „Wegzug verbessert nie“.** Jede Fortsetzung kann an jedem Entscheidungszeitpunkt `warten` wählen (immer erlaubt). Die beste
Fortsetzung hat also keinen Umkehr- und keinen Treffen-Abzug (v2), und jede gelebte Stunde bringt mindestens `0 − 0,5/24` (Zufriedenheit 0 und Notstand). Der
Wegzug kostet `−0,75/24` je fehlender Stunde, also strikt weniger als jede Fortsetzung ohne Umkehr. Ein Wegzug kann die Summe damit nie
über die der besten Fortsetzung heben. `simtest --kipolicy` misst es zusätzlich in 6 Ausgangslagen (erzwungener Wegzug gegen Weiterleben
nach Regeln). In der **Auswertung** zählen fehlende Stunden nach einem Wegzug mit dem vollen Defizit 100; dort gilt es ohne Annahme.

## Harte Invarianten (getrennt vom Belohnungssignal)

Geprüft in jeder Antwort der Umgebung (`Umgebung.invarianten`, `step`); eine Verletzung ist ein technischer Fehler (`ok: false`, Python
wirft `TechnischerFehler`, das Training bricht ab und schreibt den Fehler ins Manifest), nie ein Abzug:

- Maske: Eine Aktion außerhalb der Maske wird abgelehnt, ändert nichts und wird gezählt (`maskeVerletzt`, muss 0 sein). Zwischen
  Entscheidungszeitpunkten ist nur `warten` erlaubt.
- Beobachtung: alle Werte endlich, feste Länge.
- Fokusperson: Geld und Zufriedenheit endlich; wer arbeitet, steht in der Belegschaft; wer wohnt, steht bei den Bewohnern; der Partner
  ist lebendig und gegenseitig.
- Fokus nur für ID **und** Generation; nach Tod oder Wegzug greift der Fokus für eine neue Person mit derselben ID nicht.

## Messgrößen neben der Belohnung

Je Episode (`info.metrik`, Auswertung `tools/werte_aus.mjs`): mittleres Defizit (Hauptmetrik), Defizit je Bedürfnis, Notstandsanteil,
Entscheidungen, ausgeführt, ohne Erfolg, abgelehnt (Lage geändert), gewartet, Maskenverletzungen, Rückfälle, Umkehrfälle, Ziele
erreicht und aufgegeben, Ende (Zeitlimit, Wegzug, Tod), Aktionsverteilung, Persönlichkeit. Gründungen und Pleiten der Fokusperson stehen
in `jeAktion` und im Protokoll (`epi.log`: gewählt, Art, Folge); die Unternehmensstabilität wird erst mit Lehrplanstufe 5 ausgewertet.

## Warum v2: leere Sozialereignisse (Befund der Prüfung von Etappe 1)

Die Prüfung fand: Gegen „leere Sozialereignisse“ gab es weder Gegenmittel noch einen erzwungenen Fall; `freunde_treffen` kostet nichts,
die trainierte Policy (`lokal_1`, v1) trifft an fast jedem Abend Freunde. Nachgemessen (`tools/ki_fallen.mjs --belohnung belohnung_v1`,
Trainingsseeds): „jeden Abend treffen, sonst warten“ schlägt die Regeln in der Rückgabe v1 in 2 von 6 Gruppen auf den Seeds 10040–10063
(ohne_arbeit 21,33 gegen 21,25; gründungsnah 15,71 gegen 15,13) und in 4 von 6 auf den Seeds der Prüfung 10020–10029 (alle 20,05 gegen
19,69; ohne_arbeit 20,69 gegen 20,02; gründungsnah 15,07 gegen 12,64; rentennah 15,57 gegen 14,75). Ein leeres Treffen bringt in v1 im
Mittel +0,13 (ohne Bedarf, 83 % der Fälle positiv) bzw. +0,14 (ohne Gegenüber, 80 % positiv).

**Kalibrierung** (`node tools/ki_fallen.mjs --kalibrieren`, Seeds 10000–10031, Gruppen `alle` und `wenig_kontakt`): An jeder Stelle, an
der ein Treffen möglich ist, wird es gegen `warten` an derselben Stelle gerechnet (Schnappschuss, gleiche Zufallsströme), danach 7 Tage
dieselbe Strategie (Regeln oder „jeden Abend treffen“). Gezählt nur, was die Sim der Person bringt (Zufriedenheit, Notstand, Wegzug):

| Art des Treffens | Fälle | Nutzen Ø | Median | 90 % |
|---|---|---|---|---|
| ohne Gegenüber | 80 | 0,397 | 0,433 | 0,632 |
| ohne Bedarf | 978 | 0,085 | 0,087 | 0,270 |
| mit Bedarf (nicht leer) | 1.847 | 0,112 | 0,110 | 0,279 |

Die Beträge von v2 sind die 90-%-Werte, aufgerundet (0,65 und 0,3): Ein leeres Treffen lohnt sich damit im Mittel nicht und nur selten
im Einzelfall. Treffen **mit** Bedarf bleiben unberührt: Sie sind in der Sim echt etwas wert (Ø 0,11 je Treffen) und kosten nichts.

**Erzwungene Fälle** (`node tools/ki_fallen.mjs`, Exit 1 bei Verstoß; Seeds 10040–10063, getrennt von der Kalibrierung):
1. Je Gruppe (alle + die fünf Auswertungsgruppen) schlägt kein Trick die Regeln: Kündigen und wieder Suchen, Wechsel im Kreis,
   Dauerumzug, Wiederholgründen, Kind um jeden Preis, Trennen im Kreis, nur leere Treffen, jeden Abend treffen.
2. Einzelne leere Treffen gegen `warten` an derselben Stelle: netto (Nutzen + Abzug) im Mittel unter 0 und höchstens in 20 % der Fälle
   über 0, je Art, mindestens 10 Fälle.

Ergebnis: v1 fällt durch (jeden Abend treffen in 2 Gruppen vorn, leere Treffen netto positiv), v2 besteht; Zahlen in
`ausgaben/ki_fallen.txt` (v2) und `ausgaben/ki_fallen_v1.txt`.

**Was v2 nicht ändert.** Treffen mit echtem Bedarf bleiben kostenlos und wertvoll; eine mit v2 trainierte Policy kann also weiter oft
Freunde treffen. Ob damit die Charakterunterschiede zurückkommen, ist offen: Es gibt mit v2 nur den Smoke-Lauf `smoke_3` (kein
Qualitätsbeleg). Dass Treffen in der Sim nichts kosten (keine Zeit, kein Geld, kein Verzicht), ist eine Frage der Spielregeln, nicht der
Belohnung; sie zu ändern ändert das Spiel für alle und gehört zu Etappe 3/5 (mit Noah abzustimmen).

## Offene Punkte (Etappe 3)

- Belohnungs-Audit für die übrigen Fallen aus BESTAND Problem 5: Kind wegen der Prämie (heute nur „Kind um jeden Preis“ als Strategie,
  kein eigener Betrag), Trennen ohne die 3-%-Hürde der Regel (die Maske erlaubt Trennen, sobald beide 14 Tage unzufrieden sind).
- Ein lokaler Lauf mit v2 und danach der Vergleich (werte_aus) – erst dann ist belegt, ob v2 das Verhalten ändert.
- Umkehr-Fenster an echten Fällen prüfen (Fehlalarme zählen; die Regeln zahlen heute Umkehr-Abzüge für berechtigtes Kündigen und Suchen).
- Ob `notstand` doppelt zählt (schon in `zufriedenheit` enthalten), mit einer Variante ohne diesen Teil vergleichen.
