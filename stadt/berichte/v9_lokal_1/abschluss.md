# Auswertung v9_lokal_1_bester (abschluss 30000–30031, 32 Paare je Gruppe, 30 Tage)

Policy „v9_lokal_1_bester“ (experimentell, Hash 28385759bed1db02, 155648 Trainingsschritte, Lauf v9_lokal_1, Checkpoint bester.zip). Sim 3b1a95e0e5ae9ea5, Belohnung belohnung_v2. Hauptmetrik: mittleres Bedürfnisdefizit (100 − Zufriedenheit) je Stunde der Fokusperson, Wegzug zählt die fehlenden Stunden mit 100. Kleiner ist besser. Intervalle: 95 % mit t-Quantil. Laufzeit 120.8 s.

| Gruppe | Paare | Defizit regeln (Streuung; ±95 %) | Defizit policy (Streuung; ±95 %) | Defizit zufall (Streuung; ±95 %) | Differenz Regeln − Policy (Streuung; ±95 %) | relativ (95 %) | besser/schlechter/gleich | zählt |
|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | 32 | 32.8 (19.1; ±6.9) | 24.5 (12.4; ±4.5) | 34.6 (15.2; ±5.5) | 8.26 (13.49; ±4.86) | 25.2 % (10.4 % … 40.0 %) | 21/11/0 | ja |
| mit_kind | 32 | 38.8 (23.0; ±8.3) | 30.3 (23.8; ±8.6) | 41.3 (24.5; ±8.8) | 8.58 (10.21; ±3.68) | 22.1 % (12.6 % … 31.6 %) | 29/3/0 | ja |
| wenig_kontakt | 32 | 36.2 (15.9; ±5.7) | 25.1 (16.7; ±6.0) | 50.7 (18.0; ±6.5) | 11.13 (15.92; ±5.74) | 30.7 % (14.9 % … 46.6 %) | 26/6/0 | ja |
| gruendungsnah | 32 | 39.0 (14.1; ±5.1) | 27.8 (16.4; ±5.9) | 46.0 (18.5; ±6.7) | 11.29 (11.54; ±4.16) | 28.9 % (18.3 % … 39.6 %) | 27/5/0 | ja |
| rentennah | 32 | 29.3 (19.7; ±7.1) | 24.7 (19.5; ±7.0) | 34.7 (21.4; ±7.7) | 4.64 (10.06; ±3.63) | 15.8 % (3.4 % … 28.2 %) | 20/12/0 | ja |

| Gruppe | Arm | Entsch. | ausgeführt | ohne Erfolg | abgelehnt | gewartet | Maske verl. | Rückfall | Umkehr | Notstand | Wegzug | Ziele err./aufg. | Gründungen (Fehl-) | Kinder | leere Treffen (ohne Gegenüber/ohne Bedarf) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ohne_arbeit | regeln | 1894 | 801 | 0 | 0 | 1093 | 0 | 0 | 341 | 1.9 % | 1 | 27/8 | 3 (0) | 1 | 0/96 |
| ohne_arbeit | policy | 1915 | 608 | 1 | 0 | 1306 | 0 | 0 | 11 | 0.9 % | 1 | 17/8 | 2 (0) | 0 | 0/34 |
| ohne_arbeit | zufall | 1897 | 1196 | 3 | 29 | 669 | 0 | 0 | 564 | 1.1 % | 1 | 24/8 | 10 (0) | 10 | 0/84 |
| mit_kind | regeln | 1907 | 586 | 2 | 0 | 1319 | 0 | 0 | 20 | 6.7 % | 1 | 13/9 | 2 (0) | 0 | 0/122 |
| mit_kind | policy | 1951 | 717 | 1 | 0 | 1233 | 0 | 0 | 8 | 3.4 % | 0 | 4/10 | 0 (0) | 0 | 0/40 |
| mit_kind | zufall | 1843 | 1067 | 1 | 18 | 757 | 0 | 0 | 330 | 7.1 % | 2 | 12/9 | 6 (0) | 6 | 0/106 |
| wenig_kontakt | regeln | 1964 | 707 | 39 | 0 | 1218 | 0 | 0 | 49 | 0.7 % | 0 | 37/2 | 6 (0) | 4 | 4/52 |
| wenig_kontakt | policy | 1933 | 811 | 60 | 4 | 1058 | 0 | 0 | 9 | 2.1 % | 1 | 21/1 | 0 (0) | 0 | 13/63 |
| wenig_kontakt | zufall | 1879 | 1084 | 144 | 5 | 646 | 0 | 0 | 457 | 7.1 % | 3 | 28/1 | 5 (2) | 3 | 13/35 |
| gruendungsnah | regeln | 1948 | 451 | 1 | 0 | 1496 | 0 | 0 | 52 | 0.2 % | 0 | 20/8 | 4 (0) | 0 | 1/38 |
| gruendungsnah | policy | 1897 | 612 | 18 | 3 | 1264 | 0 | 0 | 7 | 1.3 % | 0 | 11/9 | 0 (0) | 0 | 9/35 |
| gruendungsnah | zufall | 1868 | 1111 | 44 | 5 | 708 | 0 | 0 | 422 | 2.1 % | 1 | 15/10 | 3 (1) | 4 | 5/95 |
| rentennah | regeln | 1797 | 562 | 0 | 0 | 1235 | 0 | 0 | 5 | 3.1 % | 1 | 15/10 | 0 (0) | 0 | 0/96 |
| rentennah | policy | 1614 | 623 | 22 | 1 | 968 | 0 | 0 | 2 | 3.6 % | 0 | 7/10 | 0 (0) | 0 | 0/23 |
| rentennah | zufall | 1631 | 929 | 55 | 3 | 644 | 0 | 0 | 357 | 3.8 % | 1 | 12/10 | 0 (0) | 0 | 0/83 |

Aktionen (alle Gruppen; gewählt / davon ausgeführt):

| Aktion | regeln | policy | zufall |
|---|---|---|---|
| warten | 6361 / 0 | 5829 / 0 | 3424 / 0 |
| wohnung_suchen | 7 / 3 | 6 / 3 | 10 / 3 |
| job_suchen | 229 / 229 | 56 / 56 | 865 / 865 |
| job_wechseln | 118 / 118 | 35 / 29 | 557 / 544 |
| kuendigen | 209 / 209 | 34 / 34 | 871 / 871 |
| freinehmen | 342 / 342 | 1310 / 1309 | 1191 / 1191 |
| freunde_treffen | 2165 / 2165 | 1895 / 1895 | 1772 / 1772 |
| partner_suchen | 48 / 10 | 126 / 26 | 291 / 51 |
| zusammenziehen | 8 / 8 | 15 / 15 | 37 / 34 |
| trennen | 1 / 1 | 2 / 2 | 3 / 3 |
| kind_bekommen | 5 / 5 | 0 / 0 | 23 / 23 |
| laden_gruenden | 15 / 15 | 2 / 2 | 68 / 24 |
| wegziehen | 2 / 2 | 0 / 0 | 6 / 6 |

Persönlichkeit (Pearson r, Merkmal gegen Anteil der Aktion an den Entscheidungen, alle Episoden):

| Paar | regeln | policy | zufall |
|---|---|---|---|
| gesellig~freunde_treffen+partner_suchen | 0.32 | -0.11 | 0.05 |
| ehrgeiz~job_wechseln+laden_gruenden | 0.01 | -0.03 | -0.24 |
| fleiss~freinehmen | -0.04 | -0.12 | -0.14 |
| heimat~wegziehen | -0.04 | 0.00 | -0.01 |
| spar~kuendigen | -0.08 | 0.06 | 0.17 |

Kontrollmessung (nur gemessen, die Policy sieht es nicht; „ohne Eltern in der Stadt“ = Startbevölkerung oder zugezogen): regeln: ohne Eltern in der Stadt n=159 Defizit 35.2, in der Stadt geboren n=1 Defizit 47.0; policy: ohne Eltern in der Stadt n=159 Defizit 26.3, in der Stadt geboren n=1 Defizit 47.0; zufall: ohne Eltern in der Stadt n=159 Defizit 41.3, in der Stadt geboren n=1 Defizit 62.3

Nebenmetriken (AUSWERTUNG_V9.md): 16 von 26 in Toleranz.

| Prüfung | ok | Policy | Grenze |
|---|---|---|---|
| notstand_ohne_arbeit | ja | 0.0093 | ≤ 0.0394 (Regeln + 2 pp) |
| wegzug_ohne_arbeit | ja | 1 | ≤ 1 (Regeln) |
| notstand_mit_kind | ja | 0.0336 | ≤ 0.0873 (Regeln + 2 pp) |
| wegzug_mit_kind | ja | 0 | ≤ 1 (Regeln) |
| notstand_wenig_kontakt | ja | 0.0208 | ≤ 0.0272 (Regeln + 2 pp) |
| wegzug_wenig_kontakt | **nein** | 1 | ≤ 0 (Regeln) |
| notstand_gruendungsnah | ja | 0.0133 | ≤ 0.0223 (Regeln + 2 pp) |
| wegzug_gruendungsnah | ja | 0 | ≤ 0 (Regeln) |
| notstand_rentennah | ja | 0.0363 | ≤ 0.0513 (Regeln + 2 pp) |
| wegzug_rentennah | ja | 0 | ≤ 1 (Regeln) |
| ziele_erreicht | **nein** | 60 | ≥ 89.6 (0,8 × Regeln 112) |
| gruendungen | **nein** | 2 | Regeln 15: 0,5× bis 2× |
| fehlgruendungen | ja | 0 | ≤ 2 (Regeln + 2) |
| kinder | **nein** | 0 | Regeln 5: 0,5× bis 2× |
| leere_treffen | ja | 217 | ≤ 618.5 (1,5 × Regeln 409 + 5) |
| charakter_gesellig~freunde_treffen+partner_suchen | **nein** | -0.106 | Vorzeichen wie Regeln (0.320), |r| ≥ 0.160 |
| charakter_ehrgeiz~job_wechseln+laden_gruenden | ja | -0.031 | frei (Regeln |r| 0.009 < 0,1) |
| charakter_fleiss~freinehmen | ja | -0.118 | frei (Regeln |r| 0.041 < 0,1) |
| charakter_heimat~wegziehen | ja | 0 | frei (Regeln |r| 0.037 < 0,1) |
| charakter_spar~kuendigen | ja | 0.059 | frei (Regeln |r| 0.078 < 0,1) |
| stadt_neu_einwohner | **nein** | 203 | ≥ 424 (0,9 × Regeln 471) |
| stadt_neu_kasse | **nein** | 112491 | ≥ 169640 (Regeln 212050 − 20 %) |
| stadt_neu_gruendungen | **nein** | 14 | ≥ 54.0 (0,5 × Regeln 108) |
| stadt_gewachsen_einwohner | **nein** | 2412 | ≥ 2877 (0,9 × Regeln 3197) |
| stadt_gewachsen_kasse | ja | 2060096 | ≥ 1613853 (Regeln 2017316 − 20 %) |
| stadt_gewachsen_gruendungen | **nein** | 4 | ≥ 112.0 (0,5 × Regeln 224) |

Urteil: **NICHT BESTANDEN** (Gruppen mit ≥ 10 %, Untergrenze über 0 und ≥ 0,5 Punkte: 5 von 5; Invarianten ok; Nebenmetriken nicht alle in Toleranz; ≥ 20 Paare je Gruppe ja; Trainingsläufe 1). Regeln bleiben Standard, solange nicht „BESTANDEN“.
