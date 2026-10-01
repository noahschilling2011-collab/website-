# Auswertung v9_lokal_1_bester (validierung 20016–20031, 32 Paare je Gruppe, 30 Tage)

Policy „v9_lokal_1_bester“ (experimentell, Hash 28385759bed1db02, 155648 Trainingsschritte, Lauf v9_lokal_1, Checkpoint bester.zip). Sim 3b1a95e0e5ae9ea5, Belohnung belohnung_v2. Hauptmetrik: mittleres Bedürfnisdefizit (100 − Zufriedenheit) je Stunde der Fokusperson, Wegzug zählt die fehlenden Stunden mit 100. Kleiner ist besser. Intervalle: 95 % mit t-Quantil. Laufzeit 120.2 s.

| Gruppe | Paare | Defizit regeln (Streuung; ±95 %) | Defizit policy (Streuung; ±95 %) | Defizit zufall (Streuung; ±95 %) | Differenz Regeln − Policy (Streuung; ±95 %) | relativ (95 %) | besser/schlechter/gleich | zählt |
|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | 32 | 28.7 (14.8; ±5.3) | 22.0 (7.8; ±2.8) | 40.4 (14.5; ±5.2) | 6.79 (13.59; ±4.90) | 23.6 % (6.6 % … 40.6 %) | 18/14/0 | ja |
| mit_kind | 32 | 34.8 (18.7; ±6.8) | 27.7 (20.9; ±7.6) | 40.1 (22.4; ±8.1) | 7.04 (10.55; ±3.80) | 20.2 % (9.3 % … 31.2 %) | 23/9/0 | ja |
| wenig_kontakt | 32 | 40.1 (16.7; ±6.0) | 28.0 (12.0; ±4.3) | 57.8 (13.3; ±4.8) | 12.09 (17.56; ±6.33) | 30.1 % (14.3 % … 45.9 %) | 25/7/0 | ja |
| gruendungsnah | 32 | 35.1 (12.9; ±4.7) | 24.5 (13.2; ±4.8) | 40.3 (17.5; ±6.3) | 10.69 (11.09; ±4.00) | 30.4 % (19.0 % … 41.8 %) | 27/5/0 | ja |
| rentennah | 32 | 28.5 (19.5; ±7.0) | 21.8 (17.2; ±6.2) | 28.9 (19.3; ±6.9) | 6.68 (7.96; ±2.87) | 23.4 % (13.4 % … 33.5 %) | 24/8/0 | ja |

| Gruppe | Arm | Entsch. | ausgeführt | ohne Erfolg | abgelehnt | gewartet | Maske verl. | Rückfall | Umkehr | Notstand | Wegzug | Ziele err./aufg. | Gründungen (Fehl-) | Kinder | leere Treffen (ohne Gegenüber/ohne Bedarf) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | regeln | 1947 | 678 | 17 | 0 | 1252 | 0 | 0 | 110 | 0.1 % | 0 | 32/7 | 3 (0) | 3 | 9/101 |
| ohne_arbeit | policy | 1948 | 624 | 10 | 0 | 1314 | 0 | 0 | 7 | 0.1 % | 0 | 20/7 | 0 (0) | 0 | 4/42 |
| ohne_arbeit | zufall | 1899 | 1115 | 13 | 17 | 754 | 0 | 0 | 406 | 3.6 % | 1 | 31/4 | 14 (0) | 15 | 6/86 |
| mit_kind | regeln | 1933 | 666 | 13 | 0 | 1254 | 0 | 0 | 34 | 0.2 % | 0 | 8/6 | 2 (0) | 3 | 0/138 |
| mit_kind | policy | 1935 | 682 | 7 | 0 | 1246 | 0 | 0 | 2 | 0.8 % | 0 | 1/7 | 0 (0) | 0 | 0/45 |
| mit_kind | zufall | 1868 | 1020 | 20 | 11 | 817 | 0 | 0 | 204 | 5.0 % | 2 | 7/6 | 10 (1) | 9 | 0/109 |
| wenig_kontakt | regeln | 1934 | 729 | 76 | 0 | 1129 | 0 | 0 | 61 | 4.5 % | 2 | 39/1 | 5 (1) | 1 | 27/57 |
| wenig_kontakt | policy | 1956 | 882 | 31 | 2 | 1041 | 0 | 0 | 3 | 0.0 % | 0 | 16/2 | 0 (0) | 0 | 45/80 |
| wenig_kontakt | zufall | 1881 | 1043 | 175 | 13 | 650 | 0 | 0 | 422 | 8.2 % | 3 | 21/2 | 6 (3) | 0 | 35/19 |
| gruendungsnah | regeln | 1907 | 360 | 56 | 0 | 1491 | 0 | 0 | 8 | 0.7 % | 0 | 7/12 | 1 (0) | 0 | 0/27 |
| gruendungsnah | policy | 1871 | 600 | 21 | 0 | 1250 | 0 | 0 | 16 | 0.8 % | 0 | 4/12 | 0 (0) | 0 | 2/60 |
| gruendungsnah | zufall | 1814 | 1121 | 1 | 9 | 683 | 0 | 0 | 530 | 3.3 % | 1 | 7/11 | 0 (0) | 6 | 0/83 |
| rentennah | regeln | 1805 | 569 | 1 | 0 | 1235 | 0 | 0 | 5 | 4.6 % | 3 | 24/14 | 0 (0) | 0 | 0/132 |
| rentennah | policy | 1627 | 613 | 4 | 1 | 1009 | 0 | 0 | 6 | 2.1 % | 1 | 12/14 | 0 (0) | 0 | 0/6 |
| rentennah | zufall | 1668 | 1005 | 24 | 8 | 631 | 0 | 0 | 421 | 3.2 % | 2 | 20/14 | 0 (0) | 0 | 0/86 |

Aktionen (alle Gruppen; gewählt / davon ausgeführt):

| Aktion | regeln | policy | zufall |
|---|---|---|---|
| warten | 6361 / 0 | 5860 / 0 | 3535 / 0 |
| wohnung_suchen | 12 / 3 | 5 / 2 | 8 / 3 |
| job_suchen | 119 / 119 | 54 / 54 | 822 / 822 |
| job_wechseln | 96 / 96 | 26 / 24 | 505 / 466 |
| kuendigen | 97 / 97 | 36 / 36 | 841 / 841 |
| freinehmen | 320 / 320 | 1254 / 1254 | 1257 / 1257 |
| freunde_treffen | 2318 / 2318 | 1989 / 1989 | 1752 / 1752 |
| partner_suchen | 167 / 13 | 99 / 29 | 282 / 51 |
| zusammenziehen | 13 / 13 | 11 / 10 | 40 / 40 |
| trennen | 2 / 2 | 3 / 3 | 4 / 4 |
| kind_bekommen | 7 / 7 | 0 / 0 | 32 / 30 |
| laden_gruenden | 11 / 11 | 0 / 0 | 44 / 30 |
| wegziehen | 3 / 3 | 0 / 0 | 8 / 8 |

Persönlichkeit (Pearson r, Merkmal gegen Anteil der Aktion an den Entscheidungen, alle Episoden):

| Paar | regeln | policy | zufall |
|---|---|---|---|
| gesellig~freunde_treffen+partner_suchen | 0.24 | -0.10 | -0.04 |
| ehrgeiz~job_wechseln+laden_gruenden | 0.07 | -0.06 | 0.01 |
| fleiss~freinehmen | 0.05 | -0.08 | -0.12 |
| heimat~wegziehen | -0.16 | 0.00 | 0.07 |
| spar~kuendigen | -0.11 | -0.10 | 0.26 |

Kontrollmessung (nur gemessen, die Policy sieht es nicht; „ohne Eltern in der Stadt“ = Startbevölkerung oder zugezogen): regeln: ohne Eltern in der Stadt n=156 Defizit 33.1, in der Stadt geboren n=4 Defizit 49.0; policy: ohne Eltern in der Stadt n=156 Defizit 24.4, in der Stadt geboren n=4 Defizit 39.7; zufall: ohne Eltern in der Stadt n=156 Defizit 41.1, in der Stadt geboren n=4 Defizit 55.6

Nebenmetriken (AUSWERTUNG_V9.md): 16 von 26 in Toleranz.

| Prüfung | ok | Policy | Grenze |
|---|---|---|---|
| notstand_ohne_arbeit | ja | 0.0015 | ≤ 0.0215 (Regeln + 2 pp) |
| wegzug_ohne_arbeit | ja | 0 | ≤ 0 (Regeln) |
| notstand_mit_kind | ja | 0.0081 | ≤ 0.0216 (Regeln + 2 pp) |
| wegzug_mit_kind | ja | 0 | ≤ 0 (Regeln) |
| notstand_wenig_kontakt | ja | 0 | ≤ 0.0654 (Regeln + 2 pp) |
| wegzug_wenig_kontakt | ja | 0 | ≤ 2 (Regeln) |
| notstand_gruendungsnah | ja | 0.0079 | ≤ 0.0265 (Regeln + 2 pp) |
| wegzug_gruendungsnah | ja | 0 | ≤ 0 (Regeln) |
| notstand_rentennah | ja | 0.0208 | ≤ 0.0664 (Regeln + 2 pp) |
| wegzug_rentennah | ja | 1 | ≤ 3 (Regeln) |
| ziele_erreicht | **nein** | 53 | ≥ 88.0 (0,8 × Regeln 110) |
| gruendungen | **nein** | 0 | Regeln 11: 0,5× bis 2× |
| fehlgruendungen | ja | 0 | ≤ 3 (Regeln + 2) |
| kinder | **nein** | 0 | Regeln 7: 0,5× bis 2× |
| leere_treffen | ja | 284 | ≤ 741.5 (1,5 × Regeln 491 + 5) |
| charakter_gesellig~freunde_treffen+partner_suchen | **nein** | -0.099 | Vorzeichen wie Regeln (0.235), |r| ≥ 0.118 |
| charakter_ehrgeiz~job_wechseln+laden_gruenden | ja | -0.061 | frei (Regeln |r| 0.071 < 0,1) |
| charakter_fleiss~freinehmen | ja | -0.08 | frei (Regeln |r| 0.052 < 0,1) |
| charakter_heimat~wegziehen | **nein** | 0 | Vorzeichen wie Regeln (-0.162), |r| ≥ 0.081 |
| charakter_spar~kuendigen | ja | -0.097 | Vorzeichen wie Regeln (-0.110), |r| ≥ 0.055 |
| stadt_neu_einwohner | **nein** | 130 | ≥ 424 (0,9 × Regeln 471) |
| stadt_neu_kasse | **nein** | 89833 | ≥ 140946 (Regeln 176182 − 20 %) |
| stadt_neu_gruendungen | **nein** | 3 | ≥ 51.0 (0,5 × Regeln 102) |
| stadt_gewachsen_einwohner | **nein** | 2320 | ≥ 2589 (0,9 × Regeln 2877) |
| stadt_gewachsen_kasse | ja | 2077713 | ≥ 1598654 (Regeln 1998318 − 20 %) |
| stadt_gewachsen_gruendungen | **nein** | 6 | ≥ 138.0 (0,5 × Regeln 276) |

Urteil: **nur validierung (keine Freigabe)** (Gruppen mit ≥ 10 %, Untergrenze über 0 und ≥ 0,5 Punkte: 5 von 5; Invarianten ok; Nebenmetriken nicht alle in Toleranz; ≥ 20 Paare je Gruppe ja; Trainingsläufe 1). Regeln bleiben Standard, solange nicht „BESTANDEN“.
