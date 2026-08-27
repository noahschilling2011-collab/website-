"""Messstrecke: waehlt JARVIS die richtigen Werkzeuge? (FIX-10 Schritt A)

    python -m scripts.plantest --trocken          # ohne Netz, ohne Kosten
    python -m scripts.plantest                    # echte Modellaufrufe
    python -m scripts.plantest --laeufe 3         # dreimal, fuer die Streuung

**Warum das nicht in `pytest` gehoert.** Es ruft echte Modelle.
`tests/test_no_network.py` wuerde es zu Recht erschlagen, und `CLAUDE.md`
sagt, dass `pytest` niemals einen echten Modellaufruf macht. Eigenes Skript,
eigener Aufruf, eigener Deckel.

------------------------------------------------------------------------
WAS HIER GEMESSEN WIRD - und was nicht
------------------------------------------------------------------------

Der Auftrag FIX-10 nimmt an, der Planer waehle die Werkzeuge. **Tut er
nicht.** `core/planner.erstelle_plan` liefert `Step`s mit einer Beschreibung
und einem optionalen Agenten; welche Werkzeuge laufen, entscheidet erst das
Modell in `core/tools/loop.run_tool_loop`, Zug fuer Zug, mit den Ergebnissen
der vorigen Werkzeuge in der Hand.

Daraus folgen zwei Wege, und beide haben einen Haken:

  (a) Den echten Schleifenpfad fahren und mitschreiben, welche Werkzeuge
      angefordert werden. Misst das Richtige - fuehrt aber Werkzeuge aus
      (Geld, Netz, `send_email`), oder man schiebt erfundene Ergebnisse
      unter, und dann misst man die Erfindung mit.

  (b) Das Modell nach seinem Werkzeugplan FRAGEN, ohne etwas auszufuehren.
      Genau das macht TaskBench: es bewertet den vorhergesagten Aufrufgraphen,
      nicht den Lauf. Ein Aufruf je Fall, keine Nebenwirkungen, keine
      erfundenen Zwischenergebnisse.

Gewaehlt ist **(b)**. Damit steht auch dabei, was die Zahlen NICHT sagen:
sie messen den *ausgesprochenen Plan*, nicht das Laufzeitverhalten. Ein
Modell kann gut planen und im Lauf trotzdem danebengreifen.

Damit die Messung dem echten System entspricht, kommen die Werkzeugtexte
**aus der Registry**, nicht aus einer Kopie. Wer in Schritt B eine
Beschreibung umschreibt, misst danach genau diese Aenderung.

------------------------------------------------------------------------
REPRODUZIERBARKEIT
------------------------------------------------------------------------

Der Auftrag verlangt Temperatur 0. **Das geht nicht**, ohne den
Anbietervertrag zu aendern: `LLMProvider.complete` kennt keinen
Temperaturparameter, und `core/llm.py` sagt im Modulkopf ausdruecklich, dass
`temperature`, `top_p`, `top_k` bewusst nicht gesendet werden - auf den
aktuellen Opus-Modellen ist jedes davon ein 400.

Die Reproduzierbarkeit wird deshalb **gemessen statt erzwungen**: `--laeufe 3`
faehrt den Satz dreimal und meldet die Spanne je Zahl. Bleibt sie unter 0,05,
ist die Messstrecke brauchbar. Bleibt sie es nicht, ist das der Befund - und
dann ist zuerst die Messung zu reparieren, nicht der Planer.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from core.config import Settings, get_settings
from core.llm import LLMMessage, build_provider
from core.tools import registry

WURZEL = Path(__file__).resolve().parent.parent
FAELLE = WURZEL / "tests" / "plandaten" / "faelle.json"
VERLAUF = WURZEL / "tests" / "plandaten" / "verlauf.jsonl"

GRUEN, ROT, GELB, GRAU, AUS = "\033[32m", "\033[31m", "\033[33m", "\033[90m", "\033[0m"


# --- Die Metrik -----------------------------------------------------------


def f1(erwartet: set, bekommen: set) -> float:
    """F1 ueber zwei Mengen. Beide leer = 1.0 (richtig erkannt: nichts noetig).

    Wortwoertlich aus dem Auftrag uebernommen. Der Sonderfall in Zeile 1 ist
    der wichtige: ein Fall, der KEIN Werkzeug braucht, ist richtig geloest,
    wenn auch keins vorhergesagt wurde - und nicht etwa unbewertbar.
    """
    if not erwartet and not bekommen:
        return 1.0
    if not erwartet or not bekommen:
        return 0.0
    treffer = len(erwartet & bekommen)
    p = treffer / len(bekommen)
    r = treffer / len(erwartet)
    return 0.0 if p + r == 0 else 2 * p * r / (p + r)


def mittel(werte: list[float]) -> float:
    return sum(werte) / len(werte) if werte else 0.0


# --- Der Prompt -----------------------------------------------------------


SYSTEM = """Du planst den Werkzeugeinsatz von JARVIS.

Zu einem Auftrag sagst du, WELCHE der unten aufgefuehrten Werkzeuge noetig
sind und welches vor welchem laufen muss.

Regeln:
- Nenne nur Werkzeuge, die WIRKLICH gebraucht werden. Weniger ist richtig.
- Braucht der Auftrag gar kein Werkzeug - weil er sich aus allgemeinem Wissen
  beantworten laesst oder weil JARVIS ihn mit diesen Werkzeugen gar nicht
  erfuellen kann - dann ist die richtige Antwort eine LEERE Liste.
- Eine Kante [A, B] bedeutet: A muss vor B laufen, weil B die AUSGABE von A
  als Eingabe braucht. Keine Kante fuer blosse Reihenfolgevorlieben.

DIE WERKZEUGE:
<<WERKZEUGE>>

Antworte AUSSCHLIESSLICH mit JSON in genau dieser Form, ohne Text davor oder
danach, ohne Markdown-Codeblock:

{"werkzeuge": ["name"], "kanten": [["name_a", "name_b"]]}"""


def werkzeugtext() -> tuple[str, dict]:
    """Die Werkzeugtexte, wie sie das echte System sendet.

    Aus der Registry, nicht aus einer Kopie: nur so misst Schritt B wirklich
    die umgeschriebenen Beschreibungen.
    """
    alle = sorted(registry.all_tools(), key=lambda t: t.name)
    zeilen = [f"- {t.name}: {t.description}" for t in alle]
    text = "\n".join(zeilen)
    kennzahl = {
        "anzahl": len(alle),
        "zeichen": sum(len(t.description) for t in alle),
        "token_geschaetzt": round(sum(len(t.description) for t in alle) / 4),
        "kuerzeste": min(len(t.description) for t in alle),
        "laengste": max(len(t.description) for t in alle),
    }
    return text, kennzahl


def json_aus_text(text: str) -> str:
    """Dasselbe Vorgehen wie in `core/planner._json_aus_text`.

    Modelle packen JSON gern in einen Markdown-Block. Das ist kein Grund, den
    Versuch wegzuwerfen - aber es wird gesucht und nicht geraten.
    """
    text = text.strip()
    block = re.search(r"```(?:json)?\s*(.+?)```", text, re.DOTALL)
    if block:
        text = block.group(1).strip()
    start, ende = text.find("{"), text.rfind("}")
    return text[start:ende + 1] if start != -1 and ende > start else text


# --- Deckel ---------------------------------------------------------------


class DeckelGerissen(RuntimeError):
    pass


class Deckel:
    """Harte Grenze mit Abbruch. `CLAUDE.md` Regel 6.

    **Token, nicht Euro.** Mit einem kostenlosen Anbieter stehen keine Preise
    in der `.env`, und `Settings.cost_eur` gibt dann korrekterweise 0.0
    zurueck - ein Eurodeckel wuerde nie greifen und waere eine Attrappe. Der
    Eurodeckel bleibt zusaetzlich, greift aber nur mit eingetragenen Preisen.
    """

    def __init__(self, token: int, eur: float, einstellungen: Settings) -> None:
        self.max_token = token
        self.max_eur = eur
        self.einstellungen = einstellungen
        self.token = 0
        self.eur = 0.0
        self.aufrufe = 0

    def buche(self, rein: int, raus: int) -> None:
        self.aufrufe += 1
        self.token += rein + raus
        self.eur += self.einstellungen.cost_eur(rein, raus)
        if self.token > self.max_token:
            raise DeckelGerissen(
                f"Tokendeckel gerissen: {self.token} von hoechstens "
                f"{self.max_token} nach {self.aufrufe} Aufrufen. Abbruch."
            )
        if self.einstellungen.prices_configured and self.eur > self.max_eur:
            raise DeckelGerissen(
                f"Kostendeckel gerissen: {self.eur:.4f} EUR von hoechstens "
                f"{self.max_eur:.4f} nach {self.aufrufe} Aufrufen. Abbruch."
            )


# --- Ein Lauf -------------------------------------------------------------


async def ein_lauf(provider, faelle: list[dict], system: str, deckel: Deckel) -> dict:
    knoten: list[float] = []
    kanten: list[float] = []
    leer_richtig = 0
    leer_gesamt = 0
    einzeln: list[dict] = []
    modell = ""

    for fall in faelle:
        erwartet_w = set(fall["werkzeuge"])
        erwartet_k = {tuple(k) for k in fall.get("kanten", [])}

        antwort = await provider.complete(
            [LLMMessage("user", fall["auftrag"])], system=system
        )
        modell = antwort.model
        deckel.buche(antwort.usage.in_tokens, antwort.usage.out_tokens)

        try:
            roh = json.loads(json_aus_text(antwort.text))
            bekommen_w = {str(x) for x in roh.get("werkzeuge", [])}
            bekommen_k = {
                (str(k[0]), str(k[1]))
                for k in roh.get("kanten", [])
                if isinstance(k, (list, tuple)) and len(k) == 2
            }
            lesbar = True
        except (json.JSONDecodeError, TypeError, AttributeError):
            # Eine unlesbare Antwort ist ein Fehlschlag, kein uebersprungener
            # Fall. Wer sie ueberspringt, schoent den Durchschnitt.
            bekommen_w, bekommen_k, lesbar = set(), set(), False

        n = f1(erwartet_w, bekommen_w)
        e = f1(erwartet_k, bekommen_k)
        knoten.append(n)
        kanten.append(e)

        if not erwartet_w:
            leer_gesamt += 1
            if not bekommen_w:
                leer_richtig += 1

        einzeln.append({
            "id": fall["id"],
            "node_f1": round(n, 3),
            "edge_f1": round(e, 3),
            "erwartet": sorted(erwartet_w),
            "bekommen": sorted(bekommen_w),
            "lesbar": lesbar,
        })

    return {
        "modell": modell,
        "node_f1": round(mittel(knoten), 4),
        "edge_f1": round(mittel(kanten), 4),
        "leer_genauigkeit": round(leer_richtig / leer_gesamt, 4) if leer_gesamt else 0.0,
        "leer_richtig": leer_richtig,
        "leer_gesamt": leer_gesamt,
        "unlesbar": sum(1 for x in einzeln if not x["lesbar"]),
        "einzeln": einzeln,
    }


# --- Bericht --------------------------------------------------------------


def zeige(lauf: dict, nummer: int) -> None:
    print(f"\n{GRAU}--- Lauf {nummer} · Modell {lauf['modell']} ---{AUS}")
    for x in lauf["einzeln"]:
        ok = x["node_f1"] == 1.0 and x["edge_f1"] == 1.0
        farbe = GRUEN if ok else (GELB if x["node_f1"] > 0 else ROT)
        marke = "  " if ok else "!!"
        print(f"{farbe}{marke} {x['id']:16}{AUS} node {x['node_f1']:.2f}  "
              f"edge {x['edge_f1']:.2f}   erwartet {','.join(x['erwartet']) or '(keins)'}"
              f"   bekommen {','.join(x['bekommen']) or '(keins)'}")
    print(f"   node-F1 {lauf['node_f1']:.4f}   edge-F1 {lauf['edge_f1']:.4f}   "
          f"Leer {lauf['leer_genauigkeit']:.4f} ({lauf['leer_richtig']}/{lauf['leer_gesamt']})")
    if lauf["unlesbar"]:
        print(f"{ROT}   {lauf['unlesbar']} Antworten waren kein lesbares JSON "
              f"und zaehlen als Fehlschlag.{AUS}")


def spanne(werte: list[float]) -> float:
    return max(werte) - min(werte) if werte else 0.0


def main() -> int:
    p = argparse.ArgumentParser(description="Messstrecke fuer die Werkzeugwahl")
    p.add_argument("--laeufe", type=int, default=1,
                   help="Wie oft der ganze Satz laeuft. Fuer die Streuung: 3.")
    p.add_argument("--trocken", action="store_true",
                   help="FakeLLMProvider statt echtem Modell: kein Netz, keine Kosten. "
                        "Beweist die Mechanik, nicht die Planungsguete.")
    p.add_argument("--deckel-token", type=int, default=200_000,
                   help="Harte Obergrenze fuer Token ueber alle Laeufe. Abbruch.")
    p.add_argument("--deckel-eur", type=float, default=1.0,
                   help="Zusaetzlich, greift nur mit Preisen in der .env.")
    p.add_argument("--faelle", type=Path, default=FAELLE,
                   help="Andere Falldatei. Fuer Probelaeufe, nicht fuer die Abnahme.")
    p.add_argument("--kein-verlauf", action="store_true",
                   help="Nicht an verlauf.jsonl anhaengen (fuer Probelaeufe).")
    args = p.parse_args()

    if not args.faelle.is_file():
        print(f"{ROT}{args.faelle} fehlt.{AUS}")
        return 2
    faelle = json.loads(args.faelle.read_text(encoding="utf-8"))

    text, kennzahl = werkzeugtext()
    system = SYSTEM.replace("<<WERKZEUGE>>", text)
    einstellungen = get_settings()

    if args.trocken:
        from core.llm import FakeLLMProvider

        # Der Fake antwortet immer dasselbe. Das misst nichts ueber die
        # Planungsguete - nur, dass Datei, Metrik, Deckel und Verlauf
        # zusammenspielen. Genau dafuer ist er da.
        provider = FakeLLMProvider(replies=['{"werkzeuge": [], "kanten": []}'])
        print(f"{GELB}Trockenlauf: FakeLLMProvider. Die Zahlen sagen nichts "
              f"ueber die Planungsguete.{AUS}")
    else:
        if not einstellungen.llm_api_key:
            print(f"{ROT}Kein LLM_API_KEY in der .env. Ohne echtes Modell gibt es "
                  f"nichts zu messen.{AUS}")
            print(f"{GRAU}Fuer einen Mechanikbeweis ohne Kosten: "
                  f"python -m scripts.plantest --trocken{AUS}")
            return 2
        provider = build_provider(einstellungen)

    print(f"{GRAU}{len(faelle)} Faelle · {kennzahl['anzahl']} Werkzeuge · "
          f"{kennzahl['zeichen']} Zeichen Beschreibungstext "
          f"(rund {kennzahl['token_geschaetzt']} Token je Aufruf){AUS}")

    deckel = Deckel(args.deckel_token, args.deckel_eur, einstellungen)
    laeufe: list[dict] = []
    try:
        for i in range(1, args.laeufe + 1):
            lauf = asyncio.run(ein_lauf(provider, faelle, system, deckel))
            zeige(lauf, i)
            laeufe.append(lauf)
    except DeckelGerissen as ende:
        print(f"\n{ROT}{ende}{AUS}")
        return 3

    print(f"\n{GRAU}Verbrauch: {deckel.aufrufe} Aufrufe, {deckel.token} Token"
          + (f", {deckel.eur:.4f} EUR" if einstellungen.prices_configured
             else ", Kosten unbekannt (keine Preise in der .env)") + f"{AUS}")

    if len(laeufe) > 1:
        print(f"\n{GRAU}--- Streuung ueber {len(laeufe)} Laeufe ---{AUS}")
        for name in ("node_f1", "edge_f1", "leer_genauigkeit"):
            werte = [x[name] for x in laeufe]
            s = spanne(werte)
            farbe = GRUEN if s <= 0.05 else ROT
            print(f"{farbe}   {name:18} {' '.join(f'{w:.4f}' for w in werte)}"
                  f"   Spanne {s:.4f}{AUS}")
            if s > 0.05:
                print(f"{ROT}   Ueber 0,05: die Messung selbst ist unzuverlaessig "
                      f"und muss zuerst repariert werden.{AUS}")

    if not args.kein_verlauf:
        VERLAUF.parent.mkdir(parents=True, exist_ok=True)
        with VERLAUF.open("a", encoding="utf-8") as f:
            for i, lauf in enumerate(laeufe, 1):
                f.write(json.dumps({
                    "zeit": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "modell": lauf["modell"],
                    "anbieter": "fake" if args.trocken else einstellungen.llm_provider,
                    "lauf": i,
                    "faelle": len(faelle),
                    "node_f1": lauf["node_f1"],
                    "edge_f1": lauf["edge_f1"],
                    "leer_genauigkeit": lauf["leer_genauigkeit"],
                    "unlesbar": lauf["unlesbar"],
                    "werkzeuge": kennzahl,
                }, ensure_ascii=False) + "\n")
        print(f"{GRAU}Angehaengt an {VERLAUF}{AUS}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
