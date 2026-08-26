"""Die Werkzeuge, die ohne Konto und ohne Netz funktionieren."""

from __future__ import annotations

import ast
import math
import operator
import time
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from core.contracts import Permission, Tool, ToolResult
from core.tools.registry import register


@register
class Clock(Tool):
    name = "clock"
    description = (
        "Gibt das aktuelle Datum und die aktuelle Uhrzeit zurueck. "
        "Benutze das immer, wenn nach der Zeit, dem Datum oder dem Wochentag "
        "gefragt wird - rate die Zeit nie."
    )
    parameters = {
        "type": "object",
        "properties": {
            "timezone": {
                "type": "string",
                "description": (
                    "IANA-Zeitzone wie 'Europe/Berlin'. Weglassen fuer die "
                    "lokale Zeit des Rechners."
                ),
            }
        },
        "additionalProperties": False,
    }
    permission = Permission.INFO

    async def execute(self, timezone: str | None = None) -> ToolResult:
        if timezone:
            try:
                jetzt = datetime.now(ZoneInfo(timezone))
            except (ZoneInfoNotFoundError, ValueError):
                return ToolResult(
                    ok=False,
                    error=f"Unbekannte Zeitzone {timezone!r}.",
                    display=f"Zeitzone {timezone!r} gibt es nicht.",
                )
        else:
            jetzt = datetime.now().astimezone()

        wochentage = [
            "Montag", "Dienstag", "Mittwoch", "Donnerstag",
            "Freitag", "Samstag", "Sonntag",
        ]
        text = (
            f"{wochentage[jetzt.weekday()]}, {jetzt.strftime('%d.%m.%Y, %H:%M:%S')} "
            f"({jetzt.tzname()})"
        )
        return ToolResult(
            ok=True,
            data={"iso": jetzt.isoformat(), "timezone": str(jetzt.tzinfo)},
            display=text,
        )


# Nur diese Operatoren. Was nicht hier steht, geht nicht - das ist der ganze
# Punkt gegenueber eval().
OPERATOREN = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.USub: operator.neg,
    ast.UAdd: operator.pos,
}

FUNKTIONEN = {
    "abs": abs, "round": round, "min": min, "max": max, "sum": sum,
    "int": int, "float": float,
}

KONSTANTEN = {"pi": 3.141592653589793, "e": 2.718281828459045}

# Gegen 9**9**9: das blockiert den Prozess, bevor irgendein Timeout greift.
MAX_EXPONENT = 1000
MAX_BASIS = 10**15

# BUGS-01 Fund 14. Die beiden Grenzen oben decken nur `**` ab. Eine Kette aus
# Multiplikationen kam an ihnen vorbei, und `rechne()` laeuft synchron im
# Event-Loop - der ganze Server steht solange still. Gemessen:
#
#     " * ".join(["(10**15)**1000"] * 400)   ->  6797 Zeichen  ->  34,6 s
#
# Deshalb eine Grenze fuer JEDES Zwischenergebnis, nicht nur fuer Potenzen.
# Sie liegt da, wo Python selbst aufhoert: ab 4300 Stellen weigert es sich,
# aus einer Zahl einen String zu machen. Ein Ergebnis, das man nicht
# hinschreiben kann, ist fuer einen Rechner ohnehin keins - genau daran ist
# `(10**15)**1000` mit einem ValueError aus `execute` herausgeflogen.
MAX_STELLEN = 4300
MAX_BITS = int(MAX_STELLEN * math.log2(10))


class UnsichererAusdruck(ValueError):
    pass


def _im_rahmen(wert):
    """Weist ein Zwischenergebnis ab, das zu gross zum Hinschreiben ist.

    Steht nur an `BinOp`. Vorzeichen machen eine Zahl nicht groesser, und von
    den erlaubten Funktionen kann keine eine Zahl wachsen lassen - `int` und
    `float` sind durch den Wertebereich von float gedeckelt, `sum` braucht
    eine Liste und die ist ohnehin verboten. Ein Deckel an einer Stelle, die
    nie ausloest, laesst sich nicht pruefen; deshalb steht er nicht dort.
    `test_die_erlaubten_funktionen_koennen_keine_zahl_wachsen_lassen` haelt
    das fest, falls jemand die Liste erweitert.
    """
    if isinstance(wert, int) and not isinstance(wert, bool):
        if wert.bit_length() > MAX_BITS:
            raise UnsichererAusdruck(
                f"Zwischenergebnis zu gross - mehr als {MAX_STELLEN} Stellen."
            )
    return wert


def rechne(ausdruck: str) -> float | int:
    """Wertet einen arithmetischen Ausdruck aus - ohne eval, ohne exec.

    Der Baum wird geprueft, nicht der Text: eine Zeichenkette zu filtern ist
    ein Wettlauf, den man verliert.
    """
    try:
        baum = ast.parse(ausdruck, mode="eval")
    except SyntaxError as exc:
        raise UnsichererAusdruck(f"Kein gueltiger Ausdruck: {exc.msg}") from exc

    def aus(knoten: ast.AST):
        if isinstance(knoten, ast.Expression):
            return aus(knoten.body)
        if isinstance(knoten, ast.Constant):
            if isinstance(knoten.value, bool) or not isinstance(
                knoten.value, (int, float)
            ):
                raise UnsichererAusdruck("Nur Zahlen sind erlaubt.")
            return knoten.value
        if isinstance(knoten, ast.Name):
            if knoten.id in KONSTANTEN:
                return KONSTANTEN[knoten.id]
            raise UnsichererAusdruck(f"Unbekannter Name {knoten.id!r}.")
        if isinstance(knoten, ast.BinOp):
            funktion = OPERATOREN.get(type(knoten.op))
            if funktion is None:
                raise UnsichererAusdruck(
                    f"Operator {type(knoten.op).__name__} ist nicht erlaubt."
                )
            links, rechts = aus(knoten.left), aus(knoten.right)
            if isinstance(knoten.op, ast.Pow):
                if abs(rechts) > MAX_EXPONENT or abs(links) > MAX_BASIS:
                    raise UnsichererAusdruck("Potenz zu gross.")
            if isinstance(knoten.op, (ast.Div, ast.FloorDiv, ast.Mod)) and rechts == 0:
                raise UnsichererAusdruck("Division durch null.")
            return _im_rahmen(funktion(links, rechts))
        if isinstance(knoten, ast.UnaryOp):
            funktion = OPERATOREN.get(type(knoten.op))
            if funktion is None:
                raise UnsichererAusdruck("Vorzeichen nicht erlaubt.")
            return funktion(aus(knoten.operand))
        if isinstance(knoten, ast.Call):
            if not isinstance(knoten.func, ast.Name) or knoten.func.id not in FUNKTIONEN:
                raise UnsichererAusdruck("Diese Funktion ist nicht erlaubt.")
            if knoten.keywords:
                raise UnsichererAusdruck("Keine Schluesselwort-Argumente.")
            return FUNKTIONEN[knoten.func.id](*[aus(a) for a in knoten.args])
        raise UnsichererAusdruck(
            f"{type(knoten).__name__} ist in einem Rechenausdruck nicht erlaubt."
        )

    return aus(baum)


@register
class Calculator(Tool):
    name = "calculator"
    description = (
        "Rechnet einen arithmetischen Ausdruck aus. Benutze das fuer JEDE "
        "Rechnung - auch fuer einfache. Rechne nie im Kopf. "
        "Erlaubt sind + - * / // % **, Klammern, pi, e und die Funktionen "
        "abs, round, min, max, sum, int, float. "
        "Prozent schreibst du als Multiplikation: 17 % von 4380 ist '4380 * 0.17'."
    )
    parameters = {
        "type": "object",
        "properties": {
            "expression": {
                "type": "string",
                "description": "Der Ausdruck, z. B. '4380 * 0.17'.",
            }
        },
        "required": ["expression"],
        "additionalProperties": False,
    }
    permission = Permission.INFO

    async def execute(self, expression: str) -> ToolResult:
        begonnen = time.monotonic()
        try:
            ergebnis = rechne(expression)
        except UnsichererAusdruck as exc:
            return ToolResult(
                ok=False,
                error=str(exc),
                display=f"{expression} → {exc}",
                duration_ms=int((time.monotonic() - begonnen) * 1000),
            )
        except (ArithmeticError, TypeError, ValueError) as exc:
            return ToolResult(
                ok=False,
                error=f"Rechenfehler: {exc}",
                display=f"{expression} → Rechenfehler",
                duration_ms=int((time.monotonic() - begonnen) * 1000),
            )
        return ToolResult(
            ok=True,
            data={"expression": expression, "result": ergebnis},
            display=f"{expression} = {ergebnis}",
            duration_ms=int((time.monotonic() - begonnen) * 1000),
        )
