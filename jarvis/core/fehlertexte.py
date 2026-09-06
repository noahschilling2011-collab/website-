"""Fehlermeldungen, die nichts ausplaudern - an EINER Stelle.

Warum es diese Datei gibt
-------------------------

Am 31.08.2026 sind in diesem Projekt an EINEM Tag fuenf Lecks derselben
Klasse aufgeflogen, in fuenf verschiedenen Dateien:

  * `core/kalender.py`      - httpx haengt die volle URL an seinen Fehler,
                              und die Kalender-Abo-Adresse IST das Geheimnis
  * `core/tools/memory_tools.py` - OSError haengt den vollen Pfad an
  * `api/routes.py`         - dieselbe Stelle noch einmal, nur ueber die
                              HTTP-Route statt ueber das Werkzeug
  * `core/tools/kalender_tools.py` - derselbe Kalenderfehler noch einmal,
                              nur ueber die Datei-Quelle statt ueber https
  * `core/tools/dispatch.py` - `display` bereinigt, `error` nicht

Jedes Mal war die Regel richtig formuliert und an EINER Stelle umgesetzt.
Jedes Mal wurde sie am Aufrufer repariert statt an der Ursache. Und jedes
Mal fand sie erst die naechste Pruefrunde.

Deshalb steht sie jetzt hier, einmal, und wird von einem projektweiten
Waechter durchgesetzt (`tests/test_fehlertexte.py`), der JEDES registrierte
Werkzeug durchprobiert - statt an jeder Einzelstelle zu warten, bis jemand
daran denkt.

Was durchsickern kann
---------------------

Nicht nur Pfade. Die Bibliotheken haengen ihren Kontext an:

  httpx      -> die volle URL, mit Token im Pfad oder in der Abfrage
  OSError    -> den absoluten Dateipfad
  sqlite3    -> Tabellen- und Spaltennamen
  json       -> ein Stueck des Eingabetextes, der aus dem Modell stammt

`ohne_geheimnis()` nimmt deshalb NICHTS aus dem Ausnahmetext mit. Der Typ
allein sagt einem Menschen genug, um weiterzusuchen; der Rest gehoert ins
Serverlog, wo er nicht an einen Modellanbieter geht.
"""

from __future__ import annotations

import logging

log = logging.getLogger("jarvis")


def ohne_geheimnis(exc: BaseException, was: str, hinweis: str = "") -> str:
    """Ein Satz ueber den Fehler, der garantiert nichts verraet.

    `was` ist die Handlung in Nutzersprache ("Der Kalender liess sich nicht
    lesen"), `hinweis` der optionale Rat ("Pruefe KALENDER_QUELLE in der
    .env"). Der Ausnahmetext selbst kommt NICHT vor - nur ihr Typ.

    Der volle Text geht ins Log. Das ist die Trennlinie: das Serverlog liest
    ein Mensch auf seiner eigenen Maschine, die Fehlermeldung liest ein
    Modell bei einem Anbieter.
    """
    log.warning("%s: %s: %s", was, type(exc).__name__, exc)
    teile = [f"{was.rstrip('.')} ({type(exc).__name__})."]
    if hinweis:
        teile.append(hinweis.rstrip() if hinweis.endswith(".") else hinweis + ".")
    teile.append("Der Grund steht im Serverlog, nicht hier.")
    return " ".join(teile)


def ist_verdaechtig(text: str, geheimnisse: list[str]) -> list[str]:
    """Welche der `geheimnisse` stehen in `text`? Fuer Waechter gedacht.

    Bewusst stumpf: Teilzeichenkette, ohne Normalisierung. Ein Waechter, der
    schlau ist, uebersieht den Fall, den er fangen sollte.
    """
    return [g for g in geheimnisse if g and g in (text or "")]
