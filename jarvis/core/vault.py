"""Der Vault ist die Wahrheit, die Datenbank nur ein Index.

`docs/MIGRATION-VAULT.md` legt das Prinzip fest:

    vault/*.md    = WAHRHEIT.  Menschenlesbar, in Obsidian editierbar, in git.
    SQLite + FTS5 = INDEX.     Abgeleitet. Jederzeit loeschbar und neu baubar.

Weil der Index nie autoritativ ist, gibt es hier **keine** Zwei-Wege-
Synchronisation und keinen Merge-Algorithmus. Dieses Modul schreibt Dateien
und liest Dateien, sonst nichts.

Kein PyYAML: der Stack ist festgelegt und enthaelt es nicht. Gelesen und
geschrieben wird deshalb genau die Teilmenge von YAML, die unten in
`serialisiere` erzeugt wird - Schluessel, Skalare und flache Listen. Was
darueber hinausgeht, wird als Text durchgereicht statt geraten.
"""

from __future__ import annotations

import os
import re
import unicodedata
import uuid
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any, Iterable

TRENNER = "---"

# Ordner, die Obsidian und git selbst verwalten. Wer die indexiert, indexiert
# Konfiguration statt Wissen.
IGNORIERT = {".obsidian", ".git", ".trash", ".obsidian.vimrc"}

UNTERORDNER = ("fakten", "projekte", "auftraege", "nachgeschlagen")


class VaultKonflikt(RuntimeError):
    """Die Datei auf der Platte ist neuer als der Stand, den wir kannten."""

    def __init__(self, pfad: Path, konfliktdatei: Path) -> None:
        super().__init__(
            f"{pfad.name} wurde ausserhalb von JARVIS geaendert. Nichts "
            f"ueberschrieben - der neue Stand liegt in {konfliktdatei.name}."
        )
        self.pfad = pfad
        self.konfliktdatei = konfliktdatei


@dataclass
class Notiz:
    """Eine Markdown-Datei im Vault, als Objekt.

    `id` ist der Schluessel, **nicht** der Dateiname. Obsidian benennt Dateien
    beim Umbenennen um und zieht Wikilinks nach; wer den Dateinamen als
    Schluessel nimmt, verliert den Fakt beim ersten Umbenennen.
    """

    id: str
    text: str
    typ: str = "fakt"
    quelle: str = "gespraech"
    erfasst: str = ""
    snapshot: str | None = None
    tags: list[str] = field(default_factory=list)
    links: list[str] = field(default_factory=list)
    # Rein informativ, wird nicht geschrieben:
    pfad: Path | None = None
    weitere: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if not self.erfasst:
            self.erfasst = date.today().isoformat()


def neue_id(praefix: str = "f") -> str:
    return f"{praefix}_{uuid.uuid4().hex[:6]}"


# --- Frontmatter ------------------------------------------------------------


def _skalar(wert: str) -> Any:
    wert = wert.strip()
    if wert in ("null", "~", ""):
        return None
    if wert.startswith("[") and wert.endswith("]"):
        inneres = wert[1:-1].strip()
        if not inneres:
            return []
        return [t.strip().strip("'\"") for t in inneres.split(",") if t.strip()]
    if len(wert) >= 2 and wert[0] == wert[-1] and wert[0] in "'\"":
        return wert[1:-1]
    return wert


def _als_yaml(wert: Any) -> str:
    if wert is None:
        return "null"
    if isinstance(wert, (list, tuple)):
        return "[" + ", ".join(str(x) for x in wert) + "]"
    text = str(wert)
    # Nur quoten, wenn es sonst als etwas anderes gelesen wuerde.
    if text == "" or text[0] in "[{'\"#" or ":" in text or text.strip() != text:
        return "'" + text.replace("'", "''") + "'"
    return text


def lies(pfad: Path) -> Notiz:
    """Liest eine Notiz. Fehlt die `id`, ist es keine JARVIS-Notiz."""
    roh = pfad.read_text(encoding="utf-8")
    kopf, koerper = trenne(roh)
    if "id" not in kopf:
        raise ValueError(f"{pfad}: kein 'id' im Frontmatter - keine JARVIS-Notiz.")

    bekannt = {"id", "typ", "quelle", "erfasst", "snapshot", "tags"}
    tags = kopf.get("tags") or []
    if isinstance(tags, str):
        tags = [tags]
    return Notiz(
        id=str(kopf["id"]),
        text=koerper.strip(),
        typ=str(kopf.get("typ") or "fakt"),
        quelle=str(kopf.get("quelle") or "gespraech"),
        erfasst=str(kopf.get("erfasst") or ""),
        snapshot=kopf.get("snapshot"),
        tags=list(tags),
        links=wikilinks(koerper),
        pfad=pfad,
        weitere={k: v for k, v in kopf.items() if k not in bekannt},
    )


def trenne(roh: str) -> tuple[dict[str, Any], str]:
    """Zerlegt eine Datei in Frontmatter und Koerper."""
    zeilen = roh.splitlines()
    if not zeilen or zeilen[0].strip() != TRENNER:
        return {}, roh
    try:
        ende = next(i for i in range(1, len(zeilen)) if zeilen[i].strip() == TRENNER)
    except StopIteration:
        # Offener Frontmatter-Block: nichts raten, alles als Koerper behandeln.
        return {}, roh

    kopf: dict[str, Any] = {}
    for zeile in zeilen[1:ende]:
        if not zeile.strip() or zeile.lstrip().startswith("#"):
            continue
        if ":" not in zeile:
            continue
        schluessel, _, wert = zeile.partition(":")
        kopf[schluessel.strip()] = _skalar(wert)
    return kopf, "\n".join(zeilen[ende + 1:])


def serialisiere(notiz: Notiz) -> str:
    felder: list[tuple[str, Any]] = [
        ("id", notiz.id),
        ("typ", notiz.typ),
        ("quelle", notiz.quelle),
        ("erfasst", notiz.erfasst),
        ("snapshot", notiz.snapshot),
        ("tags", notiz.tags),
    ]
    felder += sorted(notiz.weitere.items())
    kopf = "\n".join(f"{k}: {_als_yaml(v)}" for k, v in felder)
    koerper = notiz.text.strip()
    if notiz.links:
        verweise = "\n".join(f"Siehe [[{z}]]" for z in notiz.links
                             if f"[[{z}]]" not in koerper)
        if verweise:
            koerper = f"{koerper}\n\n{verweise}"
    return f"{TRENNER}\n{kopf}\n{TRENNER}\n\n{koerper}\n"


def wikilinks(text: str) -> list[str]:
    return re.findall(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]", text)


# --- Dateinamen -------------------------------------------------------------


def dateiname(notiz: Notiz) -> str:
    """Aus dem ersten Satz abgeleitet, entschaerft, plus Kurz-ID.

    Rein kosmetisch: der Schluessel ist die `id` im Frontmatter. Der Name darf
    sich jederzeit aendern, auch von Hand in Obsidian.
    """
    erster = re.split(r"(?<=[.!?])\s", notiz.text.strip(), maxsplit=1)[0]
    name = unicodedata.normalize("NFKD", erster)
    name = name.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    name = name.replace("Ä", "Ae").replace("Ö", "Oe").replace("Ü", "Ue")
    name = name.replace("ß", "ss")
    name = "".join(c for c in name if not unicodedata.combining(c))
    name = re.sub(r"[^A-Za-z0-9 _-]+", "", name).strip()
    name = re.sub(r"\s+", "-", name)[:60].strip("-")
    return f"{name or 'notiz'}-{notiz.id}.md"


# --- Schreiben --------------------------------------------------------------


def sicherstellen(wurzel: Path) -> Path:
    wurzel = Path(wurzel).expanduser()
    for unter in UNTERORDNER:
        (wurzel / unter).mkdir(parents=True, exist_ok=True)
    return wurzel


def _atomar(pfad: Path, inhalt: str) -> None:
    """Erst daneben schreiben, dann umlegen.

    Obsidian darf nie eine halbe Datei lesen - und ein Absturz mitten im
    Schreiben darf die alte Datei nicht zerstoeren.
    """
    pfad.parent.mkdir(parents=True, exist_ok=True)
    temp = pfad.with_name(f".{pfad.name}.{uuid.uuid4().hex[:8]}.tmp")
    try:
        temp.write_text(inhalt, encoding="utf-8")
        os.replace(temp, pfad)
    finally:
        if temp.exists():
            temp.unlink()


def schreibe(
    wurzel: Path,
    notiz: Notiz,
    *,
    unterordner: str = "fakten",
    bekannt_bis: float | None = None,
) -> Path:
    """Schreibt eine Notiz. Wirft `VaultKonflikt` statt still zu gewinnen.

    `bekannt_bis` ist die `mtime`, die der Index zuletzt gesehen hat. Ist die
    Datei auf der Platte neuer, hat ein Mensch sie angefasst - dann entsteht
    eine `-konflikt`-Datei und der alte Stand bleibt unberuehrt.
    """
    wurzel = sicherstellen(wurzel)
    ziel = finde(wurzel, notiz.id) or (wurzel / unterordner / dateiname(notiz))
    inhalt = serialisiere(notiz)

    if ziel.exists() and bekannt_bis is not None and ziel.stat().st_mtime > bekannt_bis + 1e-6:
        konflikt = ziel.with_name(f"{ziel.stem}-konflikt{ziel.suffix}")
        _atomar(konflikt, inhalt)
        raise VaultKonflikt(ziel, konflikt)

    _atomar(ziel, inhalt)
    return ziel


def finde(wurzel: Path, notiz_id: str) -> Path | None:
    """Sucht eine Notiz an ihrer `id`, nicht am Dateinamen."""
    for pfad in dateien(wurzel):
        try:
            kopf, _ = trenne(pfad.read_text(encoding="utf-8"))
        except OSError:
            continue
        if str(kopf.get("id") or "") == notiz_id:
            return pfad
    return None


def dateien(wurzel: Path) -> Iterable[Path]:
    """Alle Markdown-Dateien im Vault - ohne Obsidians und gits eigene."""
    wurzel = Path(wurzel).expanduser()
    if not wurzel.exists():
        return []
    treffer = []
    for pfad in sorted(wurzel.rglob("*.md")):
        if any(teil in IGNORIERT for teil in pfad.relative_to(wurzel).parts):
            continue
        if pfad.name.startswith("."):
            continue
        treffer.append(pfad)
    return treffer


def loesche(wurzel: Path, notiz_id: str) -> bool:
    pfad = finde(wurzel, notiz_id)
    if pfad is None:
        return False
    pfad.unlink()
    return True
