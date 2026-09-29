"""STADT-Trainingsumgebung für gymnasium (Etappe 1).

Die Simulation läuft in einem Node-Unterprozess (tools/kiumgebung.mjs, JSONL-Protokoll v1), derselbe sim-Block wie im Spiel.
Diese Klasse übersetzt nur: Seeds wählen, Beobachtung normalisieren, Maske bereitstellen (Methode ``action_masks``, der Name, den
sb3-contrib 2.9.0 sucht: ``sb3_contrib.common.maskable.utils.EXPECTED_METHOD_NAME``).

Nichts hier erfindet Zustand: Belohnung, Ende und Maske kommen aus Node. Technische Fehler (ok: false) lösen eine Ausnahme aus.
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import gymnasium as gym
import numpy as np
from gymnasium import spaces

BASIS = Path(__file__).resolve().parent.parent          # Ordner mit stadt.html, tools/, training/, ki/
UMGEBUNG_JS = BASIS / "tools" / "kiumgebung.mjs"


class NodeUmgebung:
    """Dauerhafter Node-Prozess, eine Anfrage und eine Antwort je Zeile."""

    def __init__(self, html: str | None = None, log: str | None = None, belohnung: str | None = None):
        cmd = ["node", str(UMGEBUNG_JS)] + (["--html", html] if html else []) + (["--belohnung", belohnung] if belohnung else [])
        self._log = open(log, "a") if log else subprocess.DEVNULL
        # eigene Sitzung: Strg+C im Terminal trifft nur Python (trainiere.py hört dann geordnet auf); endet Python, schließt sich stdin
        # und Node beendet sich selbst (tools/kiumgebung.mjs)
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self._log,
                                     text=True, bufsize=1, cwd=str(BASIS), start_new_session=True)
        self._nr = 0

    def frage(self, **q):
        self._nr += 1
        q["id"] = self._nr
        self.proc.stdin.write(json.dumps(q) + "\n")
        self.proc.stdin.flush()
        zeile = self.proc.stdout.readline()
        if not zeile:
            raise RuntimeError(f"Node-Umgebung antwortet nicht mehr (Exit {self.proc.poll()})")
        a = json.loads(zeile)
        if a.get("id") != self._nr:
            raise RuntimeError(f"Antwort passt nicht zur Anfrage: {a.get('id')} statt {self._nr}")
        return a

    def schliessen(self):
        if self.proc.poll() is None:
            try:
                self.frage(cmd="close")
            except Exception:
                pass
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        if self._log is not subprocess.DEVNULL:
            self._log.close()


class TechnischerFehler(RuntimeError):
    """Harter Fehler aus der Umgebung (Invariante, Maske, Ausnahme in der Sim)."""


class StadtEnv(gym.Env):
    """Eine Fokusperson je Episode; Schritt = bis zum nächsten Entscheidungszeitpunkt (vorspulen) oder eine Spielstunde."""

    metadata = {"render_modes": []}

    def __init__(self, seeds, normalisierung: dict | None = None, szenario="stabil", gruppe="alle", tage=30,
                 vorspulen=True, html=None, log=None, rohe_beobachtung=False, reihum=False, belohnung=None):
        super().__init__()
        self.node = NodeUmgebung(html=html, log=log, belohnung=belohnung)
        h = self.node.frage(cmd="hallo")
        if not h["ok"]:
            raise TechnischerFehler(h)
        if belohnung and h["belohnung"]["version"] != belohnung:
            raise TechnischerFehler(f"Umgebung rechnet {h['belohnung']['version']} statt {belohnung}")
        self.hallo = h
        self.n = h["beobachtung"]["laenge"]
        self.aktionen = h["aktionen"]
        self.seeds = list(seeds)
        self.szenario, self.gruppe, self.tage, self.vorspulen = szenario, gruppe, tage, vorspulen
        self.reihum = reihum                                  # Auswertung: Seeds der Reihe nach statt zufällig
        self.roh = rohe_beobachtung
        self.norm = normalisierung
        if normalisierung is not None:
            if normalisierung["schemaHash"] != h["schemaHash"]:
                raise ValueError(f"Normalisierung für Schema {normalisierung['schemaHash']}, Umgebung hat {h['schemaHash']}")
            self._mittel = np.asarray(normalisierung["mittel"], dtype=np.float64)
            self._streuung = np.asarray(normalisierung["streuung"], dtype=np.float64)
            self._clip = float(normalisierung["clip"])
            lo, hi = -self._clip, self._clip
        else:
            lo, hi = -np.inf, np.inf
        self.observation_space = spaces.Box(lo, hi, shape=(self.n,), dtype=np.float32)
        self.action_space = spaces.Discrete(len(self.aktionen))
        self._maske = np.zeros(len(self.aktionen), dtype=bool)
        self._maske[0] = True
        self._episode = 0
        self._letzte_roh = None

    # Normalisierung wie im Browser (Sim.KI.policyRechnen): (x − Mittel) / Streuung, begrenzt, dann float32
    def normiere(self, roh):
        x = np.asarray(roh, dtype=np.float32).astype(np.float64)
        if self.norm is None or self.roh:
            return x.astype(np.float32)
        z = np.clip((x - self._mittel) / self._streuung, -self._clip, self._clip)
        return z.astype(np.float32)

    def _antwort(self, a):
        if not a["ok"]:
            raise TechnischerFehler(f"{a.get('code')}: {a.get('fehler')}")
        self._maske = np.asarray(a["maske"], dtype=bool)
        self._letzte_roh = np.asarray(a["beob"], dtype=np.float32)
        return self.normiere(a["beob"])

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        options = options or {}
        versuche = 0
        while True:
            if "seed" in options:
                s = int(options["seed"])
            elif self.reihum:
                s = self.seeds[self._episode % len(self.seeds)]
            else:
                s = int(self.seeds[int(self.np_random.integers(len(self.seeds)))])
            nr = int(options.get("nr", self._episode))
            self._episode += 1
            a = self.node.frage(cmd="reset", seed=s, nr=nr, szenario=options.get("szenario", self.szenario),
                                gruppe=options.get("gruppe", self.gruppe), tage=options.get("tage", self.tage))
            if not a["ok"] and a.get("code") == "keine_fokusperson" and versuche < 20 and "seed" not in options:
                versuche += 1
                continue
            obs = self._antwort(a)
            # Episode schon beim Start vorbei: Die Fokusperson ist vor ihrer ersten Entscheidung weggezogen oder gestorben (selten, z. B.
            # Seed 10023, nr 1151). gymnasium kennt kein Ende im reset: ohne festen Seed die nächste Episode; mit festem Seed steht
            # schon_vorbei in info, und der Aufrufer zählt sie als beendete Episode ohne Schritt (wie tools/werte_aus.mjs)
            if a["beendet"] or a["abgeschnitten"]:
                if "seed" not in options and versuche < 20:
                    versuche += 1
                    continue
                return obs, dict(a["info"], seed=s, nr=nr, schon_vorbei=True)
            info = dict(a["info"], seed=s, nr=nr)
            return obs, info

    def step(self, action):
        a = self.node.frage(cmd="step", aktion=int(action), vorspulen=self.vorspulen)
        obs = self._antwort(a)
        info = dict(a["info"], teile=a["teile"], stunden=a["stunden"], grund=a["grund"])
        return obs, float(a["belohnung"]), bool(a["beendet"]), bool(a["abgeschnitten"]), info

    def step_regel(self):
        """Vergleichsarm: das normale Gehirn entscheidet an derselben Stelle (nicht Teil des Aktionsraums der Policy)."""
        a = self.node.frage(cmd="step", aktion="regel", vorspulen=self.vorspulen)
        obs = self._antwort(a)
        info = dict(a["info"], teile=a["teile"], stunden=a["stunden"], grund=a["grund"])
        return obs, float(a["belohnung"]), bool(a["beendet"]), bool(a["abgeschnitten"]), info

    def action_masks(self):
        return self._maske.copy()

    def letzte_rohe_beobachtung(self):
        return None if self._letzte_roh is None else self._letzte_roh.copy()

    def close(self):
        self.node.schliessen()
