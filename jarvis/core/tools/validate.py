"""Winziger JSON-Schema-Pruefer.

Genug fuer Tool-Parameter: `type`, `properties`, `required`, `enum`,
`minimum`/`maximum`, `items`. Kein Anspruch auf Vollstaendigkeit - und
bewusst keine neue Abhaengigkeit, der Stack ist festgelegt.

Der Zweck ist nicht Spezifikationstreue, sondern: ein Tool bekommt nie
Argumente, die es nicht erwartet.
"""

from __future__ import annotations

from typing import Any

TYPEN: dict[str, type | tuple[type, ...]] = {
    "object": dict,
    "array": list,
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "null": type(None),
}


def pruefe(schema: dict[str, Any], wert: Any, pfad: str = "") -> str | None:
    """Gibt die erste Verletzung als Klartext zurueck, oder None."""
    stelle = pfad or "Argumente"

    erwartet = schema.get("type")
    if erwartet:
        typ = TYPEN.get(erwartet)
        if typ is None:
            return None  # unbekannter Typ - nichts zu pruefen
        # bool ist in Python ein int; fuer JSON-Schema sind das zwei Typen.
        if erwartet in ("integer", "number") and isinstance(wert, bool):
            return f"{stelle}: erwartet {erwartet}, bekam boolean"
        if not isinstance(wert, typ):
            return f"{stelle}: erwartet {erwartet}, bekam {type(wert).__name__}"

    if "enum" in schema and wert not in schema["enum"]:
        return f"{stelle}: {wert!r} ist nicht in {schema['enum']}"

    if isinstance(wert, (int, float)) and not isinstance(wert, bool):
        if "minimum" in schema and wert < schema["minimum"]:
            return f"{stelle}: {wert} ist kleiner als {schema['minimum']}"
        if "maximum" in schema and wert > schema["maximum"]:
            return f"{stelle}: {wert} ist groesser als {schema['maximum']}"

    if isinstance(wert, dict):
        for pflicht in schema.get("required", []):
            if pflicht not in wert:
                return f"{stelle}: Pflichtfeld {pflicht!r} fehlt"
        eigenschaften = schema.get("properties") or {}
        for schluessel, unterwert in wert.items():
            unterschema = eigenschaften.get(schluessel)
            if unterschema is None:
                if schema.get("additionalProperties") is False:
                    return f"{stelle}: unbekanntes Feld {schluessel!r}"
                continue
            fehler = pruefe(unterschema, unterwert, f"{stelle}.{schluessel}")
            if fehler:
                return fehler

    if isinstance(wert, list) and isinstance(schema.get("items"), dict):
        for i, eintrag in enumerate(wert):
            fehler = pruefe(schema["items"], eintrag, f"{stelle}[{i}]")
            if fehler:
                return fehler

    return None
