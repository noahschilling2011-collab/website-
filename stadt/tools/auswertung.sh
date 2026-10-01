#!/bin/bash
# Auswertung eines Trainingslaufs nach training/AUSWERTUNG_V9.md (Kriterien vorab festgelegt, nicht nachträglich ändern). Gleiche Schritte
# wie beim Lauf v9_lokal_1, für jeden Lauf unter training/laeufe/<lauf>. Ergebnisse nach berichte/<lauf>/.
#   bash tools/auswertung.sh validierung <lauf>       Export bester und letzter, Stadtwirkung (20016–20019), gepaarter Vergleich (20016–20031),
#                                                    Kandidatenwahl nach A7
#   bash tools/auswertung.sh abschluss <lauf> <k>     EINMAL je Lauf: Abschlussseeds 30000–30031 für den gewählten Kandidaten k (bester|letzter)
#   bash tools/auswertung.sh export <lauf> <k>        ki/policy_<lauf>.json, Parität Trainer ↔ JS, ki/policies.json, simtest --kipolicy
# Umgebung: PY (Python mit torch und sb3-contrib; Standard: python der aktiven venv), LAEUFE (Trainingsläufe mit verschiedenen Seeds hinter
#   dem Kandidaten, Standard 1; Freigabe verlangt ≥ 3), STADT_GIT und ALT wie tools/simtest_alle.sh (für simtest --kipolicy).
# Höchstens zwei Rechenprozesse gleichzeitig. Exit 0 nur, wenn jeder Schritt klappt; 2 bei falschem Aufruf.
set -u
cd "$(dirname "$0")/.." || exit 2
PY=${PY:-$(command -v python || command -v python3)}
SCHRITT=${1:-}; LAUF=${2:-}; K=${3:-}
[ -n "$LAUF" ] && [ -d "training/laeufe/$LAUF" ] || { echo "Aufruf: bash tools/auswertung.sh validierung|abschluss|export <lauf> [bester|letzter] (Lauf unter training/laeufe/)"; exit 2; }
L=training/laeufe/$LAUF; EX=$L/export; A=berichte/$LAUF
case "$K" in ''|bester|letzter) ;; *) echo "Kandidat bester oder letzter"; exit 2 ;; esac
case "$SCHRITT" in
  validierung)
    mkdir -p "$EX" "$A" || exit 1
    for k in bester letzter; do
      "$PY" training/exportiere.py --lauf "$L" --checkpoint $k --name "${LAUF}_$k" --aus "$EX/policy_${LAUF}_$k.json" > "$A/export_$k.txt" 2>&1 \
        || { cat "$A/export_$k.txt"; exit 1; }
    done
    cat "$A/export_bester.txt" "$A/export_letzter.txt"
    kette() {   # je Kandidat erst die Stadtwirkung, dann der gepaarte Vergleich (ein Prozess nach dem anderen)
      local k=$1 arme=$2
      node tools/ki_stadtwirkung.mjs --policy "$EX/policy_${LAUF}_$k.json" --seedliste validierung --versatz 16 --anzahl 4 \
        --aus "$A/val_stadt_$k.json" > "$A/val_stadt_$k.txt" 2>&1 || return 1
      "$PY" tools/messe.py node tools/werte_aus.mjs --policy "$EX/policy_${LAUF}_$k.json" --seeds validierung --versatz 16 --je-gruppe 32 \
        --arme $arme --laeufe "${LAEUFE:-1}" --stadtwirkung "$A/val_stadt_$k.json" --aus "$A/val_$k" > "$A/val_$k.txt" 2> "$A/val_${k}_stderr.txt" || return 1
    }
    kette bester regeln,policy,zufall & p1=$!
    kette letzter regeln,policy & p2=$!
    wait $p1; r1=$?; wait $p2; r2=$?
    echo "Validierung: bester exit $r1, letzter exit $r2"
    [ $r1 -eq 0 ] && [ $r2 -eq 0 ] || exit 1
    node tools/kandidat_waehlen.mjs bester="$A/val_bester.json" letzter="$A/val_letzter.json" | tee "$A/kandidatenwahl.txt"
    ;;
  abschluss)
    [ -n "$K" ] || { echo "Kandidat angeben (bester|letzter)"; exit 2; }
    [ -e "$A/abschluss.json" ] && { echo "Abschluss schon gerechnet ($A/abschluss.json) – die Abschlussseeds gibt es je Lauf nur einmal"; exit 1; }
    grep -q "Gewählt: $K " "$A/kandidatenwahl.txt" 2>/dev/null || { echo "Kandidat $K ist nicht der nach Validierung gewählte ($A/kandidatenwahl.txt)"; exit 1; }
    [ -f "$EX/policy_${LAUF}_$K.json" ] || { echo "$EX/policy_${LAUF}_$K.json fehlt (erst validierung)"; exit 1; }
    node tools/ki_stadtwirkung.mjs --policy "$EX/policy_${LAUF}_$K.json" --seedliste abschluss --anzahl 4 \
      --aus "$A/abschluss_stadt.json" > "$A/abschluss_stadt.txt" 2>&1 || exit 1
    "$PY" tools/messe.py node tools/werte_aus.mjs --policy "$EX/policy_${LAUF}_$K.json" --seeds abschluss --abschluss-freigegeben --je-gruppe 32 \
      --arme regeln,policy,zufall --laeufe "${LAEUFE:-1}" --stadtwirkung "$A/abschluss_stadt.json" --aus "$A/abschluss" > "$A/abschluss.txt" 2> "$A/abschluss_stderr.txt" || exit 1
    tail -5 "$A/abschluss.txt"
    ;;
  export)
    [ -n "$K" ] || { echo "Kandidat angeben (bester|letzter)"; exit 2; }
    REPO=${STADT_GIT:-$(git rev-parse --show-toplevel 2>/dev/null)}
    [ -n "$REPO" ] || { echo "Keine Git-Geschichte für simtest --kipolicy: STADT_GIT=<repo> setzen"; exit 2; }
    mkdir -p "$A" ausgabe || exit 1
    "$PY" training/exportiere.py --lauf "$L" --checkpoint "$K" --name "$LAUF" --aus "ki/policy_$LAUF.json" | tee "$A/export_final.txt" || exit 1
    "$PY" training/paritaet.py --lauf "$L" --policy "ki/policy_$LAUF.json" --faelle 400 --aus "ausgabe/paritaet_$LAUF.json" > "$A/paritaet_py.txt" 2>&1 \
      || { cat "$A/paritaet_py.txt"; exit 1; }
    node tools/paritaet.mjs "ki/policy_$LAUF.json" "ausgabe/paritaet_$LAUF.json" > "$A/paritaet.txt" 2>&1; rp=$?
    echo "Parität exit $rp"; tail -3 "$A/paritaet.txt"
    node tools/ki_liste.mjs | tee "$A/ki_liste.txt"
    node tools/simtest.mjs --kipolicy --git "$REPO" --rev "${ALT:-09083f5}" --policy "ki/policy_$LAUF.json" --tage 120 > "$A/kipolicy_$LAUF.txt" 2>&1; rs=$?
    echo "simtest --kipolicy exit $rs"; tail -2 "$A/kipolicy_$LAUF.txt"
    [ $rp -eq 0 ] && [ $rs -eq 0 ] || exit 1
    ;;
  *) echo "Aufruf: bash tools/auswertung.sh validierung|abschluss|export <lauf> [bester|letzter]"; exit 2 ;;
esac
