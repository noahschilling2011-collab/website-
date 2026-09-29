#!/bin/bash
# Prüfung vom 29.09.2026: Stoppen und Fortsetzen eines Laufs (docs/EXPERIMENTE.md, Abschnitt 3). Braucht einen Lauf training/laeufe/smoke_probe
# (Smoke-Befehle aus EXPERIMENTE.md) und die Umgebung .venv. Schritte: Strg+C wie im Terminal (SIGINT an die ganze Prozessgruppe), kill -9,
# fortsetzen, Export; nach jedem Schritt Manifest gegen die Dateien (pruef_manifest.py). Logs nach ausgabe/. Ergebnis hier: abbruch.txt
#   cd stadt && bash berichte/pruefung_2026-09-29/abbruch_test.sh
HIER=$(cd "$(dirname "$0")" && pwd)
cd "$HIER/../.." || exit 2
mkdir -p ausgabe
PY=.venv/bin/python; L=training/laeufe/smoke_probe; P="$PY $HIER/pruef_manifest.py"
starte() { (setsid $PY training/trainiere.py --fortsetzen $L --zusatz 16384 > "$1" 2>&1 &); sleep 1; ps -eo pid,pgid,cmd | grep "trainiere.py --fortsetzen $L" | grep -v grep | awk '{print $2}' | head -1; }
warte_val() { local n i; for i in $(seq 1 120); do sleep 1; n=$(grep -c "Validierung bei" "$1"); [ "$n" -ge "$2" ] && return 0; done; return 1; }
echo "== 1. Strg+C (SIGINT an die Gruppe) nach 2 Validierungen"
PG=$(starte ausgabe/abbruch_1.log); warte_val ausgabe/abbruch_1.log 2; kill -INT -"$PG"; t0=$(date +%s)
while ps -p "$PG" > /dev/null; do sleep 0.5; done; echo "beendet nach $(( $(date +%s) - t0 )) s; Node-Prozesse übrig: $(ps -eo cmd | grep kiumgebung | grep -v grep | grep -c "$(pwd)")"
grep -E "Validierung|SIGINT|Fertig" ausgabe/abbruch_1.log; $P $L
echo "== 2. kill -9 nach 2 weiteren Validierungen"
PG=$(starte ausgabe/abbruch_2.log); warte_val ausgabe/abbruch_2.log 2; sleep 1; kill -9 "$PG"; sleep 2
echo "Node-Prozesse übrig: $(ps -eo cmd | grep kiumgebung | grep -v grep | grep -c "$(pwd)")"
grep -E "Validierung|Fertig" ausgabe/abbruch_2.log; $P $L
echo "== 3. fortsetzen --zusatz 2048"
$PY training/trainiere.py --fortsetzen $L --zusatz 2048 2>&1 | grep -E "Validierung|Fertig"; $P $L
echo "== 4. Export bester: Schritte aus dem Checkpoint"
$PY training/exportiere.py --lauf $L --checkpoint bester --aus ausgabe/policy_nach_abbruch.json 2>&1 | tail -1
python3 -c "import json;h=json.load(open('ausgabe/policy_nach_abbruch.json'))['herkunft'];print('herkunft.trainingsSchritte', h['trainingsSchritte'], 'Validierung Defizit', round(h['validierung']['defizitMittel']['mittel'],2))"
