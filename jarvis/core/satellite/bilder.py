"""Wo die Satellitenbilder liegen.

Ein Bild ist das einzige Binaerding, das JARVIS aufhebt. Es gehoert nicht
in die Datenbank: SQLite kann Blobs, aber ein Bild ist abgeleitet - es
laesst sich jederzeit neu rendern, solange die Szene bekannt ist. Deshalb
Dateien unter `data/bilder/`, genauso wegwerfbar wie der Vault-Index.

**Inhaltsadressiert.** Der Name ist der SHA-256 der Bytes. Zweimal
derselbe Ausschnitt am selben Tag ergibt dieselbe Datei, kostet also keine
zweiten Processing Units und belegt keinen zweiten Platz.

**Warum der Token nicht in die Bild-URL kommt.** Ein `<img src="...">`
schickt keine eigenen Header - der Browser holt die Adresse blank. Wer
also `/api/bild/<id>?token=...` bauen wuerde, haette den Token in der
Adresszeile, im Verlauf, im Referrer und in jedem Server-Log. Stattdessen
holt das Frontend die Bytes per fetch() mit dem Header wie jeden anderen
Aufruf und macht daraus eine Blob-URL. Der Zugangsschutz aus 0.4 gilt
damit auch fuer Bilder, ohne Ausnahme und ohne Schlupfloch.
"""

from __future__ import annotations

import hashlib
import logging
import re
from pathlib import Path

log = logging.getLogger("jarvis")

# Genau die Form, die `speichere` erzeugt. Alles andere wird abgewiesen,
# bevor daraus ein Pfad wird - sonst waere `../../etc/passwd` eine gueltige
# Bild-ID.
ID_FORM = re.compile(r"^[0-9a-f]{32}$")

# Ein PNG faengt immer so an. Was das nicht tut, wird gar nicht erst abgelegt.
PNG_MAGIE = b"\x89PNG\r\n\x1a\n"


class BildFehler(ValueError):
    pass


def ordner(db_path: Path | str) -> Path:
    """Neben der Datenbank, nicht darin."""
    return Path(db_path).parent / "bilder"


def speichere(daten: bytes, *, db_path: Path | str) -> str:
    """Legt die Bytes ab und gibt die ID zurueck."""
    if not daten:
        raise BildFehler("Leeres Bild wird nicht abgelegt.")
    if not daten.startswith(PNG_MAGIE):
        raise BildFehler(
            "Das sind keine PNG-Daten. Was nicht als Bild erkennbar ist, "
            "wird nicht abgelegt - sonst liegt eine Fehlermeldung als "
            "'.png' auf der Platte und die Oberflaeche zeigt ein kaputtes "
            "Bild an."
        )
    kennung = hashlib.sha256(daten).hexdigest()[:32]
    ziel = ordner(db_path) / f"{kennung}.png"
    if not ziel.exists():
        ziel.parent.mkdir(parents=True, exist_ok=True)
        # Erst daneben schreiben, dann umbenennen: ein abgebrochener
        # Schreibvorgang hinterlaesst sonst eine halbe Datei unter einem
        # Namen, der Vollstaendigkeit verspricht.
        vorlaeufig = ziel.with_suffix(".teil")
        vorlaeufig.write_bytes(daten)
        vorlaeufig.replace(ziel)
        log.info("Satellitenbild abgelegt: %s (%d Bytes)", ziel.name, len(daten))
    return kennung


def lade(kennung: str, *, db_path: Path | str) -> bytes | None:
    """Die Bytes zur ID, oder None. Wirft bei einer unmoeglichen ID."""
    if not ID_FORM.match(kennung or ""):
        raise BildFehler(
            f"Keine gueltige Bild-ID: {kennung!r}. Erwartet sind 32 "
            f"Hex-Zeichen."
        )
    datei = ordner(db_path) / f"{kennung}.png"
    if not datei.is_file():
        return None
    return datei.read_bytes()
