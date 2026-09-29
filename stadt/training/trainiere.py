#!/usr/bin/env python3
"""Training der Entscheidungs-Policy (Etappe 1): MaskablePPO aus sb3-contrib auf der STADT-Umgebung.

    python training/trainiere.py --profil smoke [--name mein_lauf]
    python training/trainiere.py --fortsetzen training/laeufe/<lauf> [--zusatz 20000]

Stoppen: Strg+C oder SIGTERM (kill <pid>) während des Trainings: Der Lauf hört nach dem laufenden Schritt auf, schreibt letzter.zip und das
Manifest („abgebrochen: von Hand gestoppt“) und lässt sich mit --fortsetzen weiterführen; ein zweites Strg+C bricht hart ab. Auch dann
(und nach kill -9) stimmen Manifest und Checkpoints: Beide werden nach jedem Rollout geschrieben, jeweils erst unter einem Nebennamen,
das Manifest direkt nach letzter.zip und noch einmal nach der Validierung; fällt der Abbruch in eine Validierung, fehlt nur deren Ergebnis.

Ergebnis je Lauf in training/laeufe/<lauf>/: manifest.json (Konfig, Code- und Sim-Hash, Schema, Seeds, Schritte, Laufzeit, Hardware,
Belohnungsteile, Episodenlängen, Aktionsverteilung, PPO-Kennzahlen, Parameteränderung), normalisierung.json, letzter.zip, bester.zip
(nach Validierung), anfang_parameter.npz, sb3/progress.csv, episoden.jsonl, validierung.jsonl.

Namen aus sb3-contrib 2.9.0 / stable-baselines3 2.9.0, im installierten Quelltext nachgesehen (training/VERSIONEN.txt):
MaskablePPO(policy, env, learning_rate, n_steps, batch_size, n_epochs, gamma, gae_lambda, clip_range, ent_coef, vf_coef, max_grad_norm,
policy_kwargs, seed, device), predict(obs, deterministic=..., action_masks=...), learn(total_timesteps, callback, reset_num_timesteps),
Methode action_masks der Umgebung, BaseCallback (_on_step, _on_rollout_end, self.locals), Monitor, DummyVecEnv, logger.configure.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import signal
import sys
import time
from pathlib import Path

import numpy as np
import torch
from sb3_contrib import MaskablePPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.logger import configure
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv

T_PROGRAMM = time.time()                                    # Programmstart (Wandzeit des Laufs)
HIER = Path(__file__).resolve().parent
BASIS = HIER.parent
sys.path.insert(0, str(HIER))
from stadt_env import StadtEnv  # noqa: E402

CODE_DATEIEN = ["training/trainiere.py", "training/stadt_env.py", "tools/kiumgebung.mjs", "tools/kiepisode.mjs", "tools/simkern.mjs"]


def sha256_datei(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def jetzt() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def json_sicher(d: dict, pfad: Path) -> None:
    """JSON erst unter <name>.neu schreiben, dann umbenennen: Ein harter Abbruch hinterlässt nie ein halbes Manifest."""
    neu = pfad.with_name(pfad.name + ".neu")
    with open(neu, "w") as f:
        json.dump(d, f, indent=1, ensure_ascii=False)
    os.replace(neu, pfad)


def sichern(model, pfad: Path) -> None:
    """Checkpoint erst als <name>.neu.zip, dann umbenennen (nie ein halb geschriebenes Zip unter dem echten Namen)."""
    neu = pfad.with_name(pfad.stem + ".neu.zip")
    model.save(neu)
    os.replace(neu, pfad)


# Stoppen von Hand: das erste SIGINT/SIGTERM setzt nur die Marke (Begleiter._on_step beendet learn wie beim Zeitlimit), das zweite bricht
# hart ab. Die Node-Prozesse laufen in einer eigenen Sitzung (stadt_env.NodeUmgebung) und bekommen das Strg+C des Terminals nicht ab.
HALT = {"signal": None}


def halt_marke(signum, _frame) -> None:
    HALT["signal"] = signal.Signals(signum).name
    print(f"\n{HALT['signal']}: Das Training hört nach dem laufenden Schritt auf und schreibt letzter.zip und das Manifest "
          "(noch einmal: harter Abbruch, Stand vom letzten Rollout).", flush=True)
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)


def hardware() -> dict:
    cpu = ""
    try:
        for z in open("/proc/cpuinfo"):
            if z.startswith("model name"):
                cpu = z.split(":", 1)[1].strip()
                break
    except OSError:
        pass
    return {"cpu": cpu, "kerne": os.cpu_count(), "last_1_5_15": list(os.getloadavg()), "gpu": torch.cuda.is_available(),
            "torch_threads": torch.get_num_threads(), "system": platform.platform(), "python": platform.python_version()}


def versionen() -> dict:
    import gymnasium
    import sb3_contrib
    import stable_baselines3
    return {"torch": torch.__version__, "numpy": np.__version__, "gymnasium": gymnasium.__version__,
            "stable_baselines3": stable_baselines3.__version__, "sb3_contrib": sb3_contrib.__version__}


def statistik(werte):
    a = np.asarray(werte, dtype=np.float64)
    if a.size == 0:
        return {"n": 0}
    return {"n": int(a.size), "mittel": float(a.mean()), "streuung": float(a.std(ddof=1)) if a.size > 1 else 0.0,
            "min": float(a.min()), "max": float(a.max())}


# ─── Normalisierung: nur aus Trainingsdaten (Regelarm auf Trainingsseeds), gespeichert, im Browser identisch angewandt ───
def normalisierung_berechnen(seeds, k: dict, log: str) -> dict:
    env = StadtEnv(seeds, normalisierung=None, szenario=k["szenario"], gruppe=k["gruppe"], tage=k["tage"], log=log, reihum=True,
                   belohnung=k["belohnung"])
    try:
        beobs = []
        for e in range(k["norm_episoden"]):
            obs, info = env.reset(options={"seed": seeds[e % len(seeds)], "nr": 1000 + e})
            fertig = bool(info.get("schon_vorbei"))            # Person vor der ersten Entscheidung weg: nichts von ihr aufnehmen
            if not fertig:
                beobs.append(env.letzte_rohe_beobachtung())
            while not fertig:
                _, _, term, trunc, _ = env.step_regel()
                fertig = term or trunc
                if not fertig:
                    beobs.append(env.letzte_rohe_beobachtung())
        X = np.stack(beobs).astype(np.float64)
        mittel = X.mean(axis=0)
        std = X.std(axis=0)
        streuung = np.where(std <= 0, 1.0, np.maximum(std, k["norm_streuung_min"]))
        merkmale = env.hallo["beobachtung"]["merkmale"]
        return {"version": 1, "schemaHash": env.hallo["schemaHash"], "merkmale": merkmale,
                "mittel": [float(v) for v in mittel], "streuung": [float(v) for v in streuung], "clip": k["norm_clip"],
                "quelle": {"arm": "regeln", "seeds": sorted(set(seeds[e % len(seeds)] for e in range(k["norm_episoden"]))),
                           "episoden": k["norm_episoden"], "beobachtungen": int(X.shape[0]),
                           "konstant": [m for m, s in zip(merkmale, std) if s <= 0],          # im Spiel nur bei 0 Abweichung ohne Clip
                           "an_der_untergrenze": [m for m, s in zip(merkmale, std) if 0 < s < k["norm_streuung_min"]]}}
    finally:
        env.close()


def validieren(model, env: StadtEnv, seeds, n: int, regeln: bool = False) -> dict:
    """Feste Validierungsepisoden (Seeds ab 20000), deterministisch und maskiert; regeln=True: Vergleichsarm."""
    rueck, defizit, enden, entsch = [], [], {}, []
    for e in range(n):
        obs, info = env.reset(options={"seed": seeds[e % len(seeds)], "nr": e // len(seeds)})
        summe, fertig = 0.0, bool(info.get("schon_vorbei"))   # schon beim Start vorbei: zählt mit der Metrik aus dem reset
        while not fertig:
            if regeln:
                obs, r, term, trunc, info = env.step_regel()
            else:
                a, _ = model.predict(obs, deterministic=True, action_masks=env.action_masks())
                obs, r, term, trunc, info = env.step(int(a))
            summe += r
            fertig = term or trunc
        m = info["metrik"]
        rueck.append(summe); defizit.append(m["defizitMittel"]); entsch.append(m["entscheidungen"])
        enden[m["ende"]] = enden.get(m["ende"], 0) + 1
    return {"episoden": n, "rueckgabe": statistik(rueck), "defizitMittel": statistik(defizit), "enden": enden, "entscheidungen": statistik(entsch)}


class Begleiter(BaseCallback):
    """Zeitlimit, Episodenstatistik, Aktionsverteilung, letzter Checkpoint je Rollout, Validierung und bester Checkpoint."""

    def __init__(self, laufdir: Path, k: dict, val_env: StadtEnv, val_seeds, zustand: dict, t_start: float | None = None, zwischenstand=None):
        super().__init__()
        self.laufdir, self.k, self.val_env, self.val_seeds, self.z = laufdir, k, val_env, val_seeds, zustand
        self.zwischenstand = zwischenstand                  # schreibt nach jedem Rollout Manifest und Checkpoint-Angaben (harter Abbruch)
        self.t0 = time.time()
        # Frist: Zeitlimit des Trainings (zeit_min) und, falls gesetzt, Wandzeit ab Programmstart abzüglich Reserve für Abschlussvalidierung
        # und Manifest (lokaler Lauf V9: höchstens 30 min Wandzeit insgesamt)
        self.frist = self.t0 + 60 * k["zeit_min"]
        if k.get("wandzeit_min") and t_start is not None:
            self.frist = min(self.frist, t_start + 60 * (k["wandzeit_min"] - k.get("reserve_min", 1.5)))
        self.naechste_val = zustand.get("naechste_val", k["val_alle"])
        self.epi_datei = open(laufdir / "episoden.jsonl", "a")
        self.val_datei = open(laufdir / "validierung.jsonl", "a")

    def _on_step(self) -> bool:
        acts = self.locals["actions"]
        for a in np.asarray(acts).reshape(-1):
            name = self.z["aktionen"][int(a)]
            self.z["aktionsverteilung"][name] = self.z["aktionsverteilung"].get(name, 0) + 1
        for info, done in zip(self.locals["infos"], self.locals["dones"]):
            if done and "metrik" in info:
                m = info["metrik"]
                zeile = {"schritte": int(self.num_timesteps), "belohnung": info.get("episode", {}).get("r"), "summe": info.get("summe"),
                         "stunden": m["stunden"] + m["rest"], "gelebt": m["stunden"], "entscheidungen": m["entscheidungen"], "ende": m["ende"],
                         "defizitMittel": m["defizitMittel"], "umkehr": m["umkehr"], "abgelehnt": m["abgelehnt"], "fehlgeschlagen": m["fehlgeschlagen"],
                         "maskeVerletzt": m["maskeVerletzt"], "seed": m["seed"], "gruppe": m["gruppe"]}
                self.epi_datei.write(json.dumps(zeile) + "\n")
                self.epi_datei.flush()
                self.z["episoden"] += 1
                if m["maskeVerletzt"]:
                    raise RuntimeError("Maske verletzt – harte Invariante")
        if HALT["signal"]:
            self.z["abbruch"] = f"von Hand gestoppt ({HALT['signal']})"
            return False
        if time.time() > self.frist:
            self.z["abbruch"] = (f"Zeitlimit erreicht (Training {self.k['zeit_min']} min"
                                 + (f", Wandzeit {self.k['wandzeit_min']} min abzüglich {self.k.get('reserve_min', 1.5)} min Reserve" if self.k.get("wandzeit_min") else "") + ")")
            return False
        return True

    def _on_rollout_end(self) -> None:
        sichern(self.model, self.laufdir / "letzter.zip")
        self.z["letzter_schritte"] = int(self.num_timesteps)
        if self.zwischenstand:                              # Manifest passt zu letzter.zip, auch wenn die Validierung abbricht
            self.zwischenstand()
        if self.num_timesteps >= self.naechste_val:
            self.naechste_val = self.num_timesteps + self.k["val_alle"]
            self.z["naechste_val"] = self.naechste_val
            v = validieren(self.model, self.val_env, self.val_seeds, self.k["val_episoden"])
            v["schritte"] = int(self.num_timesteps)
            v["zeit_s"] = round(time.time() - self.t0, 1)
            v["abschluss"] = bool(self.z.get("abschluss"))   # True: nach dem letzten PPO-Update (sonst vor dem Update dieses Rollouts)
            besser = self.z["bester"] is None or v["defizitMittel"]["mittel"] < self.z["bester"]["defizitMittel"]["mittel"]
            v["bester"] = besser
            self.val_datei.write(json.dumps(v) + "\n")
            self.val_datei.flush()
            if besser:
                sichern(self.model, self.laufdir / "bester.zip")
                self.z["bester"] = v
            if self.zwischenstand:                          # Validierung und bester.zip ins Manifest
                self.zwischenstand()
            print(f"  Validierung bei {v['schritte']} Schritten: Defizit Ø {v['defizitMittel']['mittel']:.2f}, Rückgabe Ø "
                  f"{v['rueckgabe']['mittel']:.2f}{'  (bester)' if besser else ''}", flush=True)

    def _on_training_end(self) -> None:
        self.epi_datei.close()
        self.val_datei.close()


def checkpoint_angaben(laufdir: Path, zustand: dict, bester_aenderung=None) -> dict:
    """Manifest-Eintrag je Checkpoint: Schritte und sha256 der Datei, wie sie gerade auf der Platte liegt."""
    ck = {"letzter": {"datei": "letzter.zip", "schritte": zustand.get("letzter_schritte"), "sha256": sha256_datei(laufdir / "letzter.zip")[:16]}
          if (laufdir / "letzter.zip").exists() else None, "bester": None}
    if zustand.get("bester") and (laufdir / "bester.zip").exists():
        ck["bester"] = {"datei": "bester.zip", "schritte": zustand["bester"]["schritte"], "sha256": sha256_datei(laufdir / "bester.zip")[:16],
                        "validierung": {"defizitMittel": zustand["bester"]["defizitMittel"], "rueckgabe": zustand["bester"]["rueckgabe"]}}
        if bester_aenderung is not None:
            ck["bester"]["parameter_l2_differenz_zum_anfang"] = bester_aenderung
    return ck


def parameter(model) -> dict:
    return {k: v.detach().cpu().numpy().copy() for k, v in model.policy.state_dict().items()}


def parameter_aenderung(anfang: dict, ende: dict) -> dict:
    je = {}
    ges = 0.0
    for k, v in ende.items():
        if k not in anfang:
            continue
        d = float(np.linalg.norm((v.astype(np.float64) - anfang[k].astype(np.float64)).ravel()))
        je[k] = {"l2_differenz": d, "l2_anfang": float(np.linalg.norm(anfang[k].astype(np.float64).ravel())), "form": list(v.shape)}
        ges += d * d
    return {"gesamt_l2_differenz": ges ** 0.5, "je_tensor": je}


def ppo_kennzahlen(laufdir: Path) -> dict:
    p = laufdir / "sb3" / "progress.csv"
    if not p.exists():
        return {}
    import csv
    zeilen = list(csv.DictReader(open(p)))
    if not zeilen:
        return {}
    keys = [k for k in zeilen[-1].keys() if k.startswith("train/") or k.startswith("rollout/") or k.startswith("time/")]
    letzte = {}
    for k in keys:  # letzter nicht leerer Wert je Kennzahl
        for z in reversed(zeilen):
            if z.get(k) not in (None, ""):
                letzte[k] = float(z[k])
                break
    return {"updates": len(zeilen), "letzte": letzte, "datei": "sb3/progress.csv"}


def lernkurve(laufdir: Path, epis: list, validierung: list, fenster: int = 8192) -> dict:
    """Lernkurve fürs Manifest: je PPO-Update die SB3-Kennzahlen (sb3/progress.csv), je Fenster von Schritten die Trainingsepisoden
    (Belohnung, Defizit, Wegzüge) und die Validierungen (Defizit, Rückgabe, bester)."""
    import csv
    ppo = []
    p = laufdir / "sb3" / "progress.csv"
    if p.exists():
        felder = ["time/total_timesteps", "rollout/ep_rew_mean", "rollout/ep_len_mean", "train/entropy_loss", "train/approx_kl",
                  "train/clip_fraction", "train/value_loss", "train/policy_gradient_loss", "train/explained_variance", "time/fps"]
        for z in csv.DictReader(open(p)):
            ppo.append({f.split("/")[1]: (float(z[f]) if z.get(f) not in (None, "") else None) for f in felder})
    bins = {}
    for e in epis:
        b = int(e["schritte"]) // fenster
        bins.setdefault(b, []).append(e)
    trainepisoden = []
    for b in sorted(bins):
        E = bins[b]
        bel = [e["belohnung"] for e in E if e["belohnung"] is not None]
        trainepisoden.append({"bis_schritt": (b + 1) * fenster, "episoden": len(E), "belohnung": statistik(bel),
                              "defizitMittel": statistik([e["defizitMittel"] for e in E]),
                              "wegzug": sum(1 for e in E if e["ende"] in ("wegzug", "weg")), "umkehr": sum(e["umkehr"] for e in E)})
    val = [{"schritte": v["schritte"], "defizit": v["defizitMittel"]["mittel"], "defizit_streuung": v["defizitMittel"].get("streuung"),
            "rueckgabe": v["rueckgabe"]["mittel"], "bester": v.get("bester"), "abschluss": v.get("abschluss")} for v in validierung]
    return {"fenster_schritte": fenster, "ppo_je_update": ppo, "trainingsepisoden_je_fenster": trainepisoden, "validierung": val}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profil", choices=["smoke", "lokal", "lokal_v9", "langlauf"])
    ap.add_argument("--name")
    ap.add_argument("--fortsetzen", help="Laufordner: letzter.zip weiter trainieren")
    ap.add_argument("--zusatz", type=int, default=0, help="beim Fortsetzen: so viele Schritte zusätzlich")
    ap.add_argument("--zeit-min", type=float, help="Zeitlimit des Trainings in Minuten statt dem des Profils (steht im Manifest unter konfig)")
    ap.add_argument("--wand-min", type=float, help="Wandzeit des ganzen Laufs in Minuten ab Programmstart (Normalisierung, Regelarm, Training, "
                    "Abschlussvalidierung); das Training endet so, dass 1,5 min Reserve bleiben (steht im Manifest unter konfig)")
    args = ap.parse_args()
    konfig = json.load(open(HIER / "konfig.json"))
    seeds = json.load(open(HIER / "seeds.json"))

    if args.fortsetzen:
        laufdir = Path(args.fortsetzen).resolve()
        if not (laufdir / "manifest.json").exists() or not (laufdir / "letzter.zip").exists():
            ap.error(f"{laufdir}: kein manifest.json oder letzter.zip (vor dem ersten Rollout abgebrochen?) – neu starten, mit neuem --name")
        manifest = json.load(open(laufdir / "manifest.json"))
        profil = manifest["profil"]
        k = manifest["konfig"]
        k.setdefault("belohnung", manifest["belohnung"]["version"])   # Läufe vor Belohnung v2 hatten den Schlüssel nicht: gleiche Version weiter
        norm = json.load(open(laufdir / "normalisierung.json"))
    else:
        if not args.profil:
            ap.error("--profil oder --fortsetzen angeben")
        profil = args.profil
        k = dict(konfig["gemeinsam"], **konfig["profile"][profil], profil=profil)
        if args.zeit_min:                                   # z. B. Durchsatzmessung mit dem Profil lokal (V9-Übertrag)
            k["zeit_min"] = args.zeit_min
        if args.wand_min:                                   # lokaler Lauf V9: höchstens 30 min Wandzeit insgesamt
            k["wandzeit_min"] = args.wand_min
            k["reserve_min"] = 1.5
        name = args.name or f"{profil}_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}"
        laufdir = HIER / "laeufe" / name
        if laufdir.exists():
            ap.error(f"Lauf „{name}“ gibt es schon ({laufdir}): anderen --name wählen oder mit --fortsetzen {laufdir} weitermachen")
        laufdir.mkdir(parents=True)
        manifest = {"lauf": name, "profil": profil, "konfig": k, "beginn": jetzt(), "fortsetzungen": [], "status": "läuft"}
        norm = None

    torch.set_num_threads(int(k["torch_threads"]))
    train_seeds = seeds["training"][: k["trainseeds"]]
    val_seeds = seeds["validierung"]
    log = str(laufdir / "node.log")

    t_start = T_PROGRAMM if not args.fortsetzen else time.time()
    if norm is None:
        print(f"Normalisierung aus {k['norm_episoden']} Regel-Episoden auf Trainingsseeds …", flush=True)
        norm = normalisierung_berechnen(train_seeds, k, log)
        json.dump(norm, open(laufdir / "normalisierung.json", "w"), indent=1)

    env = DummyVecEnv([lambda: Monitor(StadtEnv(train_seeds, normalisierung=norm, szenario=k["szenario"], gruppe=k["gruppe"],
                                                 tage=k["tage"], vorspulen=k["vorspulen"], log=log, belohnung=k["belohnung"]))])
    val_env = StadtEnv(val_seeds, normalisierung=norm, szenario=k["szenario"], gruppe=k["gruppe"], tage=k["tage"], log=log, reihum=True,
                       belohnung=k["belohnung"])
    hallo = val_env.hallo
    aktionen = hallo["aktionen"]

    if args.fortsetzen:
        model = MaskablePPO.load(laufdir / "letzter.zip", env=env, device="cpu")
        model.set_logger(configure(str(laufdir / "sb3"), ["csv", "log"]))
        zustand = manifest.get("_zustand") or {}
        zustand.pop("abbruch", None)                        # Abbruchgrund und Abschluss-Marke galten dem vorigen Teil, nicht diesem
        zustand.pop("abschluss", None)
        zustand["letzter_schritte"] = int(model.num_timesteps)
        zustand.setdefault("aktionsverteilung", {})
        zustand["aktionen"] = aktionen
        zustand.setdefault("episoden", 0)
        zustand.setdefault("bester", None)
        zusatz = int(args.zusatz or k["timesteps"])
        ziel = model.num_timesteps + zusatz
        manifest["fortsetzungen"].append({"beginn": jetzt(), "ab_schritt": int(model.num_timesteps), "ziel": int(ziel)})
        manifest["status"] = "läuft"                        # bis zum Ende dieses Teils (sonst stünde hier noch „fertig“ vom vorigen)
    else:
        model = MaskablePPO(
            "MlpPolicy", env, learning_rate=k["learning_rate"], n_steps=k["n_steps"], batch_size=k["batch_size"], n_epochs=k["n_epochs"],
            gamma=k["gamma"], gae_lambda=k["gae_lambda"], clip_range=k["clip_range"], ent_coef=k["ent_coef"], vf_coef=k["vf_coef"],
            max_grad_norm=k["max_grad_norm"], seed=k["seed"], device="cpu", verbose=0,
            policy_kwargs=dict(net_arch=dict(pi=list(k["net_arch"]), vf=list(k["net_arch"])),
                               activation_fn=torch.nn.Tanh if k["aktivierung"] == "tanh" else torch.nn.ReLU))
        model.set_logger(configure(str(laufdir / "sb3"), ["csv", "log"]))
        np.savez(laufdir / "anfang_parameter.npz", **parameter(model))
        zustand = {"aktionsverteilung": {}, "aktionen": aktionen, "episoden": 0, "bester": None}
        ziel = k["timesteps"]
        zusatz = ziel
        print("Regelarm auf den Validierungsepisoden (Vergleichswert) …", flush=True)
        manifest["regeln_validierung"] = validieren(None, val_env, val_seeds, k["val_episoden"], regeln=True)
        print(f"  Regeln: Defizit Ø {manifest['regeln_validierung']['defizitMittel']['mittel']:.2f}, Rückgabe Ø "
              f"{manifest['regeln_validierung']['rueckgabe']['mittel']:.2f}", flush=True)

    manifest.update({
        "code_hash": {d: sha256_datei(BASIS / d)[:16] for d in CODE_DATEIEN},
        "sim": {"hash": hallo["sim"]["hash"], "version": hallo["sim"]["version"], "stadt_html_sha256": sha256_datei(BASIS / "stadt.html")[:16]},
        "schema": {"version": hallo["beobachtung"]["schemaVersion"], "hash": hallo["schemaHash"], "merkmale": hallo["beobachtung"]["merkmale"]},
        "aktionen": aktionen, "belohnung": hallo["belohnung"], "protokoll": hallo["protokoll"],
        "seeds": {"datei": "training/seeds.json", "training": train_seeds, "validierung_benutzt": val_seeds[: k["val_episoden"]],
                  "abschluss": "nicht benutzt"},
        "normalisierung": "normalisierung.json", "normalisierung_quelle": norm.get("quelle"), "hardware": hardware(), "versionen": versionen()})
    json_sicher(manifest, laufdir / "manifest.json")

    def zwischenstand():                                    # nach jedem Rollout: Manifest passt immer zu letzter.zip und bester.zip
        manifest.update({"status": "läuft", "schritte": int(model.num_timesteps), "stand": jetzt(),
                         "checkpoints": checkpoint_angaben(laufdir, zustand),
                         "_zustand": {kk: v for kk, v in zustand.items() if kk != "aktionen"}})
        if args.fortsetzen:
            manifest["fortsetzungen"][-1]["bis_schritt"] = int(model.num_timesteps)
        json_sicher(manifest, laufdir / "manifest.json")

    begleiter = Begleiter(laufdir, k, val_env, val_seeds, zustand, t_start=t_start, zwischenstand=zwischenstand)
    print(f"Training {profil}: Ziel {ziel} Schritte, höchstens {k['zeit_min']} min, Lauf {laufdir.name} "
          f"(PID {os.getpid()}; stoppen mit Strg+C oder kill {os.getpid()})", flush=True)
    t0 = time.time()
    fehler = None
    signal.signal(signal.SIGINT, halt_marke)
    signal.signal(signal.SIGTERM, halt_marke)
    try:
        # SB3 2.9.0 (_setup_learn): mit reset_num_timesteps=False zählt total_timesteps zusätzlich zu num_timesteps
        model.learn(total_timesteps=int(zusatz), callback=begleiter, reset_num_timesteps=not args.fortsetzen)
    except Exception as e:  # harte Fehler landen im Manifest und brechen ab
        fehler = f"{type(e).__name__}: {e}"
        print("FEHLER:", fehler, flush=True)
    finally:
        signal.signal(signal.SIGINT, signal.default_int_handler)   # ab hier wieder hart (Abschluss dauert Sekunden)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
    dauer = time.time() - t0
    model.logger.dump(model.num_timesteps)                  # letzte Trainingskennzahlen (learn schreibt sie erst beim nächsten Rollout)
    sichern(model, laufdir / "letzter.zip")
    zustand["letzter_schritte"] = int(model.num_timesteps)
    zwischenstand()
    # Abschlussvalidierung des letzten Stands, falls seit der letzten mehr gelernt wurde (nicht nach Stoppen von Hand)
    if fehler is None and not HALT["signal"] and (zustand["bester"] is None or zustand["bester"]["schritte"] < model.num_timesteps):
        zustand["abschluss"] = True
        begleiter.naechste_val = 0
        begleiter.val_datei = open(laufdir / "validierung.jsonl", "a")
        begleiter._on_rollout_end()
        begleiter.val_datei.close()

    anfang = dict(np.load(laufdir / "anfang_parameter.npz"))
    aenderung = parameter_aenderung(anfang, parameter(model))
    bester_aenderung = None
    if (laufdir / "bester.zip").exists():
        b = MaskablePPO.load(laufdir / "bester.zip", device="cpu")
        bester_aenderung = parameter_aenderung(anfang, parameter(b))["gesamt_l2_differenz"]
    epis = [json.loads(z) for z in open(laufdir / "episoden.jsonl")] if (laufdir / "episoden.jsonl").exists() else []
    teile = {}
    for e in epis:
        for kk, v in (e.get("summe") or {}).items():
            teile.setdefault(kk, []).append(v)
    enden = {}
    for e in epis:
        enden[e["ende"]] = enden.get(e["ende"], 0) + 1
    manifest.update({
        "status": "fehler" if fehler else ("abgebrochen: " + zustand["abbruch"] if zustand.get("abbruch") else "fertig"),
        "fehler": fehler, "ende": jetzt(), "laufzeit_s": round(time.time() - t_start, 1), "training_s": round(dauer, 1),
        "schritte": int(model.num_timesteps), "schritte_je_s": round((model.num_timesteps - (manifest["fortsetzungen"][-1]["ab_schritt"] if args.fortsetzen else 0)) / max(dauer, 1e-9), 1),
        "episoden": {"anzahl": len(epis), "stunden": statistik([e["stunden"] for e in epis]), "gelebt": statistik([e["gelebt"] for e in epis]),
                     "entscheidungen": statistik([e["entscheidungen"] for e in epis]), "enden": enden,
                     "belohnung": statistik([e["belohnung"] for e in epis if e["belohnung"] is not None]),
                     "belohnungsteile": {kk: statistik(v) for kk, v in teile.items()},
                     "defizitMittel": statistik([e["defizitMittel"] for e in epis])},
        "aktionsverteilung": zustand["aktionsverteilung"], "ppo": ppo_kennzahlen(laufdir),
        "validierung": [json.loads(z) for z in open(laufdir / "validierung.jsonl")] if (laufdir / "validierung.jsonl").exists() else [],
        "checkpoints": checkpoint_angaben(laufdir, zustand, bester_aenderung),
        "parameter_aenderung": aenderung, "hardware_ende": hardware(),
        "lernkurve": lernkurve(laufdir, epis, [json.loads(z) for z in open(laufdir / "validierung.jsonl")] if (laufdir / "validierung.jsonl").exists() else []),
        "hinweis": "Ein Smoke-Lauf belegt nur, dass die Kette läuft; kein Qualitätsbeleg." if profil == "smoke" else
                   "Vorläufig: ein Trainingsseed, Validierung nur zur Kandidatenwahl, keine Abschlussseeds benutzt.",
        "_zustand": {kk: v for kk, v in zustand.items() if kk != "aktionen"}})
    manifest.pop("stand", None)
    if args.fortsetzen:
        manifest["fortsetzungen"][-1].update({"ende": jetzt(), "bis_schritt": int(model.num_timesteps)})
    json_sicher(manifest, laufdir / "manifest.json")
    env.close()
    val_env.close()
    print(f"Fertig: {manifest['status']}, {model.num_timesteps} Schritte in {dauer:.0f} s, Parameteränderung (L2) "
          f"{aenderung['gesamt_l2_differenz']:.4f}, Lauf {laufdir}", flush=True)
    return 1 if fehler else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nHart abgebrochen. Gab es schon einen Rollout, stehen Manifest und Checkpoints auf dessen Stand (weiter mit --fortsetzen); "
              "sonst den Lauf mit neuem --name neu starten.", file=sys.stderr)
        sys.exit(130)
