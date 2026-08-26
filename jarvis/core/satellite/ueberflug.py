"""Satellitenüberflüge aus echten Bahndaten (PHASE-08, DoD 5).

Gerechnet wird mit `skyfield` aus TLE-Sätzen von CelesTrak - nicht
geschätzt, nicht interpoliert, nicht aus dem Gedächtnis eines Modells.
Für jeden Punkt der Erde: `lat`/`lon` sind frei, die Rechnung kennt keine
Landesgrenzen.

**Stack-Änderung, ausdrücklich freigegeben.** `CLAUDE.md` legt den Stack
fest und `skyfield` stand nicht darin. Noah hat es am 26.08.2026 zugesagt.
Es zieht `numpy`, `sgp4` und `jplephem` mit - das ist der Preis, und er
steht in `requirements.txt` dabei.

Was hier **nicht** gerechnet wird: ob der Überflug mit bloßem Auge
**sichtbar** ist. Das verlangt zusätzlich, dass der Satellit von der Sonne
beschienen wird und es am Boden dunkel ist - und dafür braucht skyfield
eine Ephemeriden-Datei (`de421.bsp`, rund 16 MB Download). Die Geometrie
unten ist exakt; die Sichtbarkeit wird nicht behauptet, sondern
weggelassen. Das steht auch im Ergebnis.

CelesTrak-Regeln, aus deren eigener Dokumentation und hier eingebaut:

* "CelesTrak only checks for new GP data once every 2 hours, so there is
  no need for you to check more often." -> `TLE_HOECHSTALTER_S`
* Bei HTTP-Fehlern aufhören und melden, nicht weiter anfragen.
* Eine ungültige Gruppe kommt als **HTTP 200** mit dem Text
  `Invalid query: ...` zurück - gemessen. Der Status allein genügt also
  nicht, der Inhalt muss geprüft werden.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

log = logging.getLogger("jarvis")

CELESTRAK_URL = "https://celestrak.org/NORAD/elements/gp.php"

# Gemessen am 26.08.2026: visual 157 Satelliten, stations 21.
# `active` gibt es auch - rund 10.000 Objekte, und CelesTrak bittet
# ausdruecklich um "one download per update" dafuer. Deshalb nicht drin.
GRUPPEN = {
    "visual": "Die mit blossem Auge sichtbaren, rund 157 Objekte.",
    "stations": "Raumstationen und was an ihnen haengt, rund 21 Objekte.",
}
STANDARDGRUPPE = "visual"

# CelesTrak prueft selbst nur alle 2 Stunden auf neue Daten. Oefter zu
# fragen bringt nichts und faellt bei ihnen als Last auf.
TLE_HOECHSTALTER_S = 2 * 3600

# Ein TLE altert. Die SGP4-Bahnvorhersage ist um die Epoche herum genau und
# wird mit den Tagen schlechter. Ab hier wird es dazugesagt.
TLE_WARNT_AB_TAGEN = 7.0

# Unter dieser Hoehe steht der Satellit praktisch im Horizont: Haeuser,
# Baeume, Berge. 10 Grad ist die uebliche Schwelle.
MINDESTHOEHE_GRAD = 10.0

HIMMELSRICHTUNGEN = (
    "N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO",
    "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
)


class UeberflugFehler(RuntimeError):
    pass


def himmelsrichtung(azimut_grad: float) -> str:
    """Aus 237.5 wird WSW. Ein Azimut sagt niemandem, wohin er schauen soll."""
    schritt = 360.0 / len(HIMMELSRICHTUNGEN)
    index = int((azimut_grad % 360.0) / schritt + 0.5) % len(HIMMELSRICHTUNGEN)
    return HIMMELSRICHTUNGEN[index]


@dataclass(frozen=True)
class Ueberflug:
    name: str
    norad: int
    aufgang: datetime
    hoechststand: datetime
    untergang: datetime
    max_hoehe_grad: float
    von: str                  # Himmelsrichtung des Aufgangs
    nach: str                 # Himmelsrichtung des Untergangs
    min_entfernung_km: float
    tle_alter_tage: float

    @property
    def dauer_s(self) -> int:
        return int((self.untergang - self.aufgang).total_seconds())

    def steckbrief(self) -> str:
        alt = (
            f" (Bahndaten {self.tle_alter_tage:.1f} Tage alt - die Vorhersage "
            f"wird damit ungenauer)"
            if self.tle_alter_tage > TLE_WARNT_AB_TAGEN else ""
        )
        return (
            f"{self.name} (NORAD {self.norad})\n"
            f"  {self.aufgang:%Y-%m-%d %H:%M:%S} UTC Aufgang im {self.von}\n"
            f"  {self.hoechststand:%H:%M:%S} UTC hoechster Stand "
            f"{self.max_hoehe_grad:.0f} Grad, {self.min_entfernung_km:.0f} km\n"
            f"  {self.untergang:%H:%M:%S} UTC Untergang im {self.nach}\n"
            f"  Dauer {self.dauer_s // 60} min {self.dauer_s % 60} s{alt}"
        )

    def als_dict(self) -> dict:
        return {
            "name": self.name,
            "norad": self.norad,
            "aufgang": self.aufgang.isoformat(),
            "hoechststand": self.hoechststand.isoformat(),
            "untergang": self.untergang.isoformat(),
            "max_hoehe_grad": round(self.max_hoehe_grad, 1),
            "von": self.von,
            "nach": self.nach,
            "min_entfernung_km": round(self.min_entfernung_km, 1),
            "dauer_s": self.dauer_s,
            "tle_alter_tage": round(self.tle_alter_tage, 2),
        }


# --- TLE holen und lesen --------------------------------------------------


def parse_tle(text: str) -> list[tuple[str, str, str]]:
    """Aus dem 3LE-Text eine Liste (Name, Zeile1, Zeile2).

    Eine ungueltige Gruppe kommt bei CelesTrak als HTTP 200 mit dem Text
    `Invalid query: ...` zurueck - gemessen am 26.08.2026. Wer nur den
    Status prueft, legt diesen Satz als Bahndaten ab.
    """
    inhalt = (text or "").strip()
    if not inhalt:
        raise UeberflugFehler("Keine Bahndaten erhalten (leere Antwort).")
    if inhalt.lower().startswith("invalid query"):
        raise UeberflugFehler(f"CelesTrak hat die Anfrage abgelehnt: {inhalt}")

    zeilen = [z.rstrip() for z in inhalt.splitlines() if z.strip()]
    satelliten: list[tuple[str, str, str]] = []
    i = 0
    while i + 2 < len(zeilen) + 1:
        if i + 2 >= len(zeilen) + 0:
            break
        name, l1, l2 = zeilen[i], zeilen[i + 1], zeilen[i + 2]
        if not (l1.startswith("1 ") and l2.startswith("2 ")):
            # Kein sauberer Dreierblock - lieber diesen ueberspringen als
            # zwei Satelliten durcheinanderzubringen.
            i += 1
            continue
        satelliten.append((name.strip(), l1, l2))
        i += 3
    if not satelliten:
        raise UeberflugFehler(
            "In der Antwort stand kein einziger vollstaendiger TLE-Satz."
        )
    return satelliten


def cache_datei(gruppe: str, *, db_path: Path | str) -> Path:
    return Path(db_path).parent / "tle" / f"{gruppe}.tle"


async def hole_tle(
    gruppe: str = STANDARDGRUPPE,
    *,
    db_path: Path | str,
    transport: httpx.AsyncBaseTransport | None = None,
    jetzt: float | None = None,
) -> tuple[str, bool]:
    """Bahndaten der Gruppe, aus dem Cache oder frisch.

    Gibt (Text, war_frisch_geholt) zurueck. Der Cache ist keine Optimierung,
    sondern eine Auflage: CelesTrak prueft selbst nur alle zwei Stunden auf
    neue Daten und sperrt IPs, die dauernd anfragen.
    """
    if gruppe not in GRUPPEN:
        raise UeberflugFehler(
            f"Unbekannte Gruppe {gruppe!r}. Bekannt: "
            f"{', '.join(sorted(GRUPPEN))}."
        )
    datei = cache_datei(gruppe, db_path=db_path)
    uhr = time.time() if jetzt is None else jetzt
    if datei.is_file() and (uhr - datei.stat().st_mtime) < TLE_HOECHSTALTER_S:
        return datei.read_text(encoding="utf-8"), False

    async with httpx.AsyncClient(timeout=30.0, transport=transport) as client:
        antwort = await client.get(
            CELESTRAK_URL, params={"GROUP": gruppe, "FORMAT": "tle"}
        )
    if antwort.status_code >= 400:
        # CelesTrak bittet ausdruecklich darum, bei Fehlern aufzuhoeren und
        # es einem Menschen zu melden, statt weiter anzufragen.
        if datei.is_file():
            log.warning(
                "CelesTrak antwortete mit HTTP %s - es wird der alte "
                "Cachestand benutzt.", antwort.status_code,
            )
            return datei.read_text(encoding="utf-8"), False
        raise UeberflugFehler(
            f"CelesTrak antwortete mit HTTP {antwort.status_code}. "
            "Es wird nicht erneut angefragt."
        )

    text = antwort.text
    parse_tle(text)          # wirft, wenn es keine Bahndaten sind
    datei.parent.mkdir(parents=True, exist_ok=True)
    vorlaeufig = datei.with_suffix(".teil")
    vorlaeufig.write_text(text, encoding="utf-8")
    vorlaeufig.replace(datei)
    log.info("Bahndaten %r frisch geholt (%d Zeichen).", gruppe, len(text))
    return text, True


# --- Rechnen --------------------------------------------------------------


def ueberfluege(
    satelliten: list[tuple[str, str, str]],
    *,
    lat: float,
    lon: float,
    hoehe_m: float = 0.0,
    von: datetime,
    bis: datetime,
    mindesthoehe_grad: float = MINDESTHOEHE_GRAD,
    hoechstens: int = 20,
) -> list[Ueberflug]:
    """Alle Ueberfluege im Zeitfenster, nach Aufgang sortiert.

    Fuer jeden Punkt der Erde. `lat` und `lon` sind frei - die Rechnung
    kennt keine Landesgrenzen.
    """
    # Spaet importiert: skyfield zieht numpy mit, und das kostet beim Start
    # rund eine Sekunde. Wer nie nach Ueberfluegen fragt, soll sie nicht
    # bezahlen.
    from skyfield.api import EarthSatellite, load, wgs84

    if not -90.0 <= lat <= 90.0:
        raise UeberflugFehler(f"Breite {lat} liegt ausserhalb -90..90.")
    if not -180.0 <= lon <= 180.0:
        raise UeberflugFehler(f"Laenge {lon} liegt ausserhalb -180..180.")
    if bis <= von:
        raise UeberflugFehler("Das Zeitfenster endet vor seinem Anfang.")

    # builtin=True ist die Vorgabe: keine Datei, kein Download. Geprueft -
    # sonst wuerde `pytest` am Netzverbot scheitern.
    ts = load.timescale()
    ort = wgs84.latlon(lat, lon, elevation_m=hoehe_m)
    t0, t1 = ts.from_datetime(von), ts.from_datetime(bis)

    gefunden: list[Ueberflug] = []
    for name, l1, l2 in satelliten:
        try:
            sat = EarthSatellite(l1, l2, name, ts)
            zeiten, ereignisse = sat.find_events(
                ort, t0, t1, altitude_degrees=mindesthoehe_grad
            )
        except Exception as exc:  # noqa: BLE001
            # Verteidigend, und ehrlich gesagt bisher unerreicht:
            # gemessen wirft weder EarthSatellite noch find_events bei
            # kaputten TLE-Daten - es kommt still ein Satellit mit
            # satnum 640000 und null Ereignissen heraus. Die Mutation
            # 'except ZeroDivisionError' ueberlebt deshalb, und das ist
            # kein Testloch, sondern der Befund. Der Zweig bleibt, damit
            # ein Satz von 157 nicht die ganze Antwort kippt, falls die
            # Bibliothek das eines Tages doch meldet.
            log.warning("Bahndaten von %r unbrauchbar: %s", name, exc)
            continue

        alter = abs((von - sat.epoch.utc_datetime()).total_seconds()) / 86400.0
        # find_events liefert 0=Aufgang, 1=Hoechststand, 2=Untergang. Am Rand
        # des Fensters kann ein Dreierblock unvollstaendig sein - der wird
        # uebersprungen, nicht geraten.
        i = 0
        folge = list(ereignisse)
        while i + 2 < len(folge) + 1:
            if i + 2 >= len(folge):
                break
            if (folge[i], folge[i + 1], folge[i + 2]) != (0, 1, 2):
                i += 1
                continue
            t_auf, t_hoch, t_unter = zeiten[i], zeiten[i + 1], zeiten[i + 2]
            hoch_alt, _, hoch_entf = (sat - ort).at(t_hoch).altaz()
            _, auf_az, _ = (sat - ort).at(t_auf).altaz()
            _, unter_az, _ = (sat - ort).at(t_unter).altaz()
            gefunden.append(Ueberflug(
                name=name,
                norad=int(sat.model.satnum),
                aufgang=t_auf.utc_datetime().replace(microsecond=0),
                hoechststand=t_hoch.utc_datetime().replace(microsecond=0),
                untergang=t_unter.utc_datetime().replace(microsecond=0),
                max_hoehe_grad=float(hoch_alt.degrees),
                von=himmelsrichtung(float(auf_az.degrees)),
                nach=himmelsrichtung(float(unter_az.degrees)),
                min_entfernung_km=float(hoch_entf.km),
                tle_alter_tage=alter,
            ))
            i += 3

    gefunden.sort(key=lambda u: u.aufgang)
    return gefunden[:hoechstens]


def jetzt_utc() -> datetime:
    return datetime.now(timezone.utc)


def fenster(stunden: int = 24) -> tuple[datetime, datetime]:
    a = jetzt_utc()
    return a, a + timedelta(hours=stunden)
