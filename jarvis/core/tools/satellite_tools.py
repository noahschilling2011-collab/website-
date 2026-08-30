"""Werkzeuge des Satellite Agents (Phase 8).

Alles hier ist READ. Der Agent liest oeffentliche Daten und behauptet nichts,
was seine Bodenaufloesung nicht hergibt.

**Nicht gebaut:** ein Geocoder. Die Werkzeuge nehmen eine Bounding Box in
Grad, keinen Ortsnamen. Einen Ortsnamen in Koordinaten aufzuloesen ist ein
eigener Dienst mit eigenen Nutzungsbedingungen; ihn aus dem Gedaechtnis zu
erfinden waere genau der Fehler, den Regel 1 verbietet.
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from dataclasses import replace
from pathlib import Path

from core.contracts import Permission, Tool, ToolResult
from core.satellite.analysis import grenzsatz, vergleichbar, vergleiche_raster
from core.orte import OrtFehler, aus_tabelle, bbox_um, finde_ort
from core.satellite.bilder import BildFehler
from core.satellite.bilder import speichere as speichere_bild
from core.satellite.ueberflug import (
    MINDESTHOEHE_GRAD,
    STANDARDGRUPPE,
    UeberflugFehler,
    hole_tle,
    parse_tle,
    ueberfluege,
)
from core.satellite.cdse import (
    CDSEFehler,
    CDSEProvider,
    effektive_aufloesung_m,
)
from core.tools.registry import register

log = logging.getLogger("jarvis")

# Kantenlaenge des gerenderten Bildes. 512 ist der Kompromiss:
# gross genug, um etwas zu erkennen, klein genug, dass das
# Processing-Unit-Kontingent (10.000/Monat) nicht auffaellt.
BILD_KANTE = 512
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

BBOX_SCHEMA = {
    "type": "array",
    "description": (
        "Bounding Box in Grad: [min_lon, min_lat, max_lon, max_lat]. "
        "Ortsnamen kann ich nicht aufloesen - gib Koordinaten."
    ),
    "items": {"type": "number"},
}


def _bbox(werte) -> tuple[float, float, float, float]:
    if not isinstance(werte, list) or len(werte) != 4:
        raise ValueError("bbox braucht genau vier Zahlen.")
    min_lon, min_lat, max_lon, max_lat = (float(w) for w in werte)
    if not (-180 <= min_lon < max_lon <= 180 and -90 <= min_lat < max_lat <= 90):
        raise ValueError(
            "bbox ist ungueltig: erwartet [min_lon, min_lat, max_lon, max_lat] "
            "mit min < max."
        )
    return (min_lon, min_lat, max_lon, max_lat)


@register
class SatelliteSearch(Tool):
    name = "satellite_search"
    description = (
        "Sucht die juengste wolkenarme Sentinel-2-Szene zu einer bbox und liefert ein anzeigbares Bild.\n"
        "Nimm es fuer: wie ein Ort von oben aussieht; \"aktuell\" heisst juengste Szene unter dem Wolken-Schwellwert, Live-Bilder gibt es nicht. Du brauchst dafuer eine bbox, die liefert dir find_place. Dabei fallen je Szene acquired_at, cloud_cover_pct und resolution_m an - genau diese drei nimmt satellite_compare; NDVI-Werte fallen hier NICHT an.\n"
        "Nimm es NICHT fuer: wann ein Satellit ueber den Ort hinwegfliegt, das macht satellite_passes. Als Bildaufloesung nennst du bild_aufloesung_m aus dem Ergebnis - bei grossem Ausschnitt ueber 1000 m je Pixel -, nie die 10 m des Sensors und nie als resolution_m fuer satellite_compare.\n"
        "Beispiel: satellite_search(bbox=[9.74, 48.75, 9.90, 48.86], days_back=30, max_cloud_pct=20)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "bbox": BBOX_SCHEMA,
            "days_back": {
                "type": "integer",
                "description": "Wie weit zurueck gesucht wird, 1 bis 365.",
                "minimum": 1,
                "maximum": 365,
            },
            "max_cloud_pct": {
                "type": "number",
                "description": "Hoechster erlaubter Wolkenanteil in Prozent.",
                "minimum": 0,
                "maximum": 100,
            },
        },
        "required": ["bbox"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 60

    provider: CDSEProvider | None = None
    # Wird beim Start gesetzt, wie bei remember/recall.
    db_path: Path = PROJECT_ROOT / "data" / "jarvis.db"

    async def execute(
        self, bbox, days_back: int = 30, max_cloud_pct: float = 20.0
    ) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            box = _bbox(bbox)
        except ValueError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        if self.provider is None or not self.provider.eingerichtet:
            return ToolResult(
                ok=False,
                error="CDSE nicht eingerichtet.",
                display=(
                    "Satellitensuche nicht eingerichtet: CDSE_CLIENT_ID und "
                    "CDSE_CLIENT_SECRET fehlen in der .env. Ein Konto gibt es "
                    "kostenlos auf dataspace.copernicus.eu."
                ),
                duration_ms=dauer(),
            )

        ende = datetime.now(timezone.utc)
        start = ende - timedelta(days=days_back)
        try:
            szenen = await self.provider.search(
                box, start, ende, max_cloud_pct=max_cloud_pct
            )
        except CDSEFehler as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        if not szenen:
            # DoD 2: sagen, dass nichts da ist - und nicht ersatzweise ein
            # wolkiges Bild ohne Hinweis liefern.
            return ToolResult(
                ok=True,
                data={"scenes": [], "max_cloud_pct": max_cloud_pct,
                      "days_back": days_back},
                display=(
                    f"Kein Sentinel-2-Bild unter {max_cloud_pct:.0f} % Wolken in "
                    f"den letzten {days_back} Tagen fuer diesen Ausschnitt.\n\n"
                    "Das ist kein Fehler: Sentinel-2 ueberfliegt einen Ort alle "
                    "3 bis 5 Tage, und in Mitteleuropa ist ein grosser Teil der "
                    "Aufnahmen bewoelkt. Moeglichkeiten: Suchfenster "
                    "vergroessern oder den Wolken-Schwellwert anheben - dann "
                    "aber mit dem Hinweis, dass das Bild bewoelkt ist."
                ),
                duration_ms=dauer(),
            )

        # --- Das Bild -----------------------------------------------------
        #
        # Bis hierher war das hier ein Metadatendienst: preview_url stand
        # fest auf None. Jetzt wird die juengste Szene wirklich gerendert.
        #
        # Die Bildaufloesung ist NICHT die des Sensors. Sentinel-2 liefert
        # 10 m/px - ein 512-Pixel-Bild von ganz Deutschland hat rund 1,7 km
        # je Pixel. Der Grenzsatz unten muss sich auf DIESE Zahl stuetzen,
        # sonst sagt er dem Modell, es koenne Dinge sehen, die auf dem Bild
        # ein Zehntel Pixel gross sind.
        juengste = szenen[0]
        bild_m = effektive_aufloesung_m(box, BILD_KANTE, BILD_KANTE)
        bild_pfad: str | None = None
        bild_notiz = ""
        try:
            tag = juengste.acquired_at.strftime("%Y-%m-%d")
            morgen = (juengste.acquired_at + timedelta(days=1)).strftime("%Y-%m-%d")
            rohbild = await self.provider.render(
                box,
                f"{tag}T00:00:00Z",
                f"{morgen}T00:00:00Z",
                breite=BILD_KANTE,
                hoehe=BILD_KANTE,
            )
            kennung = speichere_bild(rohbild, db_path=self.db_path)
            bild_pfad = f"/api/bild/{kennung}"
            juengste = replace(juengste, preview_url=bild_pfad)
        except (CDSEFehler, BildFehler, OSError) as exc:
            # Kein Grund, den ganzen Aufruf scheitern zu lassen: die
            # Metadaten sind da und sind etwas wert. Aber es wird gesagt.
            log.warning("Satellitenbild nicht gerendert: %s", exc)
            bild_notiz = f"\n\nKein Bild gerendert: {exc}"

        zeilen = [s.steckbrief() for s in szenen[:5]]
        daten = [s.als_dict() for s in szenen[:5]]
        if bild_pfad:
            daten[0]["preview_url"] = bild_pfad
        return ToolResult(
            ok=True,
            data={
                "scenes": daten,
                "preview_url": bild_pfad,
                "bild_aufloesung_m": round(bild_m, 1),
                "bild_kante_px": BILD_KANTE,
                "attribution": juengste.attribution,
            },
            display=(
                f"{len(szenen)} Szene(n) gefunden, juengste zuerst:\n\n"
                + "\n\n".join(zeilen)
                + (
                    f"\n\nBild: {BILD_KANTE}x{BILD_KANTE} Pixel fuer diesen "
                    f"Ausschnitt, das sind {bild_m:.0f} m je Bildpixel "
                    f"(der Sensor liefert {juengste.resolution_m:.0f} m - "
                    f"feiner als das Bild wird es dadurch nicht).\n"
                    f"{juengste.attribution}."
                    if bild_pfad else ""
                )
                + f"\n\n{grenzsatz(bild_m if bild_pfad else juengste.resolution_m)}"
                + bild_notiz
            ),
            sources=["https://dataspace.copernicus.eu/"],
            duration_ms=dauer(),
        )


@register
class SatelliteCompare(Tool):
    name = "satellite_compare"
    description = (
        "Vergleicht zwei NDVI-Raster desselben Ausschnitts und meldet die veraenderte Flaeche in Hektar.\n"
        "Nimm es fuer: wie viel Gruen zwischen zwei Aufnahmen verschwunden ist - erst rechnen, dann deuten. before und after sind die NDVI-Werte selbst und muessen aus einer echten Rasterquelle stammen. Von satellite_search kommen before_date/after_date (acquired_at), before_cloud_pct/after_cloud_pct (cloud_cover_pct) und resolution_m der Szene.\n"
        "Nimm es NICHT fuer: das Bild eines einzelnen Zeitpunkts, das macht satellite_search. KEIN Werkzeug liefert dir heute NDVI-Werte - hast du keine aus einer echten Quelle, rufst du dieses Werkzeug GAR NICHT auf, sondern sagst, dass die Rasterdaten fehlen; die Platzhalter im Beispiel denkst du dir NIE als Zahlen aus. Setze als resolution_m nie bild_aufloesung_m des Vorschaubilds ein - sonst stimmen die Hektar um Groessenordnungen nicht. Zu weit im Jahreslauf auseinander, und es lehnt ab - man saehe die Jahreszeit.\n"
        "Beispiel: satellite_compare(before=<NDVI-Werte der aelteren Aufnahme>, after=<NDVI-Werte der juengeren>, before_date=\"2020-07-14\", after_date=\"2024-07-09\", resolution_m=10)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "before": {"type": "array", "items": {"type": "number"},
                       "description": "NDVI-Werte der aelteren Aufnahme."},
            "after": {"type": "array", "items": {"type": "number"},
                      "description": "NDVI-Werte der juengeren Aufnahme."},
            "before_date": {"type": "string", "description": "ISO-Datum, aeltere Aufnahme."},
            "after_date": {"type": "string", "description": "ISO-Datum, juengere Aufnahme."},
            "before_cloud_pct": {"type": "number", "minimum": 0, "maximum": 100},
            "after_cloud_pct": {"type": "number", "minimum": 0, "maximum": 100},
            "resolution_m": {"type": "number", "description": "Meter je Pixel.",
                             "minimum": 0.1},
        },
        "required": ["before", "after", "before_date", "after_date"],
        "additionalProperties": False,
    }
    permission = Permission.READ

    async def execute(
        self,
        before: list[float],
        after: list[float],
        before_date: str,
        after_date: str,
        before_cloud_pct: float = 0.0,
        after_cloud_pct: float = 0.0,
        resolution_m: float = 10.0,
    ) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            a = datetime.fromisoformat(before_date.replace("Z", "+00:00"))
            b = datetime.fromisoformat(after_date.replace("Z", "+00:00"))
        except ValueError as exc:
            return ToolResult(ok=False, error=f"Datum unlesbar: {exc}",
                              display=f"Datum unlesbar: {exc}", duration_ms=dauer())

        passt, grund = vergleichbar(a, b, before_cloud_pct, after_cloud_pct)
        if not passt:
            # Melden, nicht rechnen (A.5, Schritt 2).
            return ToolResult(ok=False, error=grund, display=grund,
                              duration_ms=dauer())

        try:
            ergebnis = vergleiche_raster(
                list(before), list(after), aufloesung_m=resolution_m
            )
        except ValueError as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        richtung = "Rueckgang" if ergebnis.mittlere_aenderung < 0 else "Zunahme"
        return ToolResult(
            ok=True,
            data=ergebnis.als_dict(),
            display=(
                f"NDVI-{richtung} ueber dem Schwellwert auf "
                f"{ergebnis.hektar:.2f} ha ({ergebnis.veraendert_pixel} von "
                f"{ergebnis.pixel} Pixeln).\n"
                f"Mittlere Aenderung {ergebnis.mittlere_aenderung:+.3f}, "
                f"groesste Abnahme {ergebnis.groesste_abnahme:+.3f}, "
                f"groesste Zunahme {ergebnis.groesste_zunahme:+.3f}.\n"
                # Der Grenzhinweis steht VOR dem allgemeinen Grenzsatz und
                # nur dann, wenn er zutrifft. Ohne ihn liest ein Modell eine
                # Hektarzahl von 0,04 wie einen Fund - dabei ist sie kleiner
                # als das, was der Sensor aufloesen kann.
                + (f"{ergebnis.grenzhinweis()}\n" if not ergebnis.beurteilbar else "")
                + f"{grenzsatz(resolution_m)}"
            ),
            duration_ms=dauer(),
        )


@register
class SatellitePasses(Tool):
    name = "satellite_passes"
    description = (
        "Rechnet aus echten Bahndaten (TLE), welche Satelliten in den naechsten Stunden ueber einen Punkt hinwegfliegen - weltweit.\n"
        "Nimm es fuer: wann die ISS drueber ist - Aufgang, hoechster Stand, Untergang, Richtung, Entfernung. Du brauchst dafuer lat und lon, die liefert dir find_place.\n"
        "Nimm es NICHT fuer: ein Bild des Ortes von oben, das macht satellite_search. Sagt auch NICHT, ob der Ueberflug mit blossem Auge sichtbar ist.\n"
        "Beispiel: satellite_passes(lat=48.8000, lon=9.7986, hours=24, group=\"stations\")"
    )
    parameters = {
        "type": "object",
        "properties": {
            "lat": {
                "type": "number",
                "description": "Breite in Grad, -90 bis 90. Norden positiv.",
                "minimum": -90,
                "maximum": 90,
            },
            "lon": {
                "type": "number",
                "description": "Laenge in Grad, -180 bis 180. Osten positiv.",
                "minimum": -180,
                "maximum": 180,
            },
            "hours": {
                "type": "integer",
                "description": "Wie weit nach vorn geschaut wird, 1 bis 72.",
                "minimum": 1,
                "maximum": 72,
            },
            "min_elevation_deg": {
                "type": "number",
                "description": (
                    "Ab welcher Hoehe ueber dem Horizont ein Ueberflug zaehlt. "
                    "10 Grad ist ueblich - darunter stehen Haeuser und Baeume "
                    "im Weg."
                ),
                "minimum": 0,
                "maximum": 89,
            },
            "group": {
                "type": "string",
                "description": (
                    "visual = die mit blossem Auge sichtbaren (rund 157), "
                    "stations = Raumstationen (rund 21)."
                ),
                "enum": ["visual", "stations"],
            },
        },
        "required": ["lat", "lon"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 60

    db_path: Path = PROJECT_ROOT / "data" / "jarvis.db"

    async def execute(
        self,
        lat: float,
        lon: float,
        hours: int = 24,
        min_elevation_deg: float = MINDESTHOEHE_GRAD,
        group: str = STANDARDGRUPPE,
    ) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        stunden = max(1, min(int(hours), 72))
        try:
            text, frisch = await hole_tle(group, db_path=self.db_path)
            satelliten = parse_tle(text)
        except UeberflugFehler as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        von = datetime.now(timezone.utc)
        bis = von + timedelta(hours=stunden)
        try:
            # skyfield rechnet in numpy; das gehoert nicht in die
            # Ereignisschleife des Servers.
            gefunden = await asyncio.to_thread(
                ueberfluege,
                satelliten,
                lat=float(lat),
                lon=float(lon),
                von=von,
                bis=bis,
                mindesthoehe_grad=float(min_elevation_deg),
            )
        except UeberflugFehler as exc:
            return ToolResult(ok=False, error=str(exc), display=str(exc),
                              duration_ms=dauer())

        kopf = (
            f"Ort {lat:.4f}, {lon:.4f} - naechste {stunden} h, "
            f"ab {min_elevation_deg:.0f} Grad ueber dem Horizont. "
            f"{len(satelliten)} Satelliten der Gruppe {group!r} geprueft "
            f"({'frisch geholt' if frisch else 'aus dem Zwischenspeicher'})."
        )
        if not gefunden:
            # Kein Fehler. Ueber einem Pol kommt bei der ISS null heraus,
            # weil ihre Bahnneigung 51,6 Grad ist - das ist die Wahrheit.
            return ToolResult(
                ok=True,
                data={"passes": [], "geprueft": len(satelliten),
                      "gruppe": group, "stunden": stunden},
                display=(
                    f"{kopf}\n\nKein Ueberflug in diesem Zeitfenster.\n\n"
                    "Das ist kein Fehler: nicht jede Bahn kommt ueber jeden "
                    "Ort. Ueber den Polen zum Beispiel erscheint die ISS nie "
                    "- ihre Bahnneigung ist 51,6 Grad."
                ),
                duration_ms=dauer(),
            )

        return ToolResult(
            ok=True,
            data={
                "passes": [u.als_dict() for u in gefunden],
                "geprueft": len(satelliten),
                "gruppe": group,
                "stunden": stunden,
            },
            display=(
                f"{kopf}\n\n{len(gefunden)} Ueberflug(e), Zeiten in UTC:\n\n"
                + "\n\n".join(u.steckbrief() for u in gefunden)
                + "\n\nOb ein Ueberflug mit blossem Auge zu sehen ist, steht "
                "hier NICHT: dafuer muesste zusaetzlich gerechnet werden, ob "
                "der Satellit von der Sonne beschienen wird und ob es am "
                "Boden dunkel ist."
            ),
            sources=["https://celestrak.org/NORAD/elements/gp.php"],
            duration_ms=dauer(),
        )


@register
class OrtFinden(Tool):
    name = "find_place"
    description = (
        "Macht aus einem ORTSNAMEN Koordinaten und einen fertigen Ausschnitt (bbox), weltweit.\n"
        "Nimm es fuer: jeden Ortsnamen, bevor ein Satelliten-Werkzeug drankommt - rate nie Koordinaten. Dabei fallen bbox an (fuer satellite_search) und lat/lon (fuer satellite_passes).\n"
        "Nimm es NICHT fuer: Zahlen zum Ort wie Hoehe oder Gruendungsjahr, das macht wikidata; die Einwohnerzahl steht, wenn bekannt, schon hier im Ergebnis.\n"
        "Beispiel: find_place(name=\"Schwaebisch Gmuend\", kante_km=12)"
    )
    parameters = {
        "type": "object",
        "properties": {
            "name": {
                "type": "string",
                "description": "Der Ortsname, z. B. 'Schwaebisch Gmuend', "
                               "'Tokyo', 'Kilimandscharo', 'DE'.",
            },
            "kante_km": {
                "type": "number",
                "description": (
                    "Kantenlaenge des Ausschnitts in km. 12 ist die Vorgabe "
                    "und ergibt rund 23 m je Bildpixel - das Schaerfste, was "
                    "Sentinel-2 hergibt. Fuer ein ganzes Land eher 400, dann "
                    "sind es aber schon rund 800 m je Pixel."
                ),
                "minimum": 0.5,
                "maximum": 2000,
            },
        },
        "required": ["name"],
        "additionalProperties": False,
    }
    permission = Permission.READ
    timeout_s = 30

    kontakt: str = ""      # WIKI_KONTAKT, beim Start gesetzt

    async def execute(self, name: str, kante_km: float = 12.0) -> ToolResult:
        begonnen = time.monotonic()

        def dauer() -> int:
            return int((time.monotonic() - begonnen) * 1000)

        try:
            ort = await finde_ort(name, kontakt=self.kontakt)
        except OrtFehler as exc:
            # Ohne WIKI_KONTAKT geht nur die Tabelle. Das ist kein Grund,
            # gar nichts zu liefern - Laender und Hauptstaedte stehen drin.
            ort = aus_tabelle(name)
            if ort is None:
                # BEIDE Gruende nennen. "WIKI_KONTAKT fehlt" allein ist
                # irrefuehrend: der Ort steht ausserdem nicht in der
                # eingebauten Tabelle, und das waere auch mit Kontakt so.
                grund = (
                    f"{name!r} steht nicht in der eingebauten Tabelle "
                    f"(jedes Land, jede Hauptstadt), und live nachschlagen "
                    f"geht auch nicht: {exc}"
                )
                return ToolResult(ok=False, error=str(exc), display=grund,
                                  duration_ms=dauer())

        if ort is None:
            return ToolResult(
                ok=False,
                error="Ort nicht gefunden.",
                display=(
                    f"Kein Ort namens {name!r} gefunden. Jedes Land und jede "
                    f"Hauptstadt ist eingebaut; alles andere kommt von "
                    f"Wikidata - vielleicht anders geschrieben?"
                ),
                duration_ms=dauer(),
            )

        box = bbox_um(ort.lat, ort.lon, kante_km=float(kante_km))
        aufloesung = effektive_aufloesung_m(box, BILD_KANTE, BILD_KANTE)
        return ToolResult(
            ok=True,
            data={"ort": ort.als_dict(), "bbox": list(box),
                  "bild_aufloesung_m": round(aufloesung, 1)},
            display=(
                f"{ort.name}: {ort.lat:.4f}, {ort.lon:.4f}"
                + (f" ({ort.art}, {ort.iso3})" if ort.art else "")
                + (f", {ort.einwohner} Einwohner" if ort.einwohner else "")
                + f"\nAusschnitt {kante_km:.0f} km: bbox="
                + "[" + ", ".join(f"{x:.4f}" for x in box) + "]"
                + f"\nDaraus wuerden {aufloesung:.0f} m je Bildpixel - "
                + ("gut genug fuer Siedlungsgrenzen und Felder."
                   if aufloesung < 60 else
                   "nur fuer sehr grosse Strukturen.")
            ),
            duration_ms=dauer(),
        )
