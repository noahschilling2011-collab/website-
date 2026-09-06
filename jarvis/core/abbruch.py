"""Der Pruefpunkt vor jedem teuren Aufruf.

FIX-03 Schritt 3a. Vorher gab es zwei getrennte Halbloesungen: der Runner
prueste den Abbruch an der Schrittgrenze, und der Werkzeug-Loop prueste das
Budget mit einem Rueckgabewert. Beides zusammen liess zwei Luecken offen:

* Innerhalb eines Schritts wurde der Abbruch-Wunsch ueberhaupt nicht gesehen.
  Ein Schritt mit vielen Werkzeugrunden lief nach `cancel` munter weiter -
  jede Runde ein bezahlter Modellaufruf.
* Ein Rueckgabewert kann jemand vergessen auszuwerten. Genau das war vor der
  Zusammenfassung passiert: dort stand gar keine Pruefung, und wer waehrend
  des Abschlusszuges abbrach, bekam am Ende `done`.

Deshalb EINE Funktion, die beides prueft - Abbruch-Wunsch und die
Verbrauchsgrenzen - und die im Zweifel **wirft**. Eine Ausnahme kann man nicht
versehentlich ignorieren.
"""

from __future__ import annotations

from typing import Callable

from core.contracts import Task


class LaufBeendet(Exception):
    """Der Lauf soll hier aufhoeren - abgebrochen oder Budget aufgebraucht.

    `status` ist der Endzustand, den der Task bekommen soll: `"cancelled"`
    oder `"aborted_budget"`. `teiltext` traegt, was bis dahin zusammengekommen
    ist, damit ein Teilergebnis moeglich bleibt (0.5).
    """

    def __init__(self, grund: str, *, status: str, teiltext: str = "") -> None:
        super().__init__(grund)
        self.grund = grund
        self.status = status
        self.teiltext = teiltext


def baue_pruefpunkt(
    task: Task,
    *,
    abgebrochen: Callable[[], bool],
) -> Callable[[], None]:
    """Gibt die Funktion zurueck, die vor jedem teuren Aufruf steht.

    Der Abbruch-Wunsch geht vor: wer abbricht, will nicht die Meldung, dass
    das Budget auch noch aufgebraucht ist.

    Geprueft wird mit `nur_verbrauch=True`. `max_steps` und `max_depth` zaehlen
    den laufenden Schritt bereits mit; waehrend eines Schritts geprueft wuerden
    sie ihn toeten, bevor er etwas tut. Die beiden prueft der Runner weiterhin
    zwischen den Schritten, so wie 0.5 es verlangt.
    """

    def pruefpunkt() -> None:
        if abgebrochen():
            raise LaufBeendet("Vom Nutzer abgebrochen.", status="cancelled")
        verletzung = task.budget_verletzung(nur_verbrauch=True)
        if verletzung:
            raise LaufBeendet(verletzung, status="aborted_budget")

    return pruefpunkt
