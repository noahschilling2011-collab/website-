#!/usr/bin/env python3
"""Export eines Checkpoints nach ki/policy_<name>.json (Format stadt-policy, Version 2) für den Browser und die Node-Werkzeuge.

    python training/exportiere.py --lauf training/laeufe/<lauf> [--checkpoint bester|letzter] [--name <name>] [--aus ki/policy_x.json]

Die Datei enthält: Sim-Version (Stadt-Version, auf der trainiert wurde; der Browser lehnt eine andere ab), Schema-Version, Merkmale,
Aktionen (Reihenfolge), Schema-Hash (FNV-1a wie Sim.KI.schemaHash), Inhalts-Hash (SHA-256 wie Sim.KI.policyHash, im Browser nachgerechnet), Normalisierung
(aus dem Lauf, nur Trainingsdaten), die Schichten des Policy-Netzes (Gewichte als float32-Werte in kürzester Dezimalform, Bias,
Aktivierung), die Auswahlregel, Herkunft (Lauf, Manifest, Checkpoint mit sha256, Trainingsschritte, Versionen) und den Status
„experimentell“. Das Wertnetz (value_net) wird nicht gebraucht und nicht exportiert.

Aufbau des Policy-Netzes in stable-baselines3 2.9.0 (im Quelltext nachgesehen): features = Flatten(obs) → mlp_extractor.policy_net
(Sequential aus Linear und Aktivierung) → action_net (Linear) = Logits.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np
import torch
from sb3_contrib import MaskablePPO

HIER = Path(__file__).resolve().parent
BASIS = HIER.parent


def fnv1a32(text: str) -> str:
    h = 0x811C9DC5
    for ch in text:
        c = ord(ch)
        if c > 0xFFFF:
            raise ValueError("Schema-Text enthält Zeichen außerhalb von UTF-16 BMP")
        h ^= c
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"


def f32(v) -> float:
    """float32-Wert in kürzester Dezimalform (JS: Math.fround(Zahl) ergibt wieder genau diesen float32-Wert)."""
    s = np.format_float_positional(np.float32(v), unique=True, trim="-")
    x = float(s)
    if not math.isfinite(x):
        raise ValueError("Gewicht nicht endlich")
    assert np.float32(x) == np.float32(v)
    return x


def schichten_aus(model) -> list[dict]:
    pol = model.policy
    seq = pol.mlp_extractor.policy_net
    L = []
    for mod in seq:
        if isinstance(mod, torch.nn.Linear):
            L.append({"gewichte": [[f32(w) for w in zeile] for zeile in mod.weight.detach().cpu().numpy()],
                      "bias": [f32(b) for b in mod.bias.detach().cpu().numpy()], "aktivierung": "linear"})
        elif isinstance(mod, torch.nn.Tanh):
            L[-1]["aktivierung"] = "tanh"
        elif isinstance(mod, torch.nn.ReLU):
            L[-1]["aktivierung"] = "relu"
        else:
            raise ValueError(f"unbekannte Schicht im policy_net: {mod}")
    an = pol.action_net
    L.append({"gewichte": [[f32(w) for w in zeile] for zeile in an.weight.detach().cpu().numpy()],
              "bias": [f32(b) for b in an.bias.detach().cpu().numpy()], "aktivierung": "linear"})
    return L


def inhalt_hash(d: dict) -> str:
    """Inhalts-Hash wie Sim.KI.policyHash (sim-Block): SHA-256 über Kopf (ASCII), clip, Mittel, Streuung (float64 little-endian) und je
    Schicht „|aktivierung:nOutxnIn“ mit Gewichten (zeilenweise) und Bias als float32 little-endian; die ersten 16 Hex-Zeichen."""
    no, sch = d["normalisierung"], d["netz"]["schichten"]
    b = bytearray((f"stadt-policy|{d['formatVersion']}|sim{d['simVersion']}|{d['schemaHash']}|" + ",".join(d["beobachtung"]["merkmale"])
                   + "|" + ",".join(d["aktionen"]["liste"]) + "|clip").encode("ascii"))
    b += struct.pack("<d", float(no["clip"]))
    b += np.asarray(no["mittel"], dtype=np.float64).astype("<f8").tobytes() + np.asarray(no["streuung"], dtype=np.float64).astype("<f8").tobytes()
    for q in sch:
        W = np.asarray(q["gewichte"], dtype=np.float64).astype("<f4")
        b += f"|{q['aktivierung']}:{W.shape[0]}x{W.shape[1]}".encode("ascii")
        b += W.tobytes() + np.asarray(q["bias"], dtype=np.float64).astype("<f4").tobytes()
    return hashlib.sha256(bytes(b)).hexdigest()[:16]


def exportieren(laufdir: Path, checkpoint: str, name: str | None, aus: Path | None) -> Path:
    manifest = json.load(open(laufdir / "manifest.json"))
    norm = json.load(open(laufdir / "normalisierung.json"))
    zip_pfad = laufdir / f"{checkpoint}.zip"
    model = MaskablePPO.load(zip_pfad, device="cpu")
    schema = manifest["schema"]
    merkmale = schema["merkmale"]
    # Schema der aktuellen stadt.html über die Node-Umgebung: Hash in Python nachrechnen (gleiches FNV-1a) und mit dem Lauf vergleichen
    sys.path.insert(0, str(HIER))
    from stadt_env import NodeUmgebung
    node = NodeUmgebung()
    try:
        hallo = node.frage(cmd="hallo")
    finally:
        node.schliessen()
    if fnv1a32(hallo["schemaText"]) != hallo["schemaHash"]:
        raise ValueError("Schema-Hash in Python und JS verschieden")
    if hallo["schemaHash"] != schema["hash"]:
        raise ValueError(f"Lauf hat Schema {schema['hash']}, die aktuelle stadt.html {hallo['schemaHash']}")
    sim_version = manifest["sim"]["version"]                 # Stadt-Version, auf der trainiert wurde (Manifest, aus hallo beim Training)
    if sim_version != hallo["sim"]["version"]:
        raise ValueError(f"Lauf auf Stadt-Version {sim_version}, die aktuelle stadt.html ist Version {hallo['sim']['version']} (neu trainieren)")
    aktionen = manifest["aktionen"]
    if norm["schemaHash"] != schema["hash"] or norm["merkmale"] != merkmale:
        raise ValueError("Normalisierung passt nicht zum Schema des Laufs")
    obs_dim = model.observation_space.shape[0]
    if obs_dim != len(merkmale) or model.action_space.n != len(aktionen):
        raise ValueError("Checkpoint passt nicht zum Schema (Längen)")
    schichten = schichten_aus(model)
    name = name or f"{manifest['lauf']}_{checkpoint}"
    kern = {"beobachtung": {"schemaVersion": schema["version"], "laenge": len(merkmale), "merkmale": merkmale},
            "aktionen": {"liste": aktionen},
            "normalisierung": {"mittel": norm["mittel"], "streuung": norm["streuung"], "clip": norm["clip"], "quelle": norm.get("quelle")},
            "netz": {"schichten": schichten}}
    # Schritte und Validierung gehören zur Datei, nicht zum Manifest: Nach einem harten Abbruch (vor der Korrektur in trainiere.py auch nach
    # Strg+C beim Fortsetzen) kann das Manifest einen älteren Stand beschreiben. Schritte daher immer aus dem Checkpoint (num_timesteps), die
    # Validierung aus dem Manifest nur bei gleicher sha256, sonst aus validierung.jsonl (Eintrag „bester“ mit genau diesen Schritten)
    ck = manifest.get("checkpoints", {}).get(checkpoint) or {}
    zip_sha = hashlib.sha256(zip_pfad.read_bytes()).hexdigest()[:16]
    schritte = int(model.num_timesteps)
    validierung = ck.get("validierung")
    if ck.get("sha256") != zip_sha or ck.get("schritte") != schritte:
        validierung = None
        vj = laufdir / "validierung.jsonl"
        if checkpoint == "bester" and vj.exists():
            for z in open(vj):
                v = json.loads(z)
                if v.get("bester") and v.get("schritte") == schritte:
                    validierung = {"defizitMittel": v["defizitMittel"], "rueckgabe": v["rueckgabe"]}
        print(f"Hinweis: Manifest nennt für {checkpoint} {ck.get('schritte')} Schritte (sha256 {ck.get('sha256')}), die Datei hat {schritte} "
              f"(sha256 {zip_sha}); Schritte aus der Datei, Validierung {'aus validierung.jsonl' if validierung else 'unbekannt'}", file=sys.stderr)
    d = {"format": "stadt-policy", "formatVersion": 2, "name": name, "status": "experimentell",
         "hinweis": manifest.get("hinweis", ""),
         "simVersion": int(sim_version), "schemaHash": schema["hash"], **kern,
         "auswahl": "argmax_maskiert (größter Logit unter den erlaubten Aktionen, bei Gleichstand kleinste Nummer)",
         "herkunft": {"lauf": manifest["lauf"], "profil": manifest["profil"], "manifest": f"training/laeufe/{manifest['lauf']}/manifest.json",
                      "checkpoint": zip_pfad.name, "checkpointSha256": zip_sha,
                      "trainingsSchritte": schritte, "simHash": manifest["sim"]["hash"],
                      "belohnung": manifest["belohnung"]["version"], "versionen": manifest.get("versionen"),
                      "validierung": validierung}}
    d["hash"] = inhalt_hash(d)
    aus = aus or (BASIS / "ki" / f"policy_{name}.json")
    aus.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(d, ensure_ascii=False, separators=(",", ":"))
    aus.write_text(text)
    return aus


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lauf", required=True)
    ap.add_argument("--checkpoint", default="bester", choices=["bester", "letzter"])
    ap.add_argument("--name")
    ap.add_argument("--aus")
    a = ap.parse_args()
    laufdir = Path(a.lauf).resolve()
    if a.checkpoint == "bester" and not (laufdir / "bester.zip").exists():
        print("kein bester.zip im Lauf, nehme letzter.zip", file=sys.stderr)
        a.checkpoint = "letzter"
    p = exportieren(laufdir, a.checkpoint, a.name, Path(a.aus).resolve() if a.aus else None)
    d = json.load(open(p))
    print(f"exportiert: {p} ({p.stat().st_size} Byte), Hash {d['hash']}, Schema {d['schemaHash']}, "
          f"Schichten {[len(s['gewichte']) for s in d['netz']['schichten']]}, Status {d['status']}")


if __name__ == "__main__":
    main()
