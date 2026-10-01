# Entscheidungen Noah zu Etappe 2 (29.09.2026, AskUserQuestion)

> **Ablage im Repo (Etappe 2, Schritt 5, 01.10.2026).** Bericht aus dem Arbeitsordner der Sitzung, inhaltlich unverändert (sha256 des
> Originals in `quellen.sha256`). Bereinigt sind nur Pfade: Der absolute Pfad des Arbeitsordners heißt hier `SP`, das Repo `<repo>`.
> `E` = `SP/ml/e2bau` liegt nicht im Repo; `E/stadt` ist der Ordner, der als `stadt/` ins Repo kommt. Was aus `E/mess/…` hier liegt,
> steht unter `mess/…` neben diesem Bericht (Liste in `LIESMICH.md`); Werkzeuge aus `E/werkzeug/…`, die die Doku braucht, liegen in
> `tools/` (ebenfalls dort aufgeführt). Alles andere aus `SP` (Rohdaten, Sicherungen, Prototypen) ist nicht mitgeliefert.

1. Namen im Gedächtnis (memName): STREICHEN (Empfehlung). Erinnerungen nennen die Beziehung statt des Namens.
2. Rücklage vor Gründung: ALLE GRÜNDER sparen erst (gegen die Empfehlung „nur nach Pleite“; gemessen in C: Gründungen −12 %, Kasse Jahr 1 −9 %, weniger Pleiten, kleinstes Budget 770).
3. Elternzeit: LERNEN LASSEN (gegen die Empfehlung „ausnehmen“): Elternzeit-Kündigungen werden wie andere Kündigungen als Erfahrung gelernt (gemessen A/C: −72 bis −79 %).
4. Sichtbarkeit: BEIDES – Knopf „Warum?“ in der Personenkarte plus Liste „Heute anders entschieden wegen Erfahrung“ UND stärkere Wirkung der Erfahrung (mehr als 0,5–1 % der Entscheidungen; Gates dürfen nicht leiden).
5. (keine Frage, festgelegt) Die Policy aus Etappe 1 wird mit Version 10 ungültig („neu trainieren“), Regeln entscheiden.
6. (30.09., Nachfrage nach Messung SP/ml/e2bau/mess/anlauf/auswertung.txt, hier mess/anlauf/auswertung.txt) Rücklage vor der Gründung: „ALLE, AB STUFE STADT“ –
   Entscheidung 2 gilt für alle Gründer, aber erst ab der Stufe R.ANLAUF_STUFE (Stadt, 160 Einwohner), damit der Anlauf und
   „Wachstum: schnell“ (Version 9) nicht gebremst werden. Im Code: R.PLAN_RUECKLAGE = 1 als Standard.
7. (30.09., ~11:00 UTC) Gate T rot nach Schritt 1 (+26 %, größere Stadt; Rechner langsamer als am 28.09.): „SCHNELLER MACHEN“ –
   Simulation bitgleich optimieren, Grenze 5000 ms bleibt. Umsetzung: neue Phase „Optimieren“ nach der Kalibrierung (Skript-Konstante NACH7).
8. (30.09., ~13:20 UTC) Stärkere Wirkung (Entscheidung 4) scheitert an Gate 7 (in einzelnen Städten nur 3–11 Wegzieher bis Tag 365):
   „GATE 7 ANPASSEN“ – Gate 7 (Spec: Weggezogene haben im Schnitt ≥ 15 Punkte weniger Heimatliebe als alle Erwachsenen) wird nur
   gewertet, wenn bis Tag 365 mindestens 15 Leute weggezogen sind; sonst „nicht gewertet (n = …)“ und so auch gezählt/berichtet.
   Das ist eine bewusste Änderung einer Spec-Regel durch Noah. Danach Stärke neu wählen (stärkste Stufe, die alle Gates hält).
9. (30.09., ~16:30 UTC) Nach dem Nachkalibrieren (Stufe 4 gewählt, Gate 7 dann nur in 26 von 80 Städten gewertet): „STÄRKE 1,5“ –
   R.GED_STAERKE = 1.5 (Gate 7 in 58 von 80 Städten gewertet, ~14 Fälle pro Stadt und Tag in der Liste, 0,89 % der Entscheidungen anders).
10. (30.09., ~19:30 UTC) Nach einer Pleite gründete fast niemand mehr (1,4 % statt 14,3 % ohne Erfahrung): „ERFAHRUNG VERBLASST“ –
    eine Erfahrung wird mit der Zeit schwächer; wer pleite war, zögert lange, versucht es aber irgendwann wieder (Ziel: nach 1–2 Jahren
    wieder denkbar, Sparsame später). Umsetzung: Phase „Verblassen“ nach Speicherformat (Skript-Konstante NACH10), gemessen, Gates halten.
