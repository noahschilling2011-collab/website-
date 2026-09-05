"""Tool-Registry.

Ein `@register`-Dekorator, eine Namensliste, und JSON-Schemas fuer das Modell.
Mehr braucht es nicht.

Registriert wird die **Instanz**, nicht die Klasse: ein Tool ist zustandslos
und wird pro Aufruf nicht neu gebaut.
"""

from __future__ import annotations

import re
from typing import Iterable, TypeVar

from core.contracts import Permission, Tool

NAME_MUSTER = re.compile(r"^[a-z][a-z0-9_]{2,47}$")

_REGISTRY: dict[str, Tool] = {}

T = TypeVar("T", bound=type[Tool])


def register(tool_cls: T) -> T:
    """Nimmt eine Tool-Klasse in die Registry auf.

    Prueft dabei, was das Modell spaeter zu sehen bekommt. Ein Tool mit
    kaputtem Schema faellt hier auf und nicht erst im Gespraech.
    """
    tool = tool_cls()

    name = getattr(tool, "name", "")
    if not NAME_MUSTER.match(name or ""):
        raise ValueError(
            f"Tool-Name {name!r} passt nicht auf {NAME_MUSTER.pattern} - "
            "der Name geht so an die Modell-API."
        )
    if name in _REGISTRY:
        raise ValueError(f"Tool {name!r} ist schon registriert.")
    if not getattr(tool, "description", "").strip():
        raise ValueError(f"Tool {name!r} hat keine Beschreibung. Das Modell "
                         "liest nur die.")
    schema = getattr(tool, "parameters", None)
    if not isinstance(schema, dict) or schema.get("type") != "object":
        raise ValueError(f"Tool {name!r}: parameters muss ein JSON-Schema mit "
                         "type='object' sein.")
    if not isinstance(getattr(tool, "permission", None), Permission):
        raise ValueError(f"Tool {name!r} hat keine Permission aus dem Vertrag.")
    # 0.4.6 - ohne Ausnahme.
    if tool.permission >= Permission.EXTERNAL and not tool.requires_confirmation:
        raise ValueError(
            f"Tool {name!r} hat Permission {tool.permission.name}, aber "
            "requires_confirmation=False. Alles ab EXTERNAL wird bestaetigt."
        )

    _REGISTRY[name] = tool
    return tool_cls


def get(name: str) -> Tool | None:
    return _REGISTRY.get(name)


def all_tools() -> list[Tool]:
    return sorted(_REGISTRY.values(), key=lambda t: t.name)


def names() -> list[str]:
    return sorted(_REGISTRY)


def schemas_for(
    erlaubt: Iterable[str] | None = None,
    max_permission: Permission = Permission.SENSITIVE,
) -> list[dict]:
    """Die Tool-Definitionen fuer die Modell-API.

    Ein Tool ueber `max_permission` wird gar nicht erst angeboten - das Modell
    soll nicht vorschlagen, was der Dispatcher danach ablehnt.
    """
    auswahl = set(erlaubt) if erlaubt is not None else None
    return [
        {
            "name": tool.name,
            "description": tool.description,
            "input_schema": tool.parameters,
        }
        for tool in all_tools()
        if (auswahl is None or tool.name in auswahl)
        and tool.permission <= max_permission
    ]


# --- nur fuer Tests -------------------------------------------------------


def _snapshot() -> dict[str, Tool]:
    return dict(_REGISTRY)


def _restore(zustand: dict[str, Tool]) -> None:
    _REGISTRY.clear()
    _REGISTRY.update(zustand)
