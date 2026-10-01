#!/usr/bin/env python3
"""Paritätstest, Teil Python: dieselben Beobachtungen und Masken durch den Trainer (PyTorch, Checkpoint) schicken.

    python training/paritaet.py --lauf training/laeufe/<lauf> --policy ki/policy_<name>.json [--faelle 400]

Schreibt ki/paritaet_<name>.json mit rohen Beobachtungen, Masken, normalisierten Eingaben, Logits und der deterministischen Aktion
(MaskablePPO.predict mit action_masks). Den Vergleich mit der JS-Inferenz macht tools/paritaet.mjs.
Fälle: Beobachtungen echter Entscheidungen auf Validierungsseeds (Policy handelt, eigene Beobachtungen der aktuellen stadt.html), dazu
künstliche (auch außerhalb der Clip-Grenze), Masken mit nur „warten“ und Randwerte (V9-Übertrag): Beobachtung genau im Mittel (z = 0), genau auf
und knapp jenseits der Clip-Grenze, je Merkmal einzeln weit darüber und darunter, alle 0, alle 1, −0, ±1e30 (float32), dazu Masken mit genau einer
Aktion neben warten und mit allen Aktionen.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import torch
from sb3_contrib import MaskablePPO

HIER = Path(__file__).resolve().parent
BASIS = HIER.parent
sys.path.insert(0, str(HIER))
from stadt_env import StadtEnv  # noqa: E402


def logits_torch(model, z: np.ndarray) -> np.ndarray:
    pol = model.policy
    with torch.no_grad():
        t = torch.as_tensor(z, dtype=torch.float32).reshape(1, -1)
        f = pol.extract_features(t)
        if isinstance(f, tuple):          # getrennte Merkmalsextraktoren (hier nicht der Fall, aber sicher)
            f = f[0]
        lat = pol.mlp_extractor.forward_actor(f)
        return pol.action_net(lat).numpy().reshape(-1).astype(np.float64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lauf", required=True)
    ap.add_argument("--policy", required=True)
    ap.add_argument("--faelle", type=int, default=400)
    ap.add_argument("--aus")
    a = ap.parse_args()
    laufdir = Path(a.lauf).resolve()
    pol_json = json.load(open(a.policy))
    ck = pol_json["herkunft"]["checkpoint"]
    zip_pfad = laufdir / ck
    if hashlib.sha256(zip_pfad.read_bytes()).hexdigest()[:16] != pol_json["herkunft"]["checkpointSha256"]:
        raise SystemExit("Checkpoint passt nicht zur Policy-Datei (sha256)")
    torch.set_num_threads(1)
    model = MaskablePPO.load(zip_pfad, device="cpu")
    norm = json.load(open(laufdir / "normalisierung.json"))
    seeds = json.load(open(HIER / "seeds.json"))["validierung"]
    env = StadtEnv(seeds, normalisierung=norm, tage=10, reihum=True)
    faelle = []
    rng = np.random.default_rng(12345)
    try:
        # 1) echte Entscheidungen (Policy handelt deterministisch)
        e = 0
        while len(faelle) < a.faelle * 0.6:
            obs, info = env.reset(options={"seed": seeds[e % len(seeds)], "nr": 500 + e})
            e += 1
            fertig = bool(info.get("schon_vorbei"))            # schon beim Start vorbei: keine Entscheidung dieser Person
            while not fertig and len(faelle) < a.faelle * 0.6:
                roh, m = env.letzte_rohe_beobachtung(), env.action_masks()
                faelle.append((roh, m, "echt"))
                act, _ = model.predict(obs, deterministic=True, action_masks=m)
                obs, _, te, tr, _ = env.step(int(act))
                fertig = te or tr
        n = env.n
        mittel, streuung = np.asarray(norm["mittel"]), np.asarray(norm["streuung"])
        # 2) künstliche Beobachtungen (auch jenseits der Clip-Grenze) mit zufälligen Masken, warten immer erlaubt
        while len(faelle) < a.faelle - 10:
            roh = (mittel + streuung * rng.normal(0, 3, n)).astype(np.float32)
            m = rng.random(len(env.aktionen)) < 0.4
            m[0] = True
            faelle.append((roh, m, "kuenstlich"))
        # 3) nur warten erlaubt
        while len(faelle) < a.faelle:
            roh = (mittel + streuung * rng.normal(0, 1, n)).astype(np.float32)
            m = np.zeros(len(env.aktionen), dtype=bool)
            m[0] = True
            faelle.append((roh, m, "nur_warten"))
        # 4) Randwerte (zusätzlich zu --faelle): feste Fälle, kein Zufall außer der Maske für die Merkmalsfälle
        na, clip = len(env.aktionen), float(norm["clip"])
        alle = np.ones(na, dtype=bool)
        rand = [(mittel, "mittel"), (mittel + clip * streuung, "auf_clip_plus"), (mittel - clip * streuung, "auf_clip_minus"),
                (mittel + (clip + 1e-3) * streuung, "knapp_ueber_clip"), (mittel - (clip + 1e-3) * streuung, "knapp_unter_clip"),
                (np.zeros(n), "alle_0"), (np.ones(n), "alle_1"), (np.full(n, -0.0), "minus_0"), (np.full(n, 1e30), "plus_1e30"),
                (np.full(n, -1e30), "minus_1e30")]
        for i in range(n):
            for vz in (1, -1):
                x = mittel.copy()
                x[i] = mittel[i] + vz * 10 * clip * streuung[i]
                rand.append((x, f"merkmal_{i}_{'hoch' if vz > 0 else 'tief'}"))
        for x, art in rand:
            roh = np.asarray(x, dtype=np.float64).astype(np.float32)
            faelle.append((roh, alle.copy(), "rand"))
            if art.startswith("merkmal_"):
                continue
            for k in range(1, na):                            # genau eine Aktion neben warten
                m = np.zeros(na, dtype=bool)
                m[0] = m[k] = True
                faelle.append((roh, m, "rand"))
        aus = []
        for roh, m, art in faelle:
            z = env.normiere(roh)
            lg = logits_torch(model, z)
            act, _ = model.predict(z, deterministic=True, action_masks=m)
            aus.append({"art": art, "beob": [float(v) for v in roh], "maske": [int(v) for v in m], "z": [float(v) for v in z],
                        "logits": [float(v) for v in lg], "aktion": int(act)})
    finally:
        env.close()
    ziel = Path(a.aus) if a.aus else BASIS / "ki" / f"paritaet_{pol_json['name']}.json"
    json.dump({"policy": pol_json["name"], "policyHash": pol_json["hash"], "checkpoint": ck, "torch": torch.__version__,
               "faelle": aus}, open(ziel, "w"))
    arten = {}
    for f in aus:
        arten[f["art"]] = arten.get(f["art"], 0) + 1
    print(f"geschrieben: {ziel} ({len(aus)} Fälle: {arten})")


if __name__ == "__main__":
    main()
