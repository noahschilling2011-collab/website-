#!/bin/bash
# Gate T im Wechsel mit der Basis (Etappe 2, Noahs Nachtrag 7: wer den sim-Block ändert, misst T im Wechsel mit 6c1741e, damit die Stadt
# nicht wieder langsamer wird; ein einzelner Wert sagt wenig, weil derselbe Rechner an verschiedenen Tagen verschieden schnell ist).
# simtest --gate für diesen Ordner (neu) und für die Basis (stadt.html und tools/ aus der Git-Geschichte in einen Temp-Ordner), immer nur
# ein Prozess, Reihenfolge je Runde abwechselnd (neu–basis, basis–neu, …). Vor jedem Lauf Uhrzeit, Last und fremde Rechenprozesse (node oder
# python über 20 % CPU). Am Ende T je Lauf, Median je Fassung und neu/basis. Nur allein laufen lassen (Wandzeit). Entwicklungswerkzeug,
# übernommen aus den Messwerkzeugen der Etappe 2 (gate_wechsel1.sh; dort war die Basis eine Kopie von 6c1741e im Arbeitsordner).
#   cd stadt && bash tools/gate_t_wechsel.sh [runden 4] [seeds 1] [ausgabeordner ausgabe/gate_t]
# Umgebung: STADT_GIT (Repo mit der Geschichte; sonst das, in dem dieser Ordner liegt), BASIS (Standard 6c1741e). Geprüft unter Linux;
# auf dem Mac nicht (sha256 dort über shasum).
set -u
cd "$(dirname "$0")/.." || exit 2
HIER=$(pwd)
RUNDEN=${1:-4}; SEEDS=${2:-1}; AUS=${3:-ausgabe/gate_t}; BASIS=${BASIS:-6c1741e}
REPO=${STADT_GIT:-$(git -C "$HIER" rev-parse --show-toplevel 2>/dev/null)}
[ -n "$REPO" ] || { echo "Keine Git-Geschichte: STADT_GIT=<repo> setzen"; exit 2; }
git -C "$REPO" cat-file -e "$BASIS:stadt/stadt.html" 2>/dev/null || { echo "In $REPO fehlt $BASIS:stadt/stadt.html"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/stadt_gate_t.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
git -C "$REPO" archive "$BASIS" stadt/stadt.html stadt/tools | tar -x -C "$T" || exit 2
mkdir -p "$AUS" && AUS=$(cd "$AUS" && pwd) || exit 2
kurz() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-16; }
LOG=$AUS/wechsel.txt; : > "$LOG"
echo "neu: $HIER (stadt.html $(kurz stadt.html)), basis: $BASIS ($(kurz "$T/stadt/stadt.html")), Seeds $SEEDS, $RUNDEN Runden" | tee -a "$LOG"
for i in $(seq 1 "$RUNDEN"); do
  if [ $((i % 2)) -eq 1 ]; then ORDER="neu basis"; else ORDER="basis neu"; fi
  for v in $ORDER; do
    if [ "$v" = neu ]; then D=$HIER; else D=$T/stadt; fi
    echo "Runde $i $v: $(date -u +%T) Last:$(uptime | sed 's/.*load average[s]*://') fremde>20%: $(ps -eo pcpu,comm | awk '$1 > 20 && ($2 == "node" || $2 ~ /python/)' | wc -l)" >> "$LOG"
    (cd "$D" && node tools/simtest.mjs --gate --seeds "$SEEDS" > "$AUS/gate_${v}_$i.txt" 2>&1; echo "  exit $?" >> "$LOG")
    LC_ALL=C.UTF-8 grep -E "═══ Seed|  [✓✗] T |Gate Phase" "$AUS/gate_${v}_$i.txt" >> "$LOG"
  done
done
# T des ersten Seeds je Lauf, Median je Fassung, neu/basis
node -e '
  const fs = require("fs"), aus = process.argv[1], n = Number(process.argv[2]);
  const t = (v) => [...Array(n).keys()].map(i => { const m = fs.readFileSync(`${aus}/gate_${v}_${i + 1}.txt`, "utf8").match(/[✓✗] T .* in ([\d.]+) ms/); return m ? Number(m[1].replace(/\./g, "")) : NaN; });
  const med = (x) => { const s = [...x].sort((a, b) => a - b), k = s.length >> 1; return s.length % 2 ? s[k] : (s[k - 1] + s[k]) / 2; };
  const a = t("neu"), b = t("basis");
  console.log(`T neu   ${a.join(", ")} ms, Median ${med(a)}; unter 5000 ms: ${a.filter(x => x < 5000).length} von ${a.length}`);
  console.log(`T basis ${b.join(", ")} ms, Median ${med(b)}`);
  console.log(`neu/basis (Mediane) ${(med(a) / med(b)).toFixed(3)}`);
' "$AUS" "$RUNDEN" | tee -a "$LOG"
