"""FIX-07: Kalender. DoD-Kriterien 6 bis 9.

Alle Regeln, gegen die hier geprüft wird, stammen aus RFC 5545 — geholt am
27.08.2026 von `https://www.rfc-editor.org/rfc/rfc5545.txt` (HTTP 200), nicht
aus dem Gedächtnis. Die Abschnittsnummern stehen bei den Tests.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from pathlib import Path
from unittest import mock

import pytest

from core.kalender import (
    AUSBLICK,
    KalenderFehler,
    entfalte,
    entschluessele,
    hole,
    im_fenster,
    lies_zeit,
    parse,
)
from core.tools.kalender_tools import Kalender
from tests.conftest import run

# Ein Kalender mit genau den Faellen aus dem DoD:
#   1. ein normaler Termin in UTC
#   2. ein ganztaegiger
#   3. einer mit TZID
#   4. einer mit einem Titel ueber 75 Zeichen, deshalb gefaltet
#   5. ein wiederkehrender
ICS = "\r\n".join([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Test//DE",
    "X-WR-CALNAME:Noahs Kalender",
    # 1
    "BEGIN:VEVENT",
    "UID:1@test",
    "DTSTART:20260828T090000Z",
    "DTEND:20260828T100000Z",
    "SUMMARY:Mathe-Klausur",
    "LOCATION:Raum 12",
    "END:VEVENT",
    # 2 - ganztaegig. DTEND ist NICHT einschliessend (RFC 5545, 3.6.1):
    # der Termin geht ueber den 29., nicht ueber den 30.
    "BEGIN:VEVENT",
    "UID:2@test",
    "DTSTART;VALUE=DATE:20260829",
    "DTEND;VALUE=DATE:20260830",
    "SUMMARY:Wandertag",
    "END:VEVENT",
    # 3 - Ortszeit mit Zone (FORM #3, RFC 5545, 3.3.5)
    "BEGIN:VEVENT",
    "UID:3@test",
    "DTSTART;TZID=Europe/Berlin:20260830T140000",
    "DTEND;TZID=Europe/Berlin:20260830T153000",
    "SUMMARY:Zahnarzt",
    "END:VEVENT",
    # 4 - gefalteter Titel (RFC 5545, 3.1) plus Escaping (3.3.11)
    "BEGIN:VEVENT",
    "UID:4@test",
    "DTSTART:20260831T080000Z",
    "DTEND:20260831T090000Z",
    "SUMMARY:Elternabend mit Herrn Meier\\, Frau Schulz und dem gesamten Kolle",
    " gium der Jahrgangsstufe zehn im grossen Saal",
    "END:VEVENT",
    # 5 - wiederkehrend
    "BEGIN:VEVENT",
    "UID:5@test",
    "DTSTART:20260901T160000Z",
    "DTEND:20260901T170000Z",
    "RRULE:FREQ=WEEKLY;BYDAY=TU",
    "SUMMARY:Fussballtraining",
    "END:VEVENT",
    "END:VCALENDAR",
    "",
])


def _werkzeug(quelle, tmp_path: Path) -> Kalender:
    t = Kalender()
    t.kalender_quelle = str(quelle)
    t.db_path = str(tmp_path / "k.db")
    return t


# --- Die vier Fallstricke einzeln ------------------------------------------


def test_faltung_wird_rueckgaengig_gemacht():
    """RFC 5545, 3.1: 'Unfolding is accomplished by removing the CRLF and
    the linear white-space character that immediately follows.'"""
    assert entfalte("A:eins\r\n zwei\r\nB:drei") == ["A:einszwei", "B:drei"]
    # Tab zaehlt genauso.
    assert entfalte("A:eins\r\n\tzwei") == ["A:einszwei"]
    # Und Dateien mit reinem LF gibt es genauso.
    assert entfalte("A:eins\n zwei") == ["A:einszwei"]


def test_escaping_nach_der_norm():
    """RFC 5545, 3.3.11: ESCAPED-CHAR = ("\\\\" / "\\;" / "\\," / "\\N" / "\\n")"""
    assert entschluessele(r"a\, b") == "a, b"
    assert entschluessele(r"a\; b") == "a; b"
    assert entschluessele(r"a\nb") == "a\nb"
    assert entschluessele(r"a\Nb") == "a\nb"          # Grossbuchstabe auch
    assert entschluessele(r"a\\b") == "a\\b"
    # Der Doppelpunkt wird ausdruecklich NICHT maskiert.
    assert entschluessele("http://x") == "http://x"


def test_ein_maskierter_backslash_wird_kein_zeilenumbruch():
    """Der Grund, warum hier Zeichen fuer Zeichen gelesen wird und nicht mit
    mehreren `replace` hintereinander: `\\\\n` ist ein Backslash und ein n,
    kein Umbruch."""
    assert entschluessele("a\\\\nb") == "a\\nb"
    assert "\n" not in entschluessele("a\\\\nb")


def test_die_drei_formen_von_dtstart():
    """RFC 5545, 3.3.5 (FORM #1-#3) und 3.3.4 (DATE)."""
    utc, ganz = lies_zeit("20260828T090000Z", {})
    assert ganz is False and utc == datetime(2026, 8, 28, 9, 0, tzinfo=timezone.utc)

    zone, ganz = lies_zeit("20260830T140000", {"TZID": "Europe/Berlin"})
    assert ganz is False
    assert zone.utcoffset().total_seconds() == 7200      # Sommerzeit, UTC+2

    tag, ganz = lies_zeit("20260829", {"VALUE": "DATE"})
    assert ganz is True and tag == date(2026, 8, 29)
    assert not isinstance(tag, datetime), "Ganztaegig ist kein Zeitpunkt"


# --- DoD 6 ------------------------------------------------------------------


def test_dod_6_kalender_liefert_echte_termine():
    termine, _ = parse(ICS)
    nach_titel = {t.titel: t for t in termine}

    assert "Mathe-Klausur" in nach_titel
    m = nach_titel["Mathe-Klausur"]
    assert m.beginn == datetime(2026, 8, 28, 9, 0, tzinfo=timezone.utc)
    assert m.ort == "Raum 12"
    assert m.ganztaegig is False
    assert m.kalender == "Noahs Kalender"

    w = nach_titel["Wandertag"]
    assert w.ganztaegig is True
    assert w.beginn == date(2026, 8, 29)

    z = nach_titel["Zahnarzt"]
    assert z.ganztaegig is False
    assert z.beginn.utcoffset().total_seconds() == 7200
    assert z.beginn.hour == 14                       # Ortszeit bleibt Ortszeit


# --- DoD 7 ------------------------------------------------------------------


def test_dod_7_gefaltete_zeilen_ueberleben():
    termine, _ = parse(ICS)
    lang = [t for t in termine if t.titel.startswith("Elternabend")]
    assert len(lang) == 1
    titel = lang[0].titel
    assert titel.endswith("im grossen Saal"), titel
    assert "Kollegium" in titel, "an der Faltstelle zerbrochen"
    assert "Meier, Frau Schulz" in titel, "Escaping nicht aufgeloest"
    assert len(titel) > 75


# --- DoD 8 ------------------------------------------------------------------


def test_dod_8_wiederkehrende_werden_gezaehlt_nicht_erfunden(tmp_path):
    termine, wiederkehrend = parse(ICS)
    assert wiederkehrend == 1
    assert all("Fussball" not in t.titel for t in termine), \
        "ein wiederkehrender Termin wurde als Einzeltermin erfunden"

    datei = tmp_path / "k.ics"
    datei.write_text(ICS, encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von="2026-08-28", bis="2026-09-30"))
    assert e.ok is True
    assert e.data["wiederkehrend_nicht_aufgeloest"] == 1
    assert "nicht aufgeloest" in e.display
    assert AUSBLICK.split(".")[0] in e.display


# --- DoD 9 ------------------------------------------------------------------


def test_dod_9_fehlende_quelle_ist_kein_leerer_kalender(tmp_path):
    """Ein leerer Kalender und ein nicht eingerichteter sehen sonst gleich
    aus - und der Unterschied ist der zwischen 'du hast frei' und 'ich weiss
    es nicht'."""
    e = run(_werkzeug("", tmp_path).execute())
    assert e.ok is False
    assert "KALENDER_QUELLE" in e.display
    assert "NICHT" in e.display or "nicht" in e.display
    assert e.data is None


def test_ein_wirklich_leerer_kalender_sagt_null(tmp_path):
    """Die Gegenprobe - sonst prueft der Test darueber nur, dass irgendetwas
    schiefgeht."""
    datei = tmp_path / "leer.ics"
    datei.write_text("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n",
                     encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute())
    assert e.ok is True
    assert e.data["termine"] == []
    assert "0 Termine" in e.display


# --- Zeitfenster ------------------------------------------------------------


def test_das_fenster_schneidet_richtig():
    termine, _ = parse(ICS)
    nur_28 = im_fenster(termine, date(2026, 8, 28), date(2026, 8, 28))
    assert [t.titel for t in nur_28] == ["Mathe-Klausur"]

    # DTEND ist nicht einschliessend: der Wandertag endet am 30., zaehlt
    # also nur zum 29. (RFC 5545, 3.6.1).
    assert [t.titel for t in im_fenster(termine, date(2026, 8, 29), date(2026, 8, 29))] \
        == ["Wandertag"]
    assert [t.titel for t in im_fenster(termine, date(2026, 8, 30), date(2026, 8, 30))] \
        == ["Zahnarzt"]


def test_termine_kommen_sortiert():
    termine, _ = parse(ICS)
    fenster = im_fenster(termine, date(2026, 8, 1), date(2026, 9, 30))
    titel = [t.titel for t in fenster]
    assert titel == ["Mathe-Klausur", "Wandertag", "Zahnarzt", titel[3]]
    assert titel[3].startswith("Elternabend")


# --- Fehlendes DTEND, RFC 5545 3.6.1 ---------------------------------------


def test_ohne_dtend_gilt_die_regel_aus_der_norm():
    ohne = "\r\n".join([
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT", "DTSTART;VALUE=DATE:20260901", "SUMMARY:Ganzer Tag",
        "END:VEVENT",
        "BEGIN:VEVENT", "DTSTART:20260902T100000Z", "SUMMARY:Punkt",
        "END:VEVENT",
        "END:VCALENDAR", "",
    ])
    termine, _ = parse(ohne)
    tag = [t for t in termine if t.titel == "Ganzer Tag"][0]
    assert tag.ende == date(2026, 9, 2), "DATE ohne DTEND: genau ein Tag"
    punkt = [t for t in termine if t.titel == "Punkt"][0]
    assert punkt.ende == punkt.beginn, "DATE-TIME ohne DTEND: gleicher Zeitpunkt"


# --- Beschreibungen bleiben draussen ---------------------------------------


def test_die_beschreibung_kommt_nicht_mit():
    """Dort stehen Meeting-Links, Zugangscodes und gelegentlich Passwoerter
    (FIX-07 Abschnitt 4.3)."""
    mit = ICS.replace(
        "SUMMARY:Mathe-Klausur",
        "DESCRIPTION:Zugangscode 4711\\, Passwort hunter2\r\nSUMMARY:Mathe-Klausur",
    )
    termine, _ = parse(mit)
    alles = " ".join(str(t.als_dict()) for t in termine)
    assert "hunter2" not in alles
    assert "4711" not in alles


# --- Die Quelle -------------------------------------------------------------


def test_eine_datei_wird_direkt_gelesen(tmp_path):
    datei = tmp_path / "k.ics"
    datei.write_text(ICS, encoding="utf-8")
    text, aus_cache = run(hole(str(datei), db_path=tmp_path / "k.db"))
    assert "BEGIN:VCALENDAR" in text
    assert aus_cache is False


def test_eine_datei_die_es_nicht_gibt_sagt_das(tmp_path):
    with pytest.raises(KalenderFehler):
        run(hole(str(tmp_path / "weg.ics"), db_path=tmp_path / "k.db"))


def test_ohne_quelle_wirft_hole(tmp_path):
    with pytest.raises(KalenderFehler) as exc:
        run(hole("", db_path=tmp_path / "k.db"))
    assert "KALENDER_QUELLE" in str(exc.value)


def test_das_werkzeug_ist_lesend_und_braucht_keine_bestaetigung():
    from core.contracts import Permission
    from core.tools import registry

    for name in ("kalender", "datei_suchen", "datei_lesen"):
        t = registry.get(name)
        assert t is not None, name
        assert t.permission is Permission.READ, name
        assert t.requires_confirmation is False, name


# --- Die Abo-Adresse darf NIE in einer Meldung stehen ----------------------


def test_die_geheime_abo_adresse_leckt_bei_keinem_fehler(tmp_path):
    """Die Kalender-Abo-URL IST das Geheimnis: wer sie hat, sieht den ganzen
    Kalender ohne jede Anmeldung. Genau deshalb folgt `hole()` keinen
    Weiterleitungen.

    Drei Zeilen darunter stand bis zum 31.08.2026 aber
    `KalenderFehler(f"Kalender nicht erreichbar: {exc}")` - und httpx haengt
    an seine Fehlermeldung die VOLLE URL:

        Client error '404 Not Found' for url
        'https://calendar.google.com/calendar/ical/<GEHEIM>/basic.ics'

    Dieser Text wird zu ToolResult.error, landet im Prompt und geht damit an
    den Modellanbieter. Ein abgelaufener Abo-Link genuegte.

    Gefunden von zwei Pruefern unabhaengig (Achse "fehlerpfade" und Achse
    "geheimnis").
    """
    import httpx

    from core.db import connect
    from core.kalender import KalenderFehler, hole

    GEHEIM = "https://calendar.google.com/calendar/ical/GEHEIM-TOKEN-xyz/basic.ics"
    db = tmp_path / "k.db"
    connect(db).close()

    # Jeder Statuscode, der in freier Wildbahn vorkommt.
    for status in (401, 403, 404, 410, 500, 503):
        def handler(request, _s=status):
            return httpx.Response(_s, request=request)

        echt = httpx.AsyncClient

        def fake(*a, _h=handler, **k):
            k["transport"] = httpx.MockTransport(_h)
            return echt(*a, **k)

        with mock.patch("httpx.AsyncClient", fake):
            with pytest.raises(KalenderFehler) as fehler:
                run(hole(GEHEIM, db_path=db))

        text = str(fehler.value)
        assert "GEHEIM-TOKEN-xyz" not in text, f"HTTP {status}: {text}"
        assert "calendar.google.com" not in text, f"HTTP {status}: {text}"
        assert "/ical/" not in text, f"HTTP {status}: {text}"
        # Und die Meldung muss trotzdem etwas taugen.
        assert str(status) in text or "nicht erreichbar" in text, text


def test_auch_ein_netzfehler_ohne_antwort_leckt_nichts(tmp_path):
    """Ein Verbindungsfehler hat keine `response` - der Zweig darf nicht
    versehentlich auf `exc` zurueckfallen. httpx nennt die URL auch in
    ConnectError."""
    import httpx

    from core.db import connect
    from core.kalender import KalenderFehler, hole

    GEHEIM = "https://calendar.google.com/calendar/ical/GEHEIM-TOKEN-xyz/basic.ics"
    db = tmp_path / "k.db"
    connect(db).close()

    def handler(request):
        raise httpx.ConnectError("keine Verbindung", request=request)

    echt = httpx.AsyncClient

    def fake(*a, **k):
        k["transport"] = httpx.MockTransport(handler)
        return echt(*a, **k)

    with mock.patch("httpx.AsyncClient", fake):
        with pytest.raises(KalenderFehler) as fehler:
            run(hole(GEHEIM, db_path=db))

    text = str(fehler.value)
    assert "GEHEIM-TOKEN-xyz" not in text, text
    assert "calendar.google.com" not in text, text
