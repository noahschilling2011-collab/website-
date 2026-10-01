#!/usr/bin/env python3
"""Durchsatz über das JSONL-Protokoll (Python ⇄ Node), zufällige erlaubte Aktionen (fester Strom). Ausgangslagen vorab gerechnet.

    python training/durchsatz.py [--episoden 10]
"""
import argparse, json, sys, time
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from stadt_env import StadtEnv  # noqa: E402

ap = argparse.ArgumentParser(); ap.add_argument("--episoden", type=int, default=10); a = ap.parse_args()
seeds = [10000, 10001, 10002, 10003, 10004]
env = StadtEnv(seeds, reihum=True)
for s in seeds:                                   # Ausgangslagen vorab (Cache im Node-Prozess)
    env.reset(options={"seed": s, "nr": 0})
rng = np.random.default_rng(1)
t0 = time.time(); n = 0; stunden = 0
for e in range(a.episoden):
    _, info = env.reset(options={"seed": seeds[e % len(seeds)], "nr": e})
    fertig = bool(info.get("schon_vorbei"))
    while not fertig:
        m = env.action_masks(); act = int(rng.choice(np.flatnonzero(m)))
        _, _, te, tr, info = env.step(act); n += 1; stunden += info["stunden"]; fertig = te or tr
dt = time.time() - t0
env.close()
print(f"{n} Schritte, {stunden} Spielstunden in {dt:.2f} s → {n / dt:.0f} Schritte/s, {stunden / dt:.0f} Spielstunden/s über das Protokoll (ohne Lernen)")
