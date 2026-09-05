"""Die Bestätigungsregel aus `docs/contracts.md` §0.4.6, als Test.

Die Regel lautet seit dem 25.08.2026: Bestätigung ist Pflicht ab EXTERNAL (3)
aufwärts, plus bei jeder löschenden oder überschreibenden lokalen Operation.
Rein anhängende lokale Schreibvorgänge brauchen keine.

Vorher stand in der Spec "alles, was schreibt, braucht eine Bestätigung" — und
im selben Dokument war `Permission.LOCAL` ausdrücklich für Memory-Einträge
definiert. Der Widerspruch fiel erst in einem Audit auf. Damit er nicht
zurückkommt, hängt er jetzt an einem Test statt an einem Absatz.
"""

from __future__ import annotations

import inspect

import pytest

import api.app  # noqa: F401  - loest die Registrierung aller Werkzeuge aus
from core.contracts import Permission
from core.tools import registry

# Wortmarken, an denen ein loeschender oder ueberschreibender Zugriff im
# Quelltext eines Werkzeugs zu erkennen ist.
ZERSTOEREND = ("DELETE FROM", "delete_fact", "update_fact", "UPDATE ", "os.remove",
               "unlink(", "shutil.rmtree")


def werkzeuge():
    return sorted(registry.all_tools(), key=lambda t: t.name)


def test_es_gibt_ueberhaupt_werkzeuge():
    """Sonst waeren die Regeltests unten leer und trotzdem gruen."""
    assert len(werkzeuge()) >= 5


@pytest.mark.parametrize("tool", werkzeuge(), ids=lambda t: t.name)
def test_ab_external_ist_bestaetigung_pflicht(tool):
    if tool.permission >= Permission.EXTERNAL:
        assert tool.requires_confirmation is True, (
            f"{tool.name} hat Permission {tool.permission.name}, aber keine Bestaetigung. "
            f"Vertrag 0.4.6: ab EXTERNAL ist sie Pflicht."
        )


@pytest.mark.parametrize("tool", werkzeuge(), ids=lambda t: t.name)
def test_loeschende_lokale_operationen_brauchen_bestaetigung(tool):
    quelle = inspect.getsource(type(tool))
    treffer = [w for w in ZERSTOEREND if w in quelle]
    if treffer:
        assert tool.requires_confirmation is True, (
            f"{tool.name} loescht oder ueberschreibt ({', '.join(treffer)}), "
            f"aber fragt nicht nach. Vertrag 0.4.6."
        )


def test_remember_bleibt_ohne_rueckfrage():
    """Die Stelle, an der die alte Spec falsch war - ausdruecklich festgehalten."""
    remember = registry.get("remember")
    assert remember is not None
    assert remember.permission is Permission.LOCAL
    assert remember.requires_confirmation is False, (
        "remember haengt nur an - eine Rueckfrage pro gemerktem Satz macht das "
        "Gedaechtnis unbenutzbar."
    )


def test_die_regel_greift_ueberhaupt():
    """Gegenprobe: mindestens ein Werkzeug faellt wirklich unter die Regel."""
    betroffen = [t.name for t in werkzeuge() if t.permission >= Permission.EXTERNAL]
    assert betroffen, "Kein Werkzeug ab EXTERNAL - der Regeltest liefe ins Leere."
