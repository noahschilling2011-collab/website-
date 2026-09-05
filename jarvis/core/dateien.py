"""Lesender Zugriff auf freigegebene Ordner.

**Was das hier NICHT ist.** Kein Computer-Agent. `CLAUDE.md` fuehrt den
unter Non-Goals als *dauerhaft gestrichen*, und Regel 5 verbietet `eval`,
`exec` und `shell=True` mit Eingaben aus einem Modell. Hier wird nichts
ausgefuehrt, nichts geschrieben, nichts geloescht - es wird gelesen, und
zwar nur in Ordnern, die in der `.env` stehen.

Der Vertrag sieht genau das seit Phase 0 vor, `core/contracts.py:25`:

    READ = 1        # lesen: Websuche, Datei lesen, Kalender lesen

**Zwei Sperren, nicht eine.** Die Allowlist (`DATEI_WURZELN`) schuetzt vor
dem falschen Ordner, die Sperrliste vor der falschen Datei im richtigen
Ordner. Wer nur eine davon baut, hat die andere Haelfte des Problems
uebrig: ein `.env` mit dem LLM-Key liegt in einem voellig normalen
Projektordner.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


class PfadAbgelehnt(PermissionError):
    """Der Pfad liegt ausserhalb der freigegebenen Ordner - oder auf der
    Sperrliste.

    Die Nachricht nennt **nie** den vollstaendigen Systempfad. Eine
    Fehlermeldung, die `/home/noah/.ssh/id_rsa` ausplaudert, verraet genau
    das, was die Sperre verhindern sollte (FIX-07, Abschnitt 7).
    """


# Namen, die auch innerhalb einer freigegebenen Wurzel nie gelesen werden.
# Kleingeschrieben verglichen: Windows-Dateisysteme unterscheiden nicht.
GESPERRTE_NAMEN = frozenset({
    "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
    "login data", "cookies.sqlite", "key4.db", "logins.json",
    "credentials", "authorized_keys", "known_hosts",
})

GESPERRTE_ENDUNGEN = frozenset({
    ".pem", ".key", ".p12", ".pfx", ".keychain", ".kdbx",
    ".sqlite", ".sqlite3", ".db",
})

# Binaeres kommt nicht ins Modell. Die Liste ist nicht die Sperre - die
# Sperre ist der Dekodierversuch weiter unten. Sie spart nur das Lesen.
BINAERE_ENDUNGEN = frozenset({
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".ico", ".tif", ".tiff",
    ".pdf", ".zip", ".gz", ".bz2", ".xz", ".7z", ".rar", ".tar",
    ".mp3", ".mp4", ".mov", ".avi", ".mkv", ".wav", ".ogg", ".flac",
    ".exe", ".dll", ".so", ".dylib", ".bin", ".o", ".pyc",
    ".docx", ".xlsx", ".pptx", ".odt", ".ods",
})


@dataclass(frozen=True)
class Fund:
    pfad: str            # relativ zur Wurzel - nie absolut nach aussen
    absolut: Path        # nur intern
    groesse_kb: float
    geaendert: str
    treffer_zeile: str = ""

    def als_dict(self) -> dict:
        d = {
            "pfad": self.pfad,
            "groesse_kb": self.groesse_kb,
            "geaendert": self.geaendert,
        }
        if self.treffer_zeile:
            d["treffer_zeile"] = self.treffer_zeile
        return d


def wurzeln_aus(roh: str) -> list[Path]:
    """`DATEI_WURZELN` in eine Liste aufgeloester Pfade.

    Getrennt durch `os.pathsep` - `:` unter Linux und macOS, `;` unter
    Windows. Einmal beim Start aufgeloest; danach ist der Vergleich in
    `pruefe()` ein Vergleich und keine Zeichenkettenakrobatik.

    Was nicht existiert, faellt still weg: ein Tippfehler in der `.env`
    soll den Start nicht verhindern, und ein Ordner, den es nicht gibt,
    gibt auch nichts frei.
    """
    aufgeloest: list[Path] = []
    for teil in str(roh or "").split(os.pathsep):
        teil = teil.strip()
        if not teil:
            continue
        try:
            p = Path(teil).expanduser().resolve(strict=True)
        except (OSError, RuntimeError):
            continue
        if p.is_dir():
            aufgeloest.append(p)
    return aufgeloest


def pruefe(kandidat: str | Path, wurzeln: list[Path]) -> Path:
    """Gibt den Pfad zurueck, wenn er wirklich unter einer Wurzel liegt.

    **ZUERST aufloesen, DANN vergleichen.** Andersherum ist die Pruefung
    wertlos: `resolve()` folgt Symlinks, und ein Symlink in einem
    freigegebenen Ordner, der nach `/etc` zeigt, kaeme sonst durch. Genau
    das prueft DoD-Kriterium 2, und zwar mit einem echt angelegten Symlink.

    `is_relative_to` gibt es ab Python 3.9; das Projekt faehrt 3.11
    (nachgesehen: `sys.version` 3.11.15, `hasattr(Path, 'is_relative_to')`
    ist True).
    """
    if not wurzeln:
        raise PfadAbgelehnt(
            "Kein Dateizugriff eingerichtet: DATEI_WURZELN fehlt in der .env."
        )
    try:
        p = Path(kandidat).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise PfadAbgelehnt("Diesen Pfad gibt es nicht.") from exc

    for w in wurzeln:
        if p == w or p.is_relative_to(w):
            return p
    # Kein Pfad in der Meldung: sie geht ans Modell und in die Oberflaeche.
    raise PfadAbgelehnt(
        "Dieser Pfad liegt ausserhalb der freigegebenen Ordner."
    )


def gesperrt(p: Path) -> str | None:
    """Grund, warum diese Datei auch innerhalb der Wurzel nicht gelesen
    wird - oder `None`.

    Geprueft wird der ganze Pfad relativ zur Wurzel, nicht nur der
    Dateiname: `.ssh/config` heisst nicht `.config`, liegt aber in einem
    Punktordner und ist damit genauso tabu.
    """
    for teil in p.parts:
        if teil.startswith(".") and teil not in (".", ".."):
            return "Versteckte Dateien und Ordner (Name beginnt mit einem Punkt)"
    name = p.name.lower()
    if name in GESPERRTE_NAMEN:
        return "Diese Datei steht auf der Sperrliste"
    if p.suffix.lower() in GESPERRTE_ENDUNGEN:
        return f"Dateien mit der Endung {p.suffix} werden nicht gelesen"
    return None


def _zeitstempel(p: Path) -> str:
    return datetime.fromtimestamp(p.stat().st_mtime, timezone.utc).strftime(
        "%Y-%m-%d %H:%M"
    )


def _relativ(p: Path, wurzeln: list[Path]) -> str:
    """Der Pfad, wie er nach aussen gehen darf: relativ zur Wurzel."""
    for w in wurzeln:
        if p == w or p.is_relative_to(w):
            return f"{w.name}/{p.relative_to(w).as_posix()}" if p != w else w.name
    return p.name


def suche(
    muster: str,
    wurzeln: list[Path],
    *,
    inhalt: bool = False,
    hoechstens: int = 20,
    max_kb: int = 512,
) -> list[Fund]:
    """Dateien nach Name oder Inhalt finden.

    Die Rueckgabe enthaelt **Pfade und Metadaten, keine Dateiinhalte** -
    ausser der einen Trefferzeile bei `inhalt=True`. Wer den Inhalt will,
    ruft `datei_lesen`; dann steht dieser Zugriff einzeln im
    `tool_calls`-Log und ist in der Oberflaeche aufklappbar.
    """
    muster = (muster or "").strip()
    if not muster:
        return []
    hoechstens = max(1, min(int(hoechstens), 100))
    gefunden: list[Fund] = []
    glob = muster if any(z in muster for z in "*?[") else f"*{muster}*"

    for w in wurzeln:
        for p in sorted(w.rglob("*" if inhalt else glob)):
            if len(gefunden) >= hoechstens:
                return gefunden
            if not p.is_file():
                continue
            rel = p.relative_to(w)
            if gesperrt(rel) is not None:
                continue
            try:
                gross = p.stat().st_size
            except OSError:
                continue
            if gross > max_kb * 1024:
                continue

            zeile = ""
            if inhalt:
                if p.suffix.lower() in BINAERE_ENDUNGEN:
                    continue
                zeile = _erste_trefferzeile(p, muster)
                if not zeile:
                    continue

            gefunden.append(Fund(
                pfad=_relativ(p, wurzeln),
                absolut=p,
                groesse_kb=round(gross / 1024, 1),
                geaendert=_zeitstempel(p),
                treffer_zeile=zeile,
            ))
    return gefunden


def _erste_trefferzeile(p: Path, muster: str) -> str:
    """Zeilenweise lesen und bei der ersten Grenze abbrechen.

    Nicht `read_text()`: eine 400-MB-Logdatei soll nicht in den Speicher
    wandern, nur weil jemand nach einem Wort sucht.
    """
    gesucht = muster.lower()
    try:
        with p.open("r", encoding="utf-8", errors="strict") as f:
            for nr, zeile in enumerate(f, 1):
                if nr > 20_000:
                    return ""
                if gesucht in zeile.lower():
                    return f"{nr}: {zeile.strip()[:200]}"
    except (OSError, UnicodeDecodeError):
        return ""
    return ""


def lies(
    p: Path,
    *,
    ab_zeile: int = 0,
    zeilen: int = 300,
    max_kb: int = 512,
) -> dict:
    """Einen Ausschnitt lesen. Nie die ganze Datei ungefragt.

    `abgeschnitten` steht im Ergebnis, damit weder Modell noch Mensch
    glaubt, alles gesehen zu haben.
    """
    grund = gesperrt(Path(p.name)) or gesperrt(p)
    if grund is not None:
        raise PfadAbgelehnt(grund + ".")

    gross = p.stat().st_size
    if gross > max_kb * 1024:
        raise PfadAbgelehnt(
            f"Die Datei ist {round(gross / 1024)} kB gross, die Grenze liegt "
            f"bei {max_kb} kB (DATEI_MAX_KB in der .env)."
        )
    if p.suffix.lower() in BINAERE_ENDUNGEN:
        raise PfadAbgelehnt(
            f"Dateien mit der Endung {p.suffix} sind binaer und gehen nicht "
            f"ins Modell."
        )

    roh = p.read_bytes()
    text = None
    for kodierung in ("utf-8", "latin-1"):
        try:
            text = roh.decode(kodierung)
            break
        except UnicodeDecodeError:
            continue
    if text is None or "\x00" in text[:4096]:
        # latin-1 dekodiert fast alles; ein Nullbyte im Kopf ist das
        # verlaesslichere Zeichen dafuer, dass es keine Textdatei ist.
        raise PfadAbgelehnt(
            "Das ist keine Textdatei - binaerer Inhalt geht nicht ins Modell."
        )

    alle = text.splitlines()
    ab = max(0, int(ab_zeile))
    wieviel = max(1, min(int(zeilen), 2000))
    ausschnitt = alle[ab:ab + wieviel]
    return {
        "zeilen_gesamt": len(alle),
        "ab_zeile": ab,
        "ausschnitt": "\n".join(ausschnitt),
        "abgeschnitten": ab + len(ausschnitt) < len(alle),
    }
