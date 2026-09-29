# Auswertung v9_lokal_1_letzter (validierung 20016–20031, 32 Paare je Gruppe, 30 Tage)

Policy „v9_lokal_1_letzter“ (experimentell, Hash 4654c8bc3689895c, 155648 Trainingsschritte, Lauf v9_lokal_1, Checkpoint letzter.zip). Sim 3b1a95e0e5ae9ea5, Belohnung belohnung_v2. Hauptmetrik: mittleres Bedürfnisdefizit (100 − Zufriedenheit) je Stunde der Fokusperson, Wegzug zählt die fehlenden Stunden mit 100. Kleiner ist besser. Intervalle: 95 % mit t-Quantil. Laufzeit 83.9 s.

| Gruppe | Paare | Defizit regeln (Streuung; ±95 %) | Defizit policy (Streuung; ±95 %) | Differenz Regeln − Policy (Streuung; ±95 %) | relativ (95 %) | besser/schlechter/gleich | zählt |
|---|---|---|---|---|---|---|---|
| ohne_arbeit | 32 | 28.7 (14.8; ±5.3) | 22.6 (8.2; ±3.0) | 6.14 (13.75; ±4.96) | 21.4 % (4.1 % … 38.6 %) | 18/14/0 | ja |
| mit_kind | 32 | 34.8 (18.7; ±6.8) | 27.8 (20.9; ±7.5) | 6.99 (10.54; ±3.80) | 20.1 % (9.2 % … 31.0 %) | 23/9/0 | ja |
| wenig_kontakt | 32 | 40.1 (16.7; ±6.0) | 28.3 (12.2; ±4.4) | 11.88 (18.09; ±6.52) | 29.6 % (13.4 % … 45.9 %) | 25/7/0 | ja |
| gruendungsnah | 32 | 35.1 (12.9; ±4.7) | 25.0 (14.0; ±5.0) | 10.15 (11.80; ±4.25) | 28.9 % (16.8 % … 41.0 %) | 26/6/0 | ja |
| rentennah | 32 | 28.5 (19.5; ±7.0) | 22.2 (17.1; ±6.2) | 6.27 (8.43; ±3.04) | 22.0 % (11.3 % … 32.7 %) | 22/10/0 | ja |

| Gruppe | Arm | Entsch. | ausgeführt | ohne Erfolg | abgelehnt | gewartet | Maske verl. | Rückfall | Umkehr | Notstand | Wegzug | Ziele err./aufg. | Gründungen (Fehl-) | Kinder | leere Treffen (ohne Gegenüber/ohne Bedarf) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | regeln | 1947 | 678 | 17 | 0 | 1252 | 0 | 0 | 110 | 0.1 % | 0 | 32/7 | 3 (0) | 3 | 9/101 |
| ohne_arbeit | policy | 1948 | 580 | 13 | 0 | 1355 | 0 | 0 | 5 | 0.1 % | 0 | 18/7 | 0 (0) | 0 | 4/35 |
| mit_kind | regeln | 1933 | 666 | 13 | 0 | 1254 | 0 | 0 | 34 | 0.2 % | 0 | 8/6 | 2 (0) | 3 | 0/138 |
| mit_kind | policy | 1931 | 688 | 7 | 0 | 1236 | 0 | 0 | 3 | 0.8 % | 0 | 1/7 | 0 (0) | 0 | 0/47 |
| wenig_kontakt | regeln | 1934 | 729 | 76 | 0 | 1129 | 0 | 0 | 61 | 4.5 % | 2 | 39/1 | 5 (1) | 1 | 27/57 |
| wenig_kontakt | policy | 1953 | 849 | 30 | 4 | 1070 | 0 | 0 | 6 | 0.0 % | 0 | 20/2 | 0 (0) | 0 | 46/67 |
| gruendungsnah | regeln | 1907 | 360 | 56 | 0 | 1491 | 0 | 0 | 8 | 0.7 % | 0 | 7/12 | 1 (0) | 0 | 0/27 |
| gruendungsnah | policy | 1865 | 583 | 20 | 1 | 1261 | 0 | 0 | 12 | 0.8 % | 0 | 4/12 | 0 (0) | 0 | 2/49 |
| rentennah | regeln | 1805 | 569 | 1 | 0 | 1235 | 0 | 0 | 5 | 4.6 % | 3 | 24/14 | 0 (0) | 0 | 0/132 |
| rentennah | policy | 1634 | 626 | 7 | 1 | 1000 | 0 | 0 | 3 | 2.1 % | 1 | 11/14 | 0 (0) | 0 | 0/6 |

Aktionen (alle Gruppen; gewählt / davon ausgeführt):

| Aktion | regeln | policy |
|---|---|---|
| warten | 6361 / 0 | 5922 / 0 |
| wohnung_suchen | 12 / 3 | 5 / 2 |
| job_suchen | 119 / 119 | 49 / 49 |
| job_wechseln | 96 / 96 | 34 / 30 |
| kuendigen | 97 / 97 | 32 / 32 |
| freinehmen | 320 / 320 | 1262 / 1262 |
| freunde_treffen | 2318 / 2318 | 1913 / 1913 |
| partner_suchen | 167 / 13 | 100 / 25 |
| zusammenziehen | 13 / 13 | 11 / 10 |
| trennen | 2 / 2 | 3 / 3 |
| kind_bekommen | 7 / 7 | 0 / 0 |
| laden_gruenden | 11 / 11 | 0 / 0 |
| wegziehen | 3 / 3 | 0 / 0 |

Persönlichkeit (Pearson r, Merkmal gegen Anteil der Aktion an den Entscheidungen, alle Episoden):

| Paar | regeln | policy |
|---|---|---|
| gesellig~freunde_treffen+partner_suchen | 0.24 | -0.10 |
| ehrgeiz~job_wechseln+laden_gruenden | 0.07 | -0.07 |
| fleiss~freinehmen | 0.05 | -0.04 |
| heimat~wegziehen | -0.16 | 0.00 |
| spar~kuendigen | -0.11 | -0.11 |

Kontrollmessung (nur gemessen, die Policy sieht es nicht; „ohne Eltern in der Stadt“ = Startbevölkerung oder zugezogen): regeln: ohne Eltern in der Stadt n=156 Defizit 33.1, in der Stadt geboren n=4 Defizit 49.0; policy: ohne Eltern in der Stadt n=156 Defizit 24.7, in der Stadt geboren n=4 Defizit 43.2

Nebenmetriken (AUSWERTUNG_V9.md): 16 von 26 in Toleranz.

| Prüfung | ok | Policy | Grenze |
|---|---|---|---|
| notstand_ohne_arbeit | ja | 0.0015 | ≤ 0.0215 (Regeln + 2 pp) |
| wegzug_ohne_arbeit | ja | 0 | ≤ 0 (Regeln) |
| notstand_mit_kind | ja | 0.0075 | ≤ 0.0216 (Regeln + 2 pp) |
| wegzug_mit_kind | ja | 0 | ≤ 0 (Regeln) |
| notstand_wenig_kontakt | ja | 0 | ≤ 0.0654 (Regeln + 2 pp) |
| wegzug_wenig_kontakt | ja | 0 | ≤ 2 (Regeln) |
| notstand_gruendungsnah | ja | 0.0079 | ≤ 0.0265 (Regeln + 2 pp) |
| wegzug_gruendungsnah | ja | 0 | ≤ 0 (Regeln) |
| notstand_rentennah | ja | 0.0214 | ≤ 0.0664 (Regeln + 2 pp) |
| wegzug_rentennah | ja | 1 | ≤ 3 (Regeln) |
| ziele_erreicht | **nein** | 54 | ≥ 88.0 (0,8 × Regeln 110) |
| gruendungen | **nein** | 0 | Regeln 11: 0,5× bis 2× |
| fehlgruendungen | ja | 0 | ≤ 3 (Regeln + 2) |
| kinder | **nein** | 0 | Regeln 7: 0,5× bis 2× |
| leere_treffen | ja | 256 | ≤ 741.5 (1,5 × Regeln 491 + 5) |
| charakter_gesellig~freunde_treffen+partner_suchen | **nein** | -0.097 | Vorzeichen wie Regeln (0.235), |r| ≥ 0.118 |
| charakter_ehrgeiz~job_wechseln+laden_gruenden | ja | -0.071 | frei (Regeln |r| 0.071 < 0,1) |
| charakter_fleiss~freinehmen | ja | -0.035 | frei (Regeln |r| 0.052 < 0,1) |
| charakter_heimat~wegziehen | **nein** | 0 | Vorzeichen wie Regeln (-0.162), |r| ≥ 0.081 |
| charakter_spar~kuendigen | ja | -0.111 | Vorzeichen wie Regeln (-0.110), |r| ≥ 0.055 |
| stadt_neu_einwohner | **nein** | 136 | ≥ 424 (0,9 × Regeln 471) |
| stadt_neu_kasse | **nein** | 110805 | ≥ 140946 (Regeln 176182 − 20 %) |
| stadt_neu_gruendungen | **nein** | 6 | ≥ 51.0 (0,5 × Regeln 102) |
| stadt_gewachsen_einwohner | **nein** | 2312 | ≥ 2589 (0,9 × Regeln 2877) |
| stadt_gewachsen_kasse | ja | 2081762 | ≥ 1598654 (Regeln 1998318 − 20 %) |
| stadt_gewachsen_gruendungen | **nein** | 6 | ≥ 138.0 (0,5 × Regeln 276) |

Urteil: **nur validierung (keine Freigabe)** (Gruppen mit ≥ 10 %, Untergrenze über 0 und ≥ 0,5 Punkte: 5 von 5; Invarianten ok; Nebenmetriken nicht alle in Toleranz; ≥ 20 Paare je Gruppe ja; Trainingsläufe 1). Regeln bleiben Standard, solange nicht „BESTANDEN“.
