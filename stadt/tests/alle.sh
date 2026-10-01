#!/bin/bash
# Alle Browser-Tests nacheinander (immer nur einer gleichzeitig). Wurzel des Seitenservers ist der Ordner stadt/ über tests/.
#   bash tests/alle.sh                  alle Tests
#   bash tests/alle.sh p3test otest/handy browser_ki      nur diese
# Startet den Seitenserver (python3 -m http.server auf PORT, Standard 8716, nur 127.0.0.1) und, wenn auf 11434 nichts antwortet, den
# KI-Nachbau tests/mockollama.mjs; beide am Ende per PID beendet (ein schon laufender Dienst auf 11434 bleibt unberührt). browser_ki startet
# danach seinen eigenen Server auf demselben PORT. Logs und Bilder nach tests/ausgabe/ (AUSGABE). Exit-Code 0 nur, wenn jeder Test mit 0
# endet, keine FEHL-Zeile hat und genau die Soll-Zahl an OK-Prüfungen erreicht. Umgebung: tests/LIESMICH.md (PLAYWRIGHT, THREE_DIR, STADT_GIT).
set -u
cd "$(dirname "$0")" || exit 2
TESTS=$(pwd); STADT=$(dirname "$TESTS")
export PORT=${PORT:-8716}
KI_PORT=${KI_PORT:-11434}                    # nur zum Prüfen dieses Skripts ändern; das Spiel fragt immer 11434
export AUSGABE=${AUSGABE:-$TESTS/ausgabe}
LOGS=$AUSGABE/logs
SERVER_PID=""; KI_PID=""

# FUNKTIONEN
frist() {                                    # frist <sekunden> <befehl …>: timeout (Linux) oder perl-alarm (Mac hat kein timeout)
  local s=$1; shift
  if command -v timeout > /dev/null 2>&1; then timeout "$s" "$@"; else perl -e 'alarm shift @ARGV; exec @ARGV or die "exec: $!"' "$s" "$@"; fi
}
belegt() { (echo > "/dev/tcp/127.0.0.1/$1") 2> /dev/null; }
ki_antwortet() { curl -s -m 3 "http://localhost:$KI_PORT/api/tags" 2> /dev/null; }
ki_nachbau_starten() {                       # KI-Nachbau nur starten, wenn auf KI_PORT nichts antwortet
  local tags; tags=$(ki_antwortet)
  if [ -n "$tags" ]; then
    case "$tags" in
      *test-modell*) echo "KI: auf $KI_PORT läuft schon ein KI-Nachbau (test-modell), bleibt unberührt" ;;
      *) echo "WARNUNG: auf $KI_PORT antwortet ein anderes Ollama; p4test braucht den KI-Nachbau (Ollama kurz beenden)" ;;
    esac
    return 0
  fi
  if belegt "$KI_PORT"; then echo "WARNUNG: Port $KI_PORT belegt, aber keine Ollama-Antwort – kein KI-Nachbau gestartet"; return 0; fi
  KI_PORT=$KI_PORT node "$TESTS/mockollama.mjs" > "$LOGS/mockollama.log" 2>&1 &
  KI_PID=$!
  local i; for i in $(seq 1 50); do [ -n "$(ki_antwortet)" ] && break; sleep 0.1; done
  if [ -n "$(ki_antwortet)" ]; then echo "KI: Nachbau tests/mockollama.mjs gestartet (PID $KI_PID, Port $KI_PORT)"; else echo "FEHLER: KI-Nachbau antwortet nicht"; return 1; fi
}
server_starten() {
  if belegt "$PORT"; then echo "FEHLER: Port $PORT ist belegt – nichts gestartet (PORT=… wählen)"; return 1; fi
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$STADT" > "$LOGS/server.log" 2>&1 &
  SERVER_PID=$!
  local i; for i in $(seq 1 50); do belegt "$PORT" && break; sleep 0.1; done
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/tests/leer.html")" != 200 ]; then echo "FEHLER: Seitenserver antwortet nicht"; return 1; fi
  echo "Seitenserver: python3 -m http.server $PORT (PID $SERVER_PID), Wurzel $STADT"
}
server_beenden() {
  if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2> /dev/null; wait "$SERVER_PID" 2> /dev/null; echo "Seitenserver PID $SERVER_PID beendet"; SERVER_PID=""; fi
}
aufraeumen() {
  server_beenden
  if [ -n "$KI_PID" ]; then kill "$KI_PID" 2> /dev/null; wait "$KI_PID" 2> /dev/null; echo "KI-Nachbau PID $KI_PID beendet"; KI_PID=""; fi
}
# ENDE FUNKTIONEN

# Soll-Zahl der OK-Prüfungen je Test (Stand der Schlussprüfung von Version 9; browser_ki aus dem Übertrag der KI auf Version 9, seit der
# Prüfung vom 29.09.2026 mit 6 Prüfungen mehr: Import-Rückmeldung im Fenster, Datei entfernen, Auswertung laut Datei, Texte ohne Doppelung)
soll() {
  case $1 in
    p3test) echo 12 ;; p5neu) echo 10 ;; p6migration) echo 44 ;; p7figuren) echo 6 ;; p8tech) echo 15 ;; raute_klick) echo 11 ;;
    ereignis) echo 21 ;; t1_xss) echo 5 ;; p4test) echo 29 ;; s2karten) echo 22 ;; kita) echo 22 ;; befunde_s2) echo 27 ;;
    erweiterung) echo 20 ;; sicherheit) echo 12 ;; militaer) echo 16 ;; autos) echo 9 ;; autos_bild) echo 20 ;; rathaus) echo 15 ;;
    schule) echo 8 ;; haushalt) echo 18 ;; wachstum) echo 29 ;; techfrueh) echo 17 ;; befunde_v9) echo 20 ;;
    otest/befunde) echo 21 ;; otest/handy) echo 11 ;; otest/breit) echo 12 ;; otest/tastatur) echo 4 ;; otest/breiten) echo 20 ;;
    otest/hilfehoehe) echo 1 ;; browser_ki) echo 32 ;;
    p10speicher) echo 11 ;;                    # Version 10 (Etappe 2, Schritt 2): Speicherformat, große Stadt in localStorage, Übernahme von 9 (seit FIX: auch per Import, +1)
    gedaechtnis) echo 17 ;;                    # Etappe 2, Schritt 3: Personenkarte (Erfahrung, Plan, offene Folge, „Warum?“), Liste „heute anders“, Handy, Tastatur (seit FIX: Warum nachrechenbar, Liste beim Auffrischen, +2)
    # Version 10 (Etappe 2, Schritt 4): p6migration +5 (Übernahme eines Stands der Version 9 aus 6c1741e mit Größe), browser_ki +2 (Policy aus
    # Version 9 sichtbar abgelehnt: in ki/ und beim Datei-Import), raute_klick 8 → 11 (die Teststadt läuft anders: 10 statt 7 Rauten im Bild,
    # dazu die Summenzeile; das Kriterium des Tests bleibt: mindestens 4 Klicks, keiner daneben)
    *) echo "?" ;;
  esac
}
ALLE="p3test p5neu p6migration p7figuren p8tech raute_klick ereignis t1_xss p4test s2karten kita befunde_s2 erweiterung sicherheit militaer
  autos autos_bild rathaus schule haushalt wachstum techfrueh befunde_v9 otest/befunde otest/handy otest/breit otest/tastatur otest/breiten
  otest/hilfehoehe p10speicher gedaechtnis browser_ki"
LISTE=${*:-$ALLE}
for t in $LISTE; do [ "$(soll "$t")" = "?" ] && { echo "Unbekannter Test: $t (bekannt: $(echo $ALLE))"; exit 2; }; done

rm -rf "$LOGS"; mkdir -p "$LOGS"
T0=$(date +%s)
node "$TESTS/umgebung.cjs" || { echo "FEHLER: Umgebung unvollständig (tests/LIESMICH.md)"; exit 2; }
trap aufraeumen EXIT
trap 'exit 130' INT TERM
server_starten || exit 2
ki_nachbau_starten || exit 2

ERG=""; FEHLER=0
einer() {                                    # einer <test>: laufen lassen, zählen, Zeile für die Zusammenfassung
  local t=$1 log="$LOGS/$(echo "$1" | tr / _).log" s0 rc ok fehl sl dauer urteil
  s0=$(date +%s)
  echo "=== $t"
  frist 1500 node "$TESTS/$t.cjs" > "$log" 2>&1; rc=$?
  dauer=$(( $(date +%s) - s0 ))
  case $t in
    otest/*) ok=$(grep -ciE '^ *OK' "$log") ;;
    browser_ki) ok=$(grep -c '^ok ' "$log") ;;
    *) ok=$(grep -c '^OK' "$log") ;;
  esac
  fehl=$(grep -cE '^ *FEHL|Testfehler' "$log"); sl=$(soll "$t")
  if [ "$rc" = 0 ] && [ "$fehl" = 0 ] && [ "$ok" = "$sl" ]; then urteil=grün; else urteil=ROT; FEHLER=$((FEHLER + 1)); fi
  echo "exit $rc, OK $ok (Soll $sl), FEHL $fehl, $dauer s → $urteil"
  [ "$urteil" = ROT ] && grep -E '^ *FEHL|Testfehler|Error' "$log" | head -5
  ERG="$ERG$(printf '%-18s %-5s exit %-3s OK %3s / %3s  FEHL %s  %5s s' "$t" "$urteil" "$rc" "$ok" "$sl" "$fehl" "$dauer")
"
}
KI_TEST=0
for t in $LISTE; do
  case $t in t1_xss|befunde_v9|techfrueh) BRAUCHT_BASIS=1 ;; esac
done
if [ "${BRAUCHT_BASIS:-0}" = 1 ]; then          # Teststand Seed 2 / Tag 420 aus der Git-Geschichte (für t1_xss, befunde_v9, techfrueh)
  echo "=== basis (Teststand erzeugen)"
  frist 1500 node "$TESTS/basis.cjs" > "$LOGS/basis.log" 2>&1 || { echo "FEHLER: tests/basis.cjs, siehe $LOGS/basis.log"; tail -5 "$LOGS/basis.log"; FEHLER=$((FEHLER + 1)); }
  tail -2 "$LOGS/basis.log"
fi
for t in $LISTE; do
  if [ "$t" = browser_ki ]; then KI_TEST=1; continue; fi
  einer "$t"
done
server_beenden                                # browser_ki braucht PORT für seinen eigenen Server
[ "$KI_TEST" = 1 ] && einer browser_ki

echo
echo "Zusammenfassung ($(date '+%Y-%m-%d %H:%M'), PORT $PORT, $(( ($(date +%s) - T0) / 60 )) min):"
printf '%s' "$ERG"
if [ "$FEHLER" = 0 ]; then echo "ALLES GRÜN"; exit 0; fi
echo "$FEHLER ROT – Logs in $LOGS"
exit 1
