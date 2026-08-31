"""Kalender lesen: ICS-Datei oder ICS-Abo-Adresse.

Kein neues Paket. Das Format ist RFC 5545, und die vier Stellen, an denen
ein naiver Parser scheitert, sind hier ausdruecklich behandelt. Die Regeln
sind **aus der Norm geholt** (`https://www.rfc-editor.org/rfc/rfc5545.txt`,
HTTP 200 am 27.08.2026), nicht aus dem Gedaechtnis - `CLAUDE.md` Regel 1,
und bei Feldnamen wie `RECURRENCE-ID` ist die Verwechslungsgefahr real.

**1. Zeilenfaltung** (Abschnitt 3.1). Woertlich:

    Any sequence of CRLF followed immediately by a single linear
    white-space character is ignored (i.e., removed) when processing the
    content type. ... Unfolding is accomplished by removing the CRLF and
    the linear white-space character that immediately follows.

Das muss **vor allem anderen** passieren, sonst zerfaellt jeder Titel ueber
75 Oktetts mitten im Wort.

**2. Drei Formen von DATE-TIME** (Abschnitt 3.3.5):

    FORM #1: DATE WITH LOCAL TIME              20260827T140000
    FORM #2: DATE WITH UTC TIME                20260827T120000Z
    FORM #3: DATE WITH LOCAL TIME AND TIME ZONE REFERENCE
                                               TZID=Europe/Berlin:20260827T140000

Dazu `VALUE=DATE` fuer ganztaegig (Abschnitt 3.3.4). Ein Ganztagstermin ist
**kein** Termin um 00:00 Uhr, und er wird auch nicht so angezeigt.

**3. Escaping in TEXT-Werten** (Abschnitt 3.3.11), woertlich:

    ESCAPED-CHAR = ("\\\\" / "\\;" / "\\," / "\\N" / "\\n")
       ; \\\\ encodes \\, \\N or \\n encodes newline
       ; \\; encodes ;, \\, encodes ,

Der Doppelpunkt wird ausdruecklich **nicht** escaped.

**4. RRULE** wird nicht aufgeloest, sondern gezaehlt - siehe `AUSBLICK`
unten.

**Fehlendes DTEND** (Abschnitt 3.6.1), woertlich:

    For cases where a "VEVENT" calendar component specifies a "DTSTART"
    property with a DATE value type but no "DTEND" nor "DURATION"
    property, the event's duration is taken to be one day. For cases
    where a "VEVENT" calendar component specifies a "DTSTART" property
    with a DATE-TIME value type but no "DTEND" property, the event ends
    on the same calendar date and time of day specified by the "DTSTART"
    property.

Und `DTEND` ist **nicht einschliessend** ("non-inclusive end").
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

log = logging.getLogger("jarvis")

# 15 Minuten. Dieselbe Ueberlegung wie beim TLE-Cache in
# core/satellite/ueberflug.py: ein Kalender aendert sich nicht im
# Sekundentakt, und jede Frage nach "was habe ich heute vor" soll nicht
# eine Abfrage nach draussen ausloesen. Kuerzer waere Hoeflichkeit gegen
# den Anbieter verletzt, laenger wuerde ein gerade verschobener Termin zu
# lange falsch stehen.
HOECHSTALTER_S = 15 * 60

AUSBLICK = (
    "Wiederkehrende Termine werden nicht aufgeloest. `RRULE` richtig zu "
    "rechnen heisst FREQ, INTERVAL, BYDAY, BYMONTHDAY, COUNT, UNTIL, dazu "
    "EXDATE fuer gestrichene und RECURRENCE-ID fuer verschobene "
    "Einzeltermine. Ein halb richtiger Wiederholungsregler zeigt Termine "
    "an, die es nicht gibt - das ist schlechter als keiner."
)


class KalenderFehler(RuntimeError):
    pass


@dataclass(frozen=True)
class Termin:
    titel: str
    beginn: datetime | date
    ende: datetime | date
    ganztaegig: bool
    ort: str = ""
    kalender: str = ""

    def als_dict(self) -> dict:
        return {
            "titel": self.titel,
            "beginn": self.beginn.isoformat(),
            "ende": self.ende.isoformat(),
            "ganztaegig": self.ganztaegig,
            "ort": self.ort,
            "kalender": self.kalender,
        }


# --- 1. Faltung -------------------------------------------------------------


def entfalte(roh: str) -> list[str]:
    """RFC 5545, 3.1: CRLF plus EIN folgendes Leerzeichen oder Tab entfernen.

    Robust gegen Dateien, die nur LF benutzen - die gibt es in freier
    Wildbahn genauso, und ein Parser, der daran scheitert, scheitert an der
    Haelfte aller Exporte.
    """
    zeilen: list[str] = []
    for zeile in roh.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if zeile[:1] in (" ", "\t") and zeilen:
            zeilen[-1] += zeile[1:]
        else:
            zeilen.append(zeile)
    return zeilen


# --- 3. Escaping ------------------------------------------------------------


def entschluessele(wert: str) -> str:
    """RFC 5545, 3.3.11. Zeichen fuer Zeichen, nicht mit `replace` in Folge.

    Mit aufeinanderfolgenden `replace`-Aufrufen wuerde `\\\\n` (ein
    maskierter Backslash, gefolgt von einem n) faelschlich zu einem
    Zeilenumbruch - der erste Durchgang macht aus `\\\\` ein `\\`, der
    zweite liest es zusammen mit dem `n` neu.
    """
    aus: list[str] = []
    i = 0
    while i < len(wert):
        z = wert[i]
        if z == "\\" and i + 1 < len(wert):
            n = wert[i + 1]
            if n in ("n", "N"):
                aus.append("\n")
            elif n in ("\\", ";", ","):
                aus.append(n)
            else:
                aus.append(n)          # unbekannt: Backslash faellt weg
            i += 2
            continue
        aus.append(z)
        i += 1
    return "".join(aus)


# --- 2. Datum und Zeit ------------------------------------------------------


def _zone(tzid: str):
    try:
        return ZoneInfo(tzid)
    except (ZoneInfoNotFoundError, ValueError, KeyError):
        log.warning("Kalender: Zeitzone %r unbekannt, nehme UTC.", tzid)
        return timezone.utc


# --- Anzeigezone ------------------------------------------------------------
#
# Verknuepfungspruefung 31.08.2026, Funde 2 und 3: der Kalender rechnete
# nirgends in eine Zone um. Ueberall, wo hier `zone` steht, gilt:
#
#   zone is None  ->  die Ortszeit DIESES Rechners, so wie `clock` sie ohne
#                     Argument liefert (core/tools/builtin.py:51). Dafuer
#                     wird `astimezone()` OHNE Argument benutzt, nicht ein
#                     einmal eingesammeltes `datetime.now().astimezone()
#                     .tzinfo`: letzteres ist ein FESTER Versatz fuer den
#                     Moment des Einsammelns und wuerde einen Termin im
#                     Dezember mit dem Sommerversatz rechnen.
#   zone gesetzt  ->  genau diese Zone (Tests geben ZoneInfo herein, damit
#                     sie nicht von der TZ des Testrechners abhaengen).


def _mit_zone(naiv: datetime, zone) -> datetime:
    """Naive Ortszeit zu einem Zeitpunkt machen - sommerzeitrichtig."""
    return naiv.astimezone() if zone is None else naiv.replace(tzinfo=zone)


def in_anzeigezone(x: datetime, zone=None) -> datetime:
    """Einen Zeitpunkt in die Anzeigezone umrechnen (verschiebt nichts real)."""
    return x.astimezone() if zone is None else x.astimezone(zone)


def zonenname(bezug: date, zone=None) -> str:
    """Wie die Anzeigezone AN DIESEM TAG heisst - 'CEST', 'CET', 'UTC'.

    Mit Bezugstag, weil der Name mit der Sommerzeit wechselt.
    """
    return _mit_zone(
        datetime(bezug.year, bezug.month, bezug.day), zone
    ).tzname() or "UTC"


def lies_zeit(wert: str, params: dict[str, str], zone=None) -> tuple[datetime | date, bool]:
    """Gibt (Zeitpunkt, ganztaegig) zurueck. RFC 5545, 3.3.4 und 3.3.5."""
    wert = wert.strip()
    if params.get("VALUE", "").upper() == "DATE" or (
        len(wert) == 8 and "T" not in wert
    ):
        return date(int(wert[0:4]), int(wert[4:6]), int(wert[6:8])), True

    if "T" not in wert:
        raise KalenderFehler(f"Kein erkennbares Datum: {wert!r}")
    tag, uhr = wert.split("T", 1)
    utc = uhr.endswith("Z")
    uhr = uhr.rstrip("Z")
    if len(uhr) < 6:
        uhr = uhr.ljust(6, "0")
    roh = datetime(
        int(tag[0:4]), int(tag[4:6]), int(tag[6:8]),
        int(uhr[0:2]), int(uhr[2:4]), int(uhr[4:6]),
    )
    if utc:                                    # FORM #2
        return roh.replace(tzinfo=timezone.utc), False
    tzid = params.get("TZID", "")
    if tzid:                                   # FORM #3
        return roh.replace(tzinfo=_zone(tzid)), False
    # FORM #1: Ortszeit ohne Zone. Die Norm laesst sie ausdruecklich zu und
    # meint damit "die Zeit da, wo der Betrachter ist".
    #
    # WAS WAR FALSCH: hier stand `roh.replace(tzinfo=timezone.utc)`. Solange
    # die Ausgabe die Wanduhrzeit des Objekts druckte, fiel das nicht auf -
    # 14:00 kam als 14:00 heraus. Seit Fund 2 wird fuer die Anzeige in die
    # Anzeigezone umgerechnet, und damit WAERE aus 14:00 in Berlin 16:00
    # geworden: aus einem stillen Fehler ein sichtbarer. WARUM UTC falsch
    # ist: die Norm sagt "Zeit des Betrachters", und das ist genau die
    # Anzeigezone - nicht UTC. (Verknuepfungspruefung 31.08.2026, Fund 2
    # nennt diese Zeile ausdruecklich mit.)
    return _mit_zone(roh, zone), False


# --- Zerlegen ---------------------------------------------------------------


def _teile(zeile: str) -> tuple[str, dict[str, str], str]:
    """`DTSTART;TZID=Europe/Berlin:20260827T140000` -> Name, Parameter, Wert.

    Der Doppelpunkt trennt; in TEXT-Werten wird er nicht maskiert
    (Abschnitt 3.3.11), aber er kann in einem Parameterwert in
    Anfuehrungszeichen stehen - deshalb wird von links gesucht und dabei
    auf Anfuehrungszeichen geachtet.
    """
    in_zitat = False
    for i, z in enumerate(zeile):
        if z == '"':
            in_zitat = not in_zitat
        elif z == ":" and not in_zitat:
            kopf, wert = zeile[:i], zeile[i + 1:]
            break
    else:
        return "", {}, ""

    stuecke = kopf.split(";")
    name = stuecke[0].strip().upper()
    params: dict[str, str] = {}
    for s in stuecke[1:]:
        if "=" in s:
            k, v = s.split("=", 1)
            params[k.strip().upper()] = v.strip().strip('"')
    return name, params, wert


def parse(roh: str, *, kalendername: str = "", zone=None) -> tuple[list[Termin], int, int]:
    """Alle VEVENTs. Gibt (Termine, wiederkehrende, unlesbare) zurueck.

    Wiederkehrende werden **gezaehlt und weggelassen**, nicht geraten.

    WAS WAR FALSCH (Verknuepfungspruefung 31.08.2026, Fund 1): dasselbe
    Versprechen galt fuer unlesbare VEVENTs NICHT. Ein VEVENT ohne DTSTART
    oder mit einer DTSTART-Form, die `lies_zeit` nicht kennt, gab in
    `_baue` `None` zurueck und wurde in der Schleife hier still
    uebersprungen - kein Zaehler, kein Log. Die Antwort sagte dann
    "N Termine" mit einem zu niedrigen N.
    WARUM DAS FALSCH IST: ein Kalender, der einen Termin verschweigt, ist
    schlechter als keiner, und der Nutzer hat keinen Anhaltspunkt, dass
    etwas fehlt. Genau deshalb werden Wiederkehrende zwei Zeilen weiter
    unten gezaehlt und nach oben gereicht. api/weltlage.py:100-108 macht es
    fuer unlesbare Meldungen schon so. Ab jetzt gilt hier dieselbe Regel:
    weglassen ja, verschweigen nein.
    """
    termine: list[Termin] = []
    wiederkehrend = 0
    unlesbar = 0
    name_des_kalenders = kalendername

    aktuell: dict | None = None
    for zeile in entfalte(roh):
        name, params, wert = _teile(zeile)
        if not name:
            continue

        if name == "BEGIN" and wert.strip().upper() == "VEVENT":
            aktuell = {}
            continue
        if name == "END" and wert.strip().upper() == "VEVENT":
            if aktuell is not None:
                if aktuell.get("rrule"):
                    wiederkehrend += 1
                else:
                    fertig = _baue(aktuell, name_des_kalenders, zone)
                    if fertig is not None:
                        termine.append(fertig)
                    else:
                        unlesbar += 1
            aktuell = None
            continue

        if aktuell is None:
            # Ausserhalb eines VEVENT: nur der Kalendername interessiert.
            if name == "X-WR-CALNAME" and not kalendername:
                name_des_kalenders = entschluessele(wert).strip()
            continue

        if name == "SUMMARY":
            aktuell["titel"] = entschluessele(wert).strip()
        elif name == "LOCATION":
            aktuell["ort"] = entschluessele(wert).strip()
        elif name == "DTSTART":
            aktuell["beginn"] = (wert, params)
        elif name == "DTEND":
            aktuell["ende"] = (wert, params)
        elif name == "RRULE":
            aktuell["rrule"] = wert.strip()
        # DESCRIPTION wird bewusst nicht gelesen: dort stehen Meeting-Links,
        # Zugangscodes und gelegentlich Passwoerter. Wenn Noah sie braucht,
        # wird das ein eigener Parameter, der ausdruecklich gesetzt werden
        # muss (FIX-07 Abschnitt 4.3).
    return termine, wiederkehrend, unlesbar


def _baue(roh: dict, kalendername: str, zone=None) -> Termin | None:
    """`None` heisst: dieses VEVENT ist nicht lesbar.

    Der Aufrufer MUSS das zaehlen (siehe `parse`). Das Log hier nennt den
    Titel, damit die Ursachensuche nicht bei "irgendein Termin" anfaengt.
    """
    if "beginn" not in roh:
        log.warning("Kalender: VEVENT %r ohne DTSTART, wird weggelassen.",
                    roh.get("titel", "(ohne Titel)"))
        return None
    try:
        beginn, ganztaegig = lies_zeit(*roh["beginn"], zone)
    except (KalenderFehler, ValueError) as exc:
        log.warning("Kalender: DTSTART von %r nicht lesbar (%s), wird "
                    "weggelassen.", roh.get("titel", "(ohne Titel)"), exc)
        return None

    if "ende" in roh:
        try:
            ende, _ = lies_zeit(*roh["ende"], zone)
        except (KalenderFehler, ValueError):
            ende = beginn
    elif ganztaegig:
        # RFC 5545, 3.6.1: DATE ohne DTEND/DURATION -> ein Tag.
        ende = beginn + timedelta(days=1)
    else:
        # DATE-TIME ohne DTEND -> selber Zeitpunkt.
        ende = beginn

    return Termin(
        titel=roh.get("titel", "").strip() or "(ohne Titel)",
        beginn=beginn,
        ende=ende,
        ganztaegig=ganztaegig,
        ort=roh.get("ort", ""),
        kalender=kalendername,
    )


# --- Zeitfenster ------------------------------------------------------------


def _als_utc(x: datetime | date, zone=None) -> datetime:
    """Vergleichbar machen. Ein Ganztagstermin (`date`) hat keine Uhrzeit -
    sein Tag beginnt dort, wo der Betrachter steht, also in der Anzeigezone
    und nicht in UTC. Sonst waere er im Fenster um den Zonenversatz
    verschoben, genau wie die Fenstergrenzen es vor Fund 3 waren."""
    if isinstance(x, datetime):
        return x if x.tzinfo else _mit_zone(x, zone)
    return _mit_zone(datetime(x.year, x.month, x.day), zone)


def im_fenster(termine: list[Termin], von: date, bis: date, *, zone=None) -> list[Termin]:
    """Alles, was das Fenster beruehrt. `DTEND` ist nicht einschliessend
    (RFC 5545, 3.6.1) - ein Termin, der genau bei `von` endet, zaehlt
    deshalb nicht mehr dazu.

    WAS WAR FALSCH (Verknuepfungspruefung 31.08.2026, Fund 3): hier stand
    `datetime(von.year, von.month, von.day, tzinfo=timezone.utc)`. `von`
    und `bis` sind aber Ortsdaten - sie kommen aus `date.today()` oder aus
    dem, was das Modell vom `clock`-Werkzeug bekommen hat, und das ist
    Ortszeit (core/tools/builtin.py:51). Aus einem Ortsdatum wurde so ein
    UTC-Fenster: fuer Europe/Berlin lag es im Sommer zwei Stunden, im
    Winter eine hinter dem, was der Nutzer "heute" nennt.
    WARUM DAS FALSCH IST: auf "was habe ich heute vor" fiel ein Termin
    zwischen 00:00 und 02:00 Ortszeit stillschweigend aus der Antwort, und
    einer von morgen frueh wurde als heute gemeldet - ohne jede Warnung.
    Jetzt ist Mitternacht Mitternacht IN der Anzeigezone, also aus
    derselben Quelle wie das Datum selbst."""
    # Erst den Tag rechnen, DANN die Zone dranhaengen. Andersherum
    # (`+ timedelta(days=1)` auf einen fertigen Zeitpunkt) haette an einem
    # Zeitumstellungswochenende den alten Versatz mitgeschleppt.
    a = _mit_zone(datetime(von.year, von.month, von.day), zone)
    b = _mit_zone(datetime(bis.year, bis.month, bis.day) + timedelta(days=1), zone)
    treffer = [
        t for t in termine
        if _als_utc(t.beginn, zone) < b and _als_utc(t.ende, zone) > a
    ]
    return sorted(treffer, key=lambda t: _als_utc(t.beginn, zone))


# --- Quelle holen -----------------------------------------------------------


def cache_datei(db_path) -> Path:
    return Path(db_path).parent / "kalender" / "quelle.ics"


async def hole(quelle: str, *, db_path, jetzt: float | None = None) -> tuple[str, bool]:
    """Gibt (ICS-Text, aus_dem_cache) zurueck.

    Ein Dateipfad wird direkt gelesen - dort gibt es nichts zu cachen. Eine
    `https://`-Adresse wird geholt und zwischengespeichert; der Cache
    verhaelt sich wie der TLE-Cache in `core/satellite/ueberflug.py`:
    innerhalb von `HOECHSTALTER_S` wird gar nicht erst gefragt, und wenn
    der Abruf scheitert, ist ein alter Stand besser als gar keiner.
    """
    quelle = (quelle or "").strip()
    if not quelle:
        raise KalenderFehler(
            "Keine Kalenderquelle eingetragen: KALENDER_QUELLE fehlt in der "
            ".env. Das heisst NICHT, dass du keine Termine hast - ich weiss "
            "es nur nicht."
        )

    if not quelle.lower().startswith(("http://", "https://")):
        p = Path(quelle).expanduser()
        if not p.is_file():
            raise KalenderFehler("Die Kalenderdatei gibt es nicht.")
        return p.read_text(encoding="utf-8", errors="replace"), False

    from core.netz import nach_draussen

    datei = cache_datei(db_path)
    uhr = time.time() if jetzt is None else jetzt
    if datei.is_file() and (uhr - datei.stat().st_mtime) < HOECHSTALTER_S:
        return datei.read_text(encoding="utf-8", errors="replace"), True

    try:
        # `nach_draussen` ist die Klientenfabrik des Projekts: sie haengt
        # niemals Anmeldedaten an und folgt bewusst KEINER Weiterleitung
        # (FIX-03 Schritt 2 Punkt 4). Beides zaehlt hier doppelt, denn bei
        # einem ICS-Abo IST die Adresse das Geheimnis - eine Weiterleitung
        # auf einen fremden Host wuerde sie dorthin mitnehmen.
        async with nach_draussen(timeout=20.0) as client:
            antwort = await client.get(quelle)
        if antwort.is_redirect:
            raise KalenderFehler(
                "Die Adresse leitet weiter. Dem folge ich nicht - bei einem "
                "Kalender-Abo ist die Adresse selbst das Geheimnis. Trag die "
                "endgueltige Adresse ein."
            )
        antwort.raise_for_status()
        text = antwort.text
    except KalenderFehler:
        raise
    except Exception as exc:                       # noqa: BLE001
        # NIEMALS `exc` in den Text der Ausnahme. httpx haengt die volle URL
        # an seine Fehlermeldung:
        #
        #   Client error '404 Not Found' for url
        #   'https://calendar.google.com/calendar/ical/<GEHEIM>/basic.ics'
        #
        # Und diese Adresse IST das Geheimnis - drei Zeilen weiter oben steht
        # genau deshalb, dass wir Weiterleitungen nicht folgen. Der Text
        # dieser Ausnahme wird zum ToolResult.error, landet im Prompt und
        # geht damit an den Modellanbieter. Wer den Kalender-Link hat,
        # sieht den ganzen Kalender - ohne jede Anmeldung.
        #
        # Gefunden am 31.08.2026, von zwei Pruefern unabhaengig, und mit
        # einem echten httpx-404 nachgestellt.
        #
        # Ins LOG darf der Grund, dort steht die URL ohnehin nicht drin.
        if datei.is_file():
            log.warning("Kalender: Abruf gescheitert (%s), nehme den Cache.",
                        type(exc).__name__)
            return datei.read_text(encoding="utf-8", errors="replace"), True
        status = getattr(getattr(exc, "response", None), "status_code", None)
        log.warning("Kalender: Abruf gescheitert (%s)", type(exc).__name__)
        raise KalenderFehler(
            "Kalender nicht erreichbar"
            + (f" (HTTP {status})" if status else f" ({type(exc).__name__})")
            + ". Die Adresse steht absichtlich nicht in dieser Meldung - sie "
            "ist das Geheimnis. Pruefe KALENDER_QUELLE in der .env."
        ) from exc

    if "BEGIN:VCALENDAR" not in text:
        # Ein Abo, das eine Anmeldeseite ausliefert, kommt als HTTP 200.
        # Derselbe Fall wie CelesTrak mit "Invalid query" - deshalb dieselbe
        # Vorsicht: Inhalt pruefen, nicht nur den Status.
        raise KalenderFehler(
            "Die Adresse liefert kein iCalendar. Ist es wirklich die "
            "ICS-Abo-Adresse und nicht die Web-Ansicht des Kalenders?"
        )

    datei.parent.mkdir(parents=True, exist_ok=True)
    datei.write_text(text, encoding="utf-8")
    return text, False
