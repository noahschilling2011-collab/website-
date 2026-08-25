"""Weltlage - Meldungen mit Herkunft, oder gar keine.

`docs/phases/PHASE-11.md` hat zwei Regeln, an denen diese Phase haengt:

**Das Bild kommt aus der Quelle, oder es gibt kein Bild.** Kein Stockfoto, kein
KI-Bild, kein Platzhalter, der wie ein Foto aussieht. Ein Bild vom Kreml neben
einer Moskau-Meldung, das nicht zu dieser Meldung gehoert, ist eine Attrappe -
auch wenn es echt aussieht.

**Ohne Medium und Datum wird die Meldung verworfen.** Das ist die Ersatzregel
fuer den weggefallenen Hyperlink und sie ist nicht verhandelbar.

Beides steht hier als Code und nicht als Bitte im Prompt: eine Regel, die von
der Tagesform eines Modells abhaengt, ist keine Regel.
"""

from __future__ import annotations

import html
import re
import urllib.parse
import urllib.robotparser
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

import httpx

# Ehrlicher User-Agent mit Zweck. Verlage duerfen wissen, wer da liest.
USER_AGENT = "JARVIS-Weltlage/0.1 (persoenlicher Assistent; kein Crawler)"

BILD_TIMEOUT_S = 5.0
CACHE_TTL_MINUTEN = 60


class Verworfen(ValueError):
    """Eine Meldung, die den Datenvertrag nicht erfuellt."""


@dataclass
class Quellbild:
    """Was der Verlag selbst als Vorschaubild bereitstellt - sonst nichts."""

    url: str
    herkunft: str                 # Pflicht, sobald url gesetzt ist
    beschreibung: str | None = None   # og:image:alt / alt / figcaption, NIE erzeugt


@dataclass
class Meldung:
    """Der Datenvertrag aus PHASE-11 Abschnitt 7."""

    schlagzeile: str
    kurz: str                         # max 2 Saetze
    medium: str                       # Pflicht
    veroeffentlicht: datetime         # Pflicht
    quell_url: str                    # gespeichert, nicht angezeigt
    land_iso: str
    bild_url: str | None = None       # NUR og:image der Quelle
    bild_herkunft: str | None = None  # Pflicht, sobald bild_url gesetzt ist
    bild_beschreibung: str | None = None
    lat: float | None = None
    lon: float | None = None
    einordnung: str = ""              # von JARVIS, ausdruecklich nicht aus der Quelle
    einordnung_fehlt: str = ""        # warum sie leer bleibt

    def als_dict(self) -> dict:
        return {
            "schlagzeile": self.schlagzeile,
            "kurz": self.kurz,
            "medium": self.medium,
            "veroeffentlicht": self.veroeffentlicht.astimezone(timezone.utc)
                                   .strftime("%Y-%m-%dT%H:%M:%SZ"),
            "quell_url": self.quell_url,
            "land_iso": self.land_iso,
            "bild_url": self.bild_url,
            "bild_herkunft": self.bild_herkunft,
            "bild_beschreibung": self.bild_beschreibung,
            "lat": self.lat,
            "lon": self.lon,
            "einordnung": self.einordnung,
            "einordnung_fehlt": self.einordnung_fehlt,
        }


# FIX-02 Schritt 3: eine Meldung, die aelter ist als das, wird verworfen.
# "Weltlage" heisst Lage, nicht Archiv.
MAX_ALTER_TAGE = 3


def pruefe(meldung: Meldung, *, jetzt: datetime | None = None) -> str | None:
    """Gibt den Verwerfungsgrund zurueck, oder None wenn die Meldung gilt.

    Keiner dieser Gruende ist verhandelbar, und keiner haengt an einem Modell.
    """
    if not (meldung.schlagzeile or "").strip():
        return "keine Schlagzeile"
    if not (meldung.kurz or "").strip():
        return "kein Text"
    if not (meldung.medium or "").strip():
        return "kein Medium"
    if meldung.veroeffentlicht is None:
        return "kein Datum"
    if not _url_gueltig(meldung.quell_url):
        return "Quell-URL ungueltig"
    if meldung.bild_url and not (meldung.bild_herkunft or "").strip():
        return "Bild ohne Herkunft"

    bezug = jetzt or _jetzt()
    if abs((bezug - meldung.veroeffentlicht).days) > MAX_ALTER_TAGE:
        return f"aelter als {MAX_ALTER_TAGE} Tage"
    return None


def _url_gueltig(url: str) -> bool:
    try:
        teile = urllib.parse.urlparse(url or "")
    except ValueError:
        return False
    return teile.scheme in ("http", "https") and bool(teile.netloc)


def siebe(
    meldungen: list[Meldung],
    *,
    weltweit: bool = False,
    jetzt: datetime | None = None,
) -> tuple[list[Meldung], list[str]]:
    """Trennt gueltige von verworfenen Meldungen.

    Die Anzahl der verworfenen steht sichtbar in der Statusleiste - deshalb
    kommen die Gruende hier mit heraus statt im Log zu verschwinden.

    Drei Siebe, in dieser Reihenfolge:
    1. der Vertrag je Meldung (`pruefe`),
    2. Duplikate - gleiche Schlagzeile ODER gleiche Quell-URL,
    3. im Weltweit-Modus: alles aus demselben Land ist keine Weltlage.
    """
    gut: list[Meldung] = []
    verworfen: list[str] = []
    gesehen_titel: set[str] = set()
    gesehen_url: set[str] = set()

    for m in meldungen:
        grund = pruefe(m, jetzt=jetzt)
        if grund is not None:
            verworfen.append(grund)
            continue

        titel = " ".join((m.schlagzeile or "").lower().split())
        url = (m.quell_url or "").strip().rstrip("/")
        if titel in gesehen_titel:
            verworfen.append("doppelte Schlagzeile")
            continue
        if url in gesehen_url:
            verworfen.append("doppelte Quell-URL")
            continue

        gesehen_titel.add(titel)
        gesehen_url.add(url)
        gut.append(m)

    # Fuenf Karten aus einem Land, waehrend "weltweit" aktiv ist, ist keine
    # Weltlage, sondern ein Fehler. Lieber nichts zeigen als das Falsche.
    if weltweit and len(gut) > 1:
        laender = {(m.land_iso or "").strip().upper() for m in gut}
        if len(laender) < 2:
            verworfen.extend(["nur ein Land im Weltweit-Modus"] * len(gut))
            return [], verworfen

    return gut, verworfen


# --- Das Quellbild ----------------------------------------------------------

_META = re.compile(
    r"<meta\s+[^>]*?(?:property|name)\s*=\s*[\"']([^\"']+)[\"'][^>]*?"
    r"content\s*=\s*[\"']([^\"']*)[\"'][^>]*>",
    re.IGNORECASE,
)
_META_UMGEKEHRT = re.compile(
    r"<meta\s+[^>]*?content\s*=\s*[\"']([^\"']*)[\"'][^>]*?"
    r"(?:property|name)\s*=\s*[\"']([^\"']+)[\"'][^>]*>",
    re.IGNORECASE,
)
_FIGCAPTION = re.compile(r"<figcaption[^>]*>(.*?)</figcaption>", re.IGNORECASE | re.DOTALL)
_IMG_ALT = re.compile(r"<img\s+[^>]*alt\s*=\s*[\"']([^\"']+)[\"']", re.IGNORECASE)


def meta_felder(seite: str) -> dict[str, str]:
    felder: dict[str, str] = {}
    for schluessel, wert in _META.findall(seite):
        felder.setdefault(schluessel.strip().lower(), html.unescape(wert.strip()))
    for wert, schluessel in _META_UMGEKEHRT.findall(seite):
        felder.setdefault(schluessel.strip().lower(), html.unescape(wert.strip()))
    return felder


def _nur_text(roh: str) -> str:
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", roh))).strip()
    # "3. Mai ." entsteht, wenn ein </b> vor dem Punkt steht. Das ist keine
    # Bildbeschreibung aus der Quelle mehr, sondern eine mit Tippfehler.
    return re.sub(r"\s+([.,;:!?])", r"\1", text)


def bild_aus_seite(seite: str, quell_url: str, medium: str) -> Quellbild | None:
    """Liest `og:image` aus der Seite. Kein Treffer heisst: kein Bild.

    Reihenfolge wie im Phasenauftrag: og:image -> twitter:image -> None.
    **Kein Fallback auf Stockfotos.**
    """
    felder = meta_felder(seite)
    url = felder.get("og:image") or felder.get("twitter:image") or ""
    if not url:
        return None
    url = urllib.parse.urljoin(quell_url, url)
    if not _url_gueltig(url):
        return None

    # Die Beschreibung kommt AUS DER QUELLE, geschrieben von jemandem, der
    # wusste, was auf dem Foto ist. Wird keine gefunden, bleibt sie leer -
    # dann sagt JARVIS zum Bild nichts.
    beschreibung = (felder.get("og:image:alt") or felder.get("twitter:image:alt") or "").strip()
    if not beschreibung:
        treffer = _FIGCAPTION.search(seite)
        if treffer:
            beschreibung = _nur_text(treffer.group(1))
    if not beschreibung:
        treffer = _IMG_ALT.search(seite)
        if treffer:
            beschreibung = html.unescape(treffer.group(1)).strip()

    return Quellbild(url=url, herkunft=medium or urllib.parse.urlparse(quell_url).netloc,
                     beschreibung=beschreibung or None)


async def darf_ich(url: str, client: httpx.AsyncClient) -> bool:
    """robots.txt respektieren. Bei Unerreichbarkeit: nicht holen.

    Ein Verlag, dessen robots.txt gerade nicht antwortet, hat nicht
    zugestimmt. Im Zweifel nichts holen ist billiger als im Zweifel holen.
    """
    teile = urllib.parse.urlparse(url)
    try:
        antwort = await client.get(f"{teile.scheme}://{teile.netloc}/robots.txt",
                                   timeout=BILD_TIMEOUT_S)
    except httpx.HTTPError:
        return False
    if antwort.status_code == 404:
        return True                      # keine robots.txt = keine Einschraenkung
    if antwort.status_code >= 400:
        return False
    parser = urllib.robotparser.RobotFileParser()
    parser.parse(antwort.text.splitlines())
    return parser.can_fetch(USER_AGENT, url)


async def hole_quellbild(
    url: str,
    *,
    medium: str = "",
    transport: httpx.AsyncBaseTransport | None = None,
) -> Quellbild | None:
    """Serverseitig, weil der Browser an CORS scheitert.

    Gibt die `og:image`-URL zurueck oder None. **Niemals einen Ersatz.**
    """
    if not _url_gueltig(url):
        return None
    kopf = {"user-agent": USER_AGENT, "accept": "text/html"}
    try:
        async with httpx.AsyncClient(timeout=BILD_TIMEOUT_S, transport=transport,
                                     follow_redirects=True, headers=kopf) as client:
            if not await darf_ich(url, client):
                return None
            antwort = await client.get(url)
            if antwort.status_code >= 400:
                return None
            typ = antwort.headers.get("content-type", "")
            if "html" not in typ.lower():
                return None
            return bild_aus_seite(antwort.text, url, medium)
    except httpx.HTTPError:
        return None


# --- Cache ------------------------------------------------------------------


def _jetzt() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class CacheStand:
    treffer: int = 0
    abfragen: int = 0

    @property
    def quote(self) -> float:
        gesamt = self.treffer + self.abfragen
        return (self.treffer / gesamt) if gesamt else 0.0


def cache_lesen(conn, land_iso: str, ttl_minuten: int = CACHE_TTL_MINUTEN) -> dict | None:
    """Ein Klick innerhalb der TTL kostet null neue Auftraege."""
    import json

    zeile = conn.execute(
        "SELECT nutzlast, geholt_am FROM weltlage_cache WHERE land_iso = ?",
        (land_iso,),
    ).fetchone()
    if zeile is None:
        return None
    try:
        geholt = datetime.strptime(zeile[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    if _jetzt() - geholt > timedelta(minutes=ttl_minuten):
        return None
    daten = json.loads(zeile[0])
    daten["cache"] = True
    daten["alter_minuten"] = int((_jetzt() - geholt).total_seconds() // 60)
    return daten


def cache_schreiben(conn, land_iso: str, nutzlast: dict) -> None:
    import json

    conn.execute(
        "INSERT INTO weltlage_cache (land_iso, nutzlast, geholt_am) VALUES (?, ?, ?) "
        "ON CONFLICT(land_iso) DO UPDATE SET nutzlast=excluded.nutzlast, "
        "geholt_am=excluded.geholt_am",
        (land_iso, json.dumps(nutzlast, ensure_ascii=False),
         _jetzt().strftime("%Y-%m-%dT%H:%M:%SZ")),
    )
