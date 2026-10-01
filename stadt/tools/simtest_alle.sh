#!/bin/bash
# Alle 21 simtest-Modi und die KI-Prüfung (--kipolicy) aus einer Temp-Kopie dieses Ordners; der Ordner selbst bleibt unverändert.
# simtest vergleicht die Übernahme alter Stände mit Version 8, die neben stadt.html als stadt.orig.html liegen muss, und holt ältere
# Fassungen per --git; beides kommt hier aus der Git-Geschichte. --kipolicy prüft u. a. „Policy aus = jeden Tag bitgleich zu ALT“ (mit R.GED = 0) und
# die Ablehnung einer Policy aus Version 9; --gedaechtnis (Version 10, Etappe 2) vergleicht mit ausgeschalteten Schaltern mit 6c1741e (--git).
#   cd stadt && bash tools/simtest_alle.sh              alle 21 Modi, --kipolicy und --kipolicy mit jeder Policy aus ki/policies.json
#   cd stadt && bash tools/simtest_alle.sh gate kita    nur diese (Modusnamen ohne --; kipolicy_datei = die Policies aus ki/)
# Umgebung: JOBS (gleichzeitige Läufe, Standard 2), STADT_GIT (Repo mit der Geschichte; sonst das, in dem dieser Ordner liegt),
#   ALT (Vergleichsfassung für --kipolicy, Standard 09083f5 = Version 9 ohne KI-Teil), AUSGABE (Logs, Standard ausgabe/simtest).
# Exit 0 nur, wenn jeder Lauf mit 0 endet; 1 sonst; 2 bei fehlender Umgebung oder unbekanntem Modus. Läuft auch mit bash 3.2 (Mac).
# --gate enthält eine Zeitgrenze (T: 365 Tage in weniger als 5000 ms, Wandzeit). Es läuft deshalb allein nach allen anderen; ist trotzdem nur
# T rot (anderes Programm rechnet nebenher), einzeln wiederholen: bash tools/simtest_alle.sh gate
set -u
cd "$(dirname "$0")/.." || exit 2
HIER=$(pwd)
JOBS=${JOBS:-2}
ALT=${ALT:-09083f5}
AUSGABE=${AUSGABE:-ausgabe/simtest}
REPO=${STADT_GIT:-$(git -C "$HIER" rev-parse --show-toplevel 2>/dev/null)}
# langsamste zuerst (gemessen im Linux-Container), damit sich die Läufe gut verteilen
MODI="autos sicherheit buergermeister rathaus schule kipolicy techfrueh erweiterung gedaechtnis militaer haushalt migrationstest tech gate wachstum regierung kita speichertest kitest bau waren aufholtest kipolicy_datei"
WAHL=${*:-$MODI}
for m in $WAHL; do case " $MODI " in *" $m "*) ;; *) echo "unbekannter Modus: $m (bekannt: $MODI)"; exit 2 ;; esac; done
command -v node >/dev/null || { echo "node fehlt"; exit 2; }
[ -n "$REPO" ] || { echo "Keine Git-Geschichte: STADT_GIT=<repo> setzen (alte Fassungen kommen per git show)"; exit 2; }
for c in 31ce452 6c1741e "$ALT"; do
  git -C "$REPO" cat-file -e "$c:stadt/stadt.html" 2>/dev/null || { echo "In $REPO fehlt $c:stadt/stadt.html (vollständige Git-Kopie nötig, nicht --depth 1)"; exit 2; }
done

T=$(mktemp -d "${TMPDIR:-/tmp}/stadt_simtest.XXXXXX") || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tools" "$AUSGABE" || exit 2
cp stadt.html "$T/" && cp tools/*.mjs "$T/tools/" || exit 2
git -C "$REPO" show 31ce452:stadt/stadt.html > "$T/stadt.orig.html" || exit 2   # Version 8
export T REPO ALT AUSGABE HIER

# ein Lauf: lauf <modus> [policy-datei]; Log nach AUSGABE/<modus>[_<datei>].txt, eine Zeile Status nach stdout
lauf() {
  [ -n "${1:-}" ] || return 0                     # GNU xargs ruft bei leerer Liste (nur gate) einmal ohne Argument auf
  local m=$1 datei=${2:-} f t0 code
  f="$AUSGABE/$m${datei:+_${datei%.json}}.txt"; t0=$(date +%s)
  case $m in
    migrationstest|erweiterung|rathaus|schule|haushalt|gedaechtnis) (cd "$T" && node tools/simtest.mjs --$m --git "$REPO") ;;
    kipolicy) (cd "$T" && node tools/simtest.mjs --kipolicy --git "$REPO" --rev "$ALT") ;;
    kipolicy_datei) (cd "$T" && node tools/simtest.mjs --kipolicy --git "$REPO" --rev "$ALT" --policy "$HIER/ki/$datei" --tage 120) ;;
    *) (cd "$T" && node tools/simtest.mjs --$m) ;;
  esac > "$f" 2>&1
  code=$?
  echo "--$m${datei:+ --policy ki/$datei} -> exit $code ($(( $(date +%s) - t0 )) s, $f)"
}
export -f lauf

POLICIES=$(node -e "try { console.log(JSON.parse(require('fs').readFileSync('ki/policies.json', 'utf8')).policies.join(' ')) } catch (e) { }")
echo "simtest aus $T: stadt.html $(node -e "console.log(require('crypto').createHash('sha256').update(require('fs').readFileSync('stadt.html')).digest('hex').slice(0, 16))"), Version 8 = 31ce452, Vergleich --kipolicy = $ALT, $JOBS gleichzeitig, Logs in $AUSGABE/"
: > "$AUSGABE/status.txt"
{ for m in $WAHL; do
    case $m in
      gate) ;;                                   # allein am Ende (Zeitgrenze)
      kipolicy_datei) for p in $POLICIES; do echo "$m $p"; done ;;
      *) echo "$m" ;;
    esac
  done; } | xargs -P "$JOBS" -L 1 bash -c 'lauf "$@"' _ | tee -a "$AUSGABE/status.txt"
case " $WAHL " in *" gate "*) lauf gate | tee -a "$AUSGABE/status.txt" ;; esac
n=$(grep -c ' -> exit ' "$AUSGABE/status.txt"); rot=$(grep -c ' -> exit [1-9]' "$AUSGABE/status.txt")
echo "Ergebnis: $((n - rot)) von $n Läufen mit Exit 0" | tee -a "$AUSGABE/status.txt"
[ "$rot" -eq 0 ] && [ "$n" -gt 0 ]
