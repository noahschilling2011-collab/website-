#!/usr/bin/env bash
# guests_jet_aircraft: AircraftModel builds of the current tree vs the round-2b baseline: the airliners (320 / 380) at
# every LOD must be identical part for part (name, class, CFrame, size, colour, material, transparency) - compared by
# a per-kind/LOD fingerprint (count + sha256 of the sorted part list) committed in tests/guests_jet/aircraft_base.json
# (made from agents/stable/src_r2b_base, so the suite also runs in a run_all sandbox); the bizjet is new: part
# budgets per LOD, the attachments / points, the airstair parts.
# Usage: tests/guests_jet/aircraft.sh [--src DIR] [--base DIR]   (--base: compare against a source tree instead)
#        tests/guests_jet/aircraft.sh --write-base DIR             (re-make aircraft_base.json from a source tree)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$ROOT"
SRC=work/src; BASE=""; WRITE=""
FP_FILE=tests/guests_jet/aircraft_base.json
while [ $# -gt 0 ]; do case "$1" in --src) SRC="$2"; shift;; --base) BASE="$2"; shift;; --write-base) WRITE="$2"; shift;; esac; shift; done
OUT=out/guests_jet/aircraft_$$; mkdir -p "$OUT"
if [ -n "$WRITE" ]; then SRC="$WRITE"; fi
bash tests/guests_jet/aircraft_dump.sh "$SRC" "$OUT/new.json" >/dev/null 2>&1 || { echo "FAIL  aircraft dump"; echo "guests_jet_aircraft: 0 passed, 1 failed"; exit 1; }
if [ -n "$BASE" ]; then
  bash tests/guests_jet/aircraft_dump.sh "$BASE" "$OUT/base.json" >/dev/null 2>&1 || { echo "FAIL  baseline aircraft dump"; echo "guests_jet_aircraft: 0 passed, 1 failed"; exit 1; }
elif [ -z "$WRITE" ]; then
  cp "$FP_FILE" "$OUT/base.json" 2>/dev/null || { echo "FAIL  baseline fingerprint $FP_FILE missing"; echo "guests_jet_aircraft: 0 passed, 1 failed"; exit 1; }
fi
python3 - "$OUT/base.json" "$OUT/new.json" "$WRITE" "$FP_FILE" <<'PY'
import json, sys, collections, hashlib
def load(p):
    d = json.load(open(p)); out = collections.defaultdict(list); attrs = collections.defaultdict(list)
    for x in d['instances']:
        top = x['path'].split('/')[1] if x['path'].count('/') >= 1 else x['path']
        if 'cframe' in x:
            out[top].append((x['name'], x['class'], tuple(round(v, 4) + 0.0 for v in x['cframe']), tuple(round(v, 4) + 0.0 for v in x.get('size', [])),
                             tuple(x.get('color', [])), x.get('material'), round(x.get('transparency', 0), 3)))
            attrs[top].append(x.get('attrs') or {})
        else:
            out[top].append((x['name'], x['class']))
    return out, attrs
KEYS = [k + "_" + l for k in ("320", "380") for l in ("full", "medium", "low")]
def fingerprint(parts):
    rows = sorted(json.dumps(list(r)) for r in parts)
    return {"count": len(rows), "sha256": hashlib.sha256("\n".join(rows).encode()).hexdigest()}
b, battrs = load(sys.argv[2])
if sys.argv[3]:
    fp = {k: fingerprint(b.get(k, [])) for k in KEYS}
    json.dump({"note": "guests_jet: airliner fingerprints of " + sys.argv[3] + " (tests/guests_jet/aircraft.sh --write-base)", "fingerprints": fp}, open(sys.argv[4], "w"), indent=1)
    print("wrote " + sys.argv[4] + ": " + ", ".join("%s %d" % (k, fp[k]["count"]) for k in KEYS)); sys.exit(0)
raw = json.load(open(sys.argv[1]))
if "fingerprints" in raw:
    basefp = raw["fingerprints"]
else:
    a, _ = load(sys.argv[1]); basefp = {k: fingerprint(a.get(k, [])) for k in KEYS}
passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("FAIL  " + name + ("  -- " + str(detail) if detail != "" else ""))
for kind in ("320", "380"):
    for lod in ("full", "medium", "low"):
        k = kind + "_" + lod
        want, got = basefp.get(k, {"count": 0, "sha256": ""}), fingerprint(b.get(k, []))
        check("%s unchanged vs the baseline (%d parts)" % (k, want["count"]), want["count"] > 20 and want == got,
              "%d vs %d entries, sha %s vs %s" % (want["count"], got["count"], want["sha256"][:12], got["sha256"][:12]))
budget = {"full": 300, "medium": 100, "low": 45}
for lod, cap in budget.items():
    k = "bizjet_" + lod
    n = sum(1 for r in b.get(k, []) if len(r) > 2 and r[1] != "Attachment")
    check("bizjet %s built within %d parts" % (lod, cap), 20 < n <= cap, n)
full = b.get("bizjet_full", [])
names = {r[0] for r in full}
for need in ("TailName", "Titles", "Windshield", "CockpitSeat" if "CockpitSeat" in names else "PilotSeat", "CabinSeat", "AirstairFlight", "Fan", "Nacelle", "Winglet"):
    check("bizjet full has %s" % need, need in names)
att = {r[0] for r in full if r[1] == "Attachment"}
for need in ("DoorL1", "CaptainSeat", "FirstOfficerSeat", "CockpitCamera", "CabinCamera", "CabinSeat1", "CabinSeat6"):
    check("bizjet attachment %s" % need, need in att)
stair = [x for x in battrs["bizjet_full"] if x.get("Airstair")]
check("bizjet airstair parts tagged (setAirstair toggles them)", len(stair) >= 8, len(stair))
gear = [x for x in battrs["bizjet_full"] if x.get("Gear")]
spin = [x for x in battrs["bizjet_full"] if x.get("Spin")]
check("bizjet gear (Gear) and fans (Spin) for AircraftMover", len(gear) >= 3 and len(spin) >= 2, (len(gear), len(spin)))
print("guests_jet_aircraft: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PY
rc=$?
[ $rc -eq 0 ] && rm -rf "$OUT"
exit $rc
