"""Kein Geheimnis in einer Fehlermeldung - fuer JEDES Werkzeug, nicht je Datei.

Am 31.08.2026 sind an EINEM Tag fuenf Lecks derselben Klasse aufgeflogen, in
fuenf Dateien: core/kalender.py (httpx haengt die volle Abo-URL an),
core/tools/memory_tools.py (OSError haengt den Vault-Pfad an), api/routes.py
(dieselbe Stelle noch einmal, nur ueber die HTTP-Route), kalender_tools.py
(derselbe Kalenderfehler, nur ueber die Datei-Quelle statt https) und
dispatch.py (`display` bereinigt, `error` nicht).

Jedes Mal war die Regel richtig formuliert und an EINER Stelle umgesetzt.
Jedes Mal wurde am Aufrufer repariert statt an der Ursache. Und jeder
vorhandene Waechter sass ebenfalls an einer Einzelstelle - der fuer die
Datei-Werkzeuge prueft bis heute nur `display`, nicht `error`, und waere mit
dem Leck gruen gewesen.

Dieser Test sitzt deshalb NICHT an einer Stelle. Er geht ueber alles, was in
der Registry steht, und ueber beide Felder. Ein neues Werkzeug ist damit
automatisch erfasst, ohne dass jemand daran denken muss.
"""

from __future__ import annotations

import inspect
from pathlib import Path

import pytest

import core.tools  # noqa: F401 - registriert alle Werkzeuge
from core.contracts import ToolResult
from core.fehlertexte import ist_verdaechtig, ohne_geheimnis
from core.tools import registry
from tests.conftest import run

# Was in keiner Meldung stehen darf. Erkennbar erfunden, damit ein Treffer
# eindeutig ist und nicht zufaellig aus echtem Text stammt.
GEHEIM_PFAD = "/home/noah/GEHEIMER-ORDNER-xyz/vault"
GEHEIM_URL = "https://calendar.google.com/calendar/ical/GEHEIM-TOKEN-xyz/basic.ics"
GEHEIMNISSE = [GEHEIM_PFAD, "GEHEIMER-ORDNER-xyz", "GEHEIM-TOKEN-xyz",
               "GEHEIM-TOKEN", "calendar.google.com"]


def test_ohne_geheimnis_nimmt_nichts_aus_dem_ausnahmetext_mit():
    """Die Grundfunktion selbst. Wenn die leckt, leckt alles darunter."""
    for exc in (
        OSError(2, "No such file or directory", GEHEIM_PFAD),
        FileNotFoundError(f"[Errno 2] No such file: '{GEHEIM_PFAD}'"),
        RuntimeError(f"Client error '404' for url '{GEHEIM_URL}'"),
        ValueError(GEHEIM_URL),
    ):
        satz = ohne_geheimnis(exc, "Etwas ging schief", "Pruefe die .env")
        assert ist_verdaechtig(satz, GEHEIMNISSE) == [], f"{exc!r} -> {satz}"
        # Und die Meldung muss trotzdem etwas taugen.
        assert type(exc).__name__ in satz, satz
        assert "Serverlog" in satz, satz


def test_der_typ_steht_drin_sonst_ist_die_meldung_wertlos():
    """Gegenprobe: eine Meldung, die NUR schweigt, hilft niemandem beim
    Suchen. Ohne diesen Test waere `return ''` eine gueltige Loesung."""
    satz = ohne_geheimnis(PermissionError("egal"), "Der Vault ist zu")
    assert "PermissionError" in satz
    assert "Der Vault ist zu" in satz


async def _ja(*a, **k) -> bool:
    """Die Bestaetigung ist eine KORUTINE - `lambda: True` wird awaited und
    fliegt mit TypeError. Bestaetigungspflichtige Werkzeuge kaemen sonst gar
    nicht bis zum Auffangzweig, den dieser Test pruefen will."""
    return True


def _leckt(ergebnis: ToolResult) -> list[str]:
    """Beide Felder, nicht nur display. Genau daran ist der alte Waechter
    fuer die Datei-Werkzeuge gescheitert."""
    treffer = []
    for feld in ("display", "error"):
        wert = getattr(ergebnis, feld, None)
        for g in ist_verdaechtig(str(wert or ""), GEHEIMNISSE):
            treffer.append(f"{feld}: {g}")
    return treffer


@pytest.mark.parametrize("werkzeug", sorted(registry.all_tools(), key=lambda t: t.name),
                         ids=lambda t: t.name)
def test_kein_werkzeug_gibt_ein_geheimnis_in_seiner_fehlermeldung_aus(werkzeug, monkeypatch):
    """Jedes registrierte Werkzeug, mit einer Ausnahme, die ein Geheimnis
    traegt - genau so, wie httpx und OSError es in freier Wildbahn tun.

    Der Weg fuehrt ueber `run_tool`, nicht direkt ueber `execute`: dort sitzt
    die Engstelle, und der Auffangzweig dort war selbst eine der fuenf
    Lecksstellen.
    """
    from core.contracts import Permission
    from core.tools.dispatch import run_tool

    # Das Werkzeug soll fliegen, und zwar mit einer Ausnahme, die ein
    # Geheimnis mitbringt. Wo genau es fliegt, ist egal - der Auffangzweig
    # im Dispatcher muss jede erwischen.
    def platzt(*a, **k):
        raise OSError(2, "No such file or directory", GEHEIM_PFAD)

    monkeypatch.setattr(werkzeug, "execute", platzt, raising=False)

    # Argumente aus dem Schema raten, damit die Signaturpruefung nicht schon
    # vorher abbricht. Pflichtfelder bekommen einen harmlosen Wert.
    schema = getattr(werkzeug, "parameters", {}) or {}
    noetig = schema.get("required") or []
    eigenschaften = schema.get("properties") or {}
    argumente = {}
    for feld in noetig:
        typ = (eigenschaften.get(feld) or {}).get("type", "string")
        argumente[feld] = {"string": "x", "integer": 1, "number": 1.0,
                           "boolean": True, "array": [], "object": {}}.get(typ, "x")

    ergebnis = run(run_tool(werkzeug.name, argumente,
                            max_permission=Permission.SENSITIVE,
                            bestaetigung=_ja))
    assert _leckt(ergebnis) == [], (
        f"{werkzeug.name} verraet ein Geheimnis: {_leckt(ergebnis)}\n"
        f"  display={ergebnis.display!r}\n  error={ergebnis.error!r}")


def test_der_waechter_wuerde_ein_leck_ueberhaupt_bemerken():
    """Ein Waechter, der nichts fangen kann, ist der gefaehrlichste Test von
    allen - heute sind in diesem Projekt zwei davon aufgeflogen, einer weil
    er eine nicht existierende Variable abfragte, einer weil er still
    uebersprang.

    Also die Gegenprobe: ein ToolResult, das leckt, MUSS auffallen."""
    schlecht = ToolResult(ok=False, error=f"kaputt: {GEHEIM_PFAD}",
                          display="alles gut")
    assert _leckt(schlecht) == [f"error: {GEHEIM_PFAD}", "error: GEHEIMER-ORDNER-xyz"], \
        _leckt(schlecht)

    nur_display = ToolResult(ok=False, error="sauber",
                             display=f"kaputt: {GEHEIM_URL}")
    assert _leckt(nur_display), "ein Leck in display muss ebenso auffallen"


def test_die_regel_steht_nur_noch_an_einer_stelle():
    """Der eigentliche Punkt. Wer kuenftig `f"...: {exc}"` in ein error- oder
    display-Feld schreibt, hat die Lehre nicht verstanden.

    Der Test verbietet das Muster nicht ueberall - im Log ist es richtig und
    erwuenscht. Er verbietet es dort, wo der Text nach draussen geht.
    """
    import re

    wurzel = Path(__file__).resolve().parent.parent
    muster = re.compile(
        r"(?:error|display|detail)\s*=\s*f?[\"'][^\"']*\{(?:exc|e|err|fehler)\}")
    treffer = []
    for pfad in sorted(wurzel.glob("core/**/*.py")) + sorted(wurzel.glob("api/*.py")):
        text = pfad.read_text(encoding="utf-8")
        # Docstrings ZEILENTREU leeren, nicht loeschen: ein `re.sub` auf ""
        # verschiebt jede Zeilennummer danach, und der Waechter schickt den
        # naechsten Leser an die falsche Stelle. Genau diesen Fehler hatte
        # der `--dim`-Waechter in tests/test_designsystem.py schon einmal.
        ohne = re.sub(r'"""(?:.|\n)*?"""',
                      lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
        for nr, zeile in enumerate(ohne.splitlines(), 1):
            if zeile.lstrip().startswith("#"):
                continue
            if muster.search(zeile):
                treffer.append(f"{pfad.relative_to(wurzel)}:{nr}: {zeile.strip()[:80]}")
    assert treffer == [], (
        "Ausnahmetext direkt in einer nach aussen sichtbaren Meldung - "
        "nimm core.fehlertexte.ohne_geheimnis:\n  " + "\n  ".join(treffer))
