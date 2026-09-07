"""FIX-12, Gruppe 4: der Kalender, wenn der Dienst dahinter fehlt.

Der Auftrag ist "Features muessen auch dann stabil bleiben, wenn Dienste
fehlen - ein fehlender Dienst darf keinen Crash verursachen". Fuer den
Kalender heisst das sechs Faelle, und jeder wird hier mit
`httpx.MockTransport` nachgestellt statt beschrieben: Zeitueberschreitung,
Verbindungsfehler, HTTP 500, HTTP 429 (mit und ohne `Retry-After`),
unerwartete Antwortform und die leere sowie die sehr grosse Antwort.

Kein Netz. `tests/conftest.py` sperrt die echten Transporte; `MockTransport`
geht daran vorbei, weil er sie gar nicht erst benutzt. Vorbild fuer den
Aufbau ist `tests/test_kalender.py` (dort steht der ConnectError-Test, auf
dem dieser hier aufbaut) und `tests/test_fix09.py`.

Zwei Zusagen laufen durch ALLE Faelle mit:

* Die Abo-Adresse ist das Geheimnis (FIX-07, `core/fehlertexte.py`). Sie
  darf in keiner Meldung auftauchen - auch nicht in `error`, auch nicht bei
  einer Weiterleitung, auch nicht, wenn Anmeldedaten darin stehen.
* Kein Wurf schlaegt nach oben durch. Ein fehlender Dienst ist eine
  Auskunft in einem deutschen Satz, kein `ReadTimeout` im Chatfenster.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path
from unittest import mock

import httpx
import pytest

from core.kalender import KalenderFehler, hole, ist_ical, parse
from core.tools.dispatch import run_tool
from core.tools.kalender_tools import FRUEHESTES, MAX_TERMINE, SPAETESTES, Kalender
from tests.conftest import run

# Erkennbar erfunden, damit ein Treffer eindeutig ist - wie in
# tests/test_fehlertexte.py.
GEHEIME_ADRESSE = (
    "https://calendar.google.com/calendar/ical/GEHEIM-TOKEN-xyz/basic.ics"
)
GEHEIMNISSE = ["GEHEIM-TOKEN-xyz", "calendar.google.com", "/ical/",
               "GEHEIM-ORDNER-xyz"]

ICS_EIN_TERMIN = "\r\n".join([
    "BEGIN:VCALENDAR", "VERSION:2.0",
    "BEGIN:VEVENT", "DTSTART:20260828T090000Z", "DTEND:20260828T100000Z",
    "SUMMARY:Zahnarzt", "END:VEVENT",
    "END:VCALENDAR", "",
])


def _werkzeug(quelle, tmp_path: Path) -> Kalender:
    t = Kalender()
    t.kalender_quelle = str(quelle)
    t.db_path = str(tmp_path / "k.db")
    return t


def _mit_transport(handler):
    """`hole()` baut seinen Klienten ueber `core.netz.nach_draussen`, und der
    nimmt keinen Transport von aussen entgegen. Deshalb wird - wie in
    tests/test_kalender.py - `httpx.AsyncClient` selbst umgebogen."""
    echt = httpx.AsyncClient

    def fake(*a, **k):
        k["transport"] = httpx.MockTransport(handler)
        return echt(*a, **k)

    return mock.patch("httpx.AsyncClient", fake)


def _lauf(handler, tmp_path, quelle=GEHEIME_ADRESSE, **kw):
    with _mit_transport(handler):
        return run(_werkzeug(quelle, tmp_path).execute(**kw))


def _wirft(klasse, text="kaputt"):
    def handler(request):
        raise klasse(text, request=request)
    return handler


def _leckt(ergebnis) -> list[str]:
    """Beide Felder, nicht nur display - genau daran ist ein frueherer
    Waechter vorbeigelaufen (core/fehlertexte.py, Modulkopf)."""
    text = f"{ergebnis.display or ''} {ergebnis.error or ''}"
    return [g for g in GEHEIMNISSE if g in text]


# ===========================================================================
# Fall 1 und 2: Zeitueberschreitung und Verbindungsfehler
# ===========================================================================


@pytest.mark.parametrize("klasse", [
    httpx.ReadTimeout, httpx.TimeoutException, httpx.ConnectTimeout,
    httpx.ConnectError, httpx.ReadError, httpx.RemoteProtocolError,
])
def test_ein_netzausfall_ist_eine_auskunft_und_kein_absturz(klasse, tmp_path):
    """Sechs Arten, wie httpx aufgibt. Keine davon darf als Ausnahme aus dem
    Werkzeug herauskommen: der Nutzer bekommt einen Satz, den er versteht,
    und die Antwort sagt, wo er nachsehen kann."""
    e = _lauf(_wirft(klasse), tmp_path)
    assert e.ok is False
    assert "Kalender nicht erreichbar" in e.display
    assert "KALENDER_QUELLE" in e.display
    assert klasse.__name__ in e.display          # ohne_geheimnis nennt den Typ
    assert _leckt(e) == [], _leckt(e)


def test_der_dispatcher_sieht_bei_einem_timeout_keinen_werkzeugfehler(tmp_path):
    """Der Weg, den das Modell wirklich nimmt. Ein `ReadTimeout`, der bis in
    `run_tool` durchschlaegt, wird dort zu "kalender ist mit einem Fehler
    ausgestiegen" - eine Meldung, mit der niemand etwas anfangen kann."""
    werkzeug = _werkzeug(GEHEIME_ADRESSE, tmp_path)
    with mock.patch.object(type(werkzeug), "kalender_quelle", GEHEIME_ADRESSE), \
            mock.patch.object(type(werkzeug), "db_path", str(tmp_path / "k.db")), \
            _mit_transport(_wirft(httpx.ReadTimeout)):
        e = run(run_tool("kalender", {}))
    assert e.ok is False
    assert "ausgestiegen" not in (e.error or ""), e.error
    assert "Kalender nicht erreichbar" in (e.error or "")


# ===========================================================================
# Fall 3 und 4: HTTP 500, HTTP 429 mit und ohne Retry-After
# ===========================================================================


@pytest.mark.parametrize("status,kopfzeilen", [
    (500, {}),
    (502, {}),
    (503, {"Retry-After": "120"}),
    (429, {}),
    (429, {"Retry-After": "60"}),
    (429, {"Retry-After": "Wed, 09 Sep 2026 08:00:00 GMT"}),
    (401, {}),
    (404, {}),
])
def test_jeder_fehlerstatus_nennt_die_zahl_und_nicht_die_adresse(
    status, kopfzeilen, tmp_path
):
    """Die Zahl hilft beim Suchen, die Adresse waere das Leck. `Retry-After`
    aendert daran nichts - es wird bewusst nicht ausgewertet, weil hier
    ohnehin nicht automatisch nachgefragt wird."""
    def handler(request):
        return httpx.Response(status, request=request, headers=kopfzeilen)

    e = _lauf(handler, tmp_path)
    assert e.ok is False
    assert f"HTTP {status}" in e.display, e.display
    assert _leckt(e) == [], _leckt(e)


def test_nach_einem_fehlschlag_wird_der_zwischenspeicher_benutzt(tmp_path):
    """Ein alter Kalenderstand ist besser als gar keiner - und dass er alt
    ist, steht in der Antwort."""
    db = tmp_path / "k.db"
    ok = lambda r: httpx.Response(200, request=r, text=ICS_EIN_TERMIN)  # noqa: E731
    with _mit_transport(ok):
        erst = run(_werkzeug(GEHEIME_ADRESSE, tmp_path).execute(
            von="2026-08-28", bis="2026-08-28"))
    assert erst.ok is True and erst.data["aus_cache"] is False

    # Der Cache ist 15 Minuten gueltig; damit wirklich der FEHLERWEG geprueft
    # wird und nicht nur der Cachetreffer, wird die Datei alt gemacht.
    import os
    import time as _zeit

    from core.kalender import cache_datei
    datei = cache_datei(db)
    vor_drei_tagen = _zeit.time() - 3 * 86400
    os.utime(datei, (vor_drei_tagen, vor_drei_tagen))

    with _mit_transport(_wirft(httpx.ConnectError)):
        zweit = run(_werkzeug(GEHEIME_ADRESSE, tmp_path).execute(
            von="2026-08-28", bis="2026-08-28"))
    assert zweit.ok is True
    assert zweit.data["aus_cache"] is True
    assert "Zwischenspeicher" in zweit.display
    # Und das Alter muss stimmen: hier stand fest "hoechstens 15 Minuten
    # alt", obwohl der Rueckfallstand Tage alt sein kann.
    assert "3 Tage alt" in zweit.display, zweit.display
    assert [t["titel"] for t in zweit.data["termine"]] == ["Zahnarzt"]
    assert _leckt(zweit) == [], _leckt(zweit)


# ===========================================================================
# Fall 5: unerwartete Form
# ===========================================================================


def test_eine_anmeldeseite_mit_status_200_ist_kein_kalender(tmp_path):
    """Ein abgelaufenes Abo antwortet mit HTTP 200 und HTML. Wer nur den
    Status prueft, meldet "0 Termine"."""
    e = _lauf(lambda r: httpx.Response(
        200, request=r, text="<html><body>Bitte anmelden</body></html>"), tmp_path)
    assert e.ok is False
    assert "kein iCalendar" in e.display
    assert _leckt(e) == [], _leckt(e)


def test_eine_umleitung_wird_nicht_verfolgt(tmp_path):
    """Bei einem Abo IST die Adresse das Geheimnis - eine Weiterleitung
    wuerde sie auf einen fremden Host mitnehmen (FIX-03 Schritt 2)."""
    e = _lauf(lambda r: httpx.Response(
        302, request=r, headers={"Location": "https://fremd.example/x.ics"}),
        tmp_path)
    assert e.ok is False
    assert "leitet weiter" in e.display
    assert "fremd.example" not in e.display
    assert _leckt(e) == [], _leckt(e)


def test_ein_abgeschnittenes_vevent_wird_gezaehlt_statt_verschluckt():
    """Fund 1 noch einmal, eine Zeile spaeter: ein `BEGIN:VEVENT` ohne
    `END:VEVENT` - abgeschnittene Datei, halb uebertragene Antwort - fiel
    beim Verlassen der Schleife spurlos weg. Die Antwort sagte "0 Termine",
    obwohl einer dagestanden hat.

    Weglassen ja, verschweigen nein: jedes VEVENT ist entweder geliefert,
    gezaehlt-weil-wiederkehrend oder gezaehlt-weil-unlesbar."""
    halb = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20260828T090000Z\r\n"
            "SUMMARY:Halber Termin")
    termine, wiederkehrend, unlesbar, _ = parse(halb)
    assert termine == []
    assert unlesbar == 1, "das abgeschnittene VEVENT wurde nicht gezaehlt"
    assert len(termine) + wiederkehrend + unlesbar == halb.count("BEGIN:VEVENT")


def test_das_werkzeug_meldet_den_abgeschnittenen_termin(tmp_path):
    datei = tmp_path / "halb.ics"
    datei.write_text("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n"
                     "DTSTART:20260828T090000Z\r\nSUMMARY:Halber Termin",
                     encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von="2026-08-01",
                                               bis="2026-09-30"))
    assert e.ok is True
    assert e.data["nicht_lesbar"] == 1
    assert "nicht lesbar" in e.display


def test_eine_unbekannte_zeitzone_wird_gesagt_statt_still_zu_utc_zu_werden(tmp_path):
    """Outlook schreibt `TZID:W. Europe Standard Time`, und diesen Namen
    kennt die IANA-Datenbank nicht. Vorher fiel `_zone` still auf UTC
    zurueck: jeder Termin lag ein bis zwei Stunden daneben, ohne ein Wort.
    Das ist dieselbe Klasse wie Fund 2 - nur ohne Anhaltspunkt."""
    ics = "\r\n".join([
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT", "DTSTART;TZID=W. Europe Standard Time:20260828T090000",
        "DTEND;TZID=W. Europe Standard Time:20260828T100000",
        "SUMMARY:Besprechung", "END:VEVENT",
        "END:VCALENDAR", "",
    ])
    datei = tmp_path / "outlook.ics"
    datei.write_text(ics, encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von="2026-08-28",
                                               bis="2026-08-28"))
    assert e.ok is True
    assert e.data["unbekannte_zeitzonen"] == ["W. Europe Standard Time"]
    assert "W. Europe Standard Time" in e.display
    assert "koennen um Stunden danebenliegen" in e.display
    # Der Termin selbst bleibt in der Liste - weglassen waere schlimmer.
    assert [t["titel"] for t in e.data["termine"]] == ["Besprechung"]


def test_eine_bekannte_zeitzone_meldet_nichts(tmp_path):
    """Gegenprobe - sonst waere ein Zaehler gruen, der immer etwas meldet."""
    ics = "\r\n".join([
        "BEGIN:VCALENDAR",
        "BEGIN:VEVENT", "DTSTART;TZID=Europe/Berlin:20260828T090000",
        "DTEND;TZID=Europe/Berlin:20260828T100000",
        "SUMMARY:Besprechung", "END:VEVENT",
        "END:VCALENDAR", "",
    ])
    datei = tmp_path / "gut.ics"
    datei.write_text(ics, encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von="2026-08-28",
                                               bis="2026-08-28"))
    assert e.data["unbekannte_zeitzonen"] == []
    assert "kennt" not in e.display


# ===========================================================================
# Fall 6: leere und sehr grosse Antwort
# ===========================================================================


def test_eine_leere_antwort_ist_kein_leerer_kalender(tmp_path):
    """HTTP 200 mit leerem Koerper heisst nicht "du hast frei"."""
    e = _lauf(lambda r: httpx.Response(200, request=r, text=""), tmp_path)
    assert e.ok is False
    assert "kein iCalendar" in e.display
    assert _leckt(e) == [], _leckt(e)


def test_ein_wirklich_leerer_kalender_sagt_weiter_null(tmp_path):
    """Die Gegenprobe zum Test darueber."""
    e = _lauf(lambda r: httpx.Response(
        200, request=r, text="BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"),
        tmp_path)
    assert e.ok is True
    assert e.data["termine"] == []
    assert "0 Termine" in e.display


def test_zehntausend_termine_sprengen_den_prompt_nicht(tmp_path):
    """Gemessen vor der Reparatur: 10.000 Termine an einem Tag ergaben eine
    `display` von rund 600 KB mit 10.000 Zeilen - und `display` geht in den
    Prompt und damit an den Modellanbieter. Die Laenge der Antwort auf "was
    habe ich heute vor" haengt jetzt nicht mehr an der Groesse des
    Kalenders.

    Die Gesamtzahl bleibt ehrlich: sie steht im Kopf und in `data`."""
    viele = "BEGIN:VCALENDAR\r\n" + "".join(
        f"BEGIN:VEVENT\r\nDTSTART:20260828T09{i % 60:02d}00Z\r\n"
        f"DTEND:20260828T10{i % 60:02d}00Z\r\nSUMMARY:Termin {i}\r\n"
        f"END:VEVENT\r\n" for i in range(10000)
    ) + "END:VCALENDAR\r\n"

    e = _lauf(lambda r: httpx.Response(200, request=r, text=viele), tmp_path,
              von="2026-08-28", bis="2026-08-28")
    assert e.ok is True
    assert e.data["termine_gesamt"] == 10000
    assert len(e.data["termine"]) == MAX_TERMINE
    zeilen = [z for z in e.display.splitlines() if z.startswith("2026-08-28")]
    assert len(zeilen) == MAX_TERMINE, len(zeilen)
    assert len(e.display) < 20_000, len(e.display)
    assert "10000 Termine" in e.display        # verschwiegen wird nichts
    assert f"die ersten {MAX_TERMINE}" in e.display


# ===========================================================================
# Ungueltige Eingaben
# ===========================================================================


@pytest.mark.parametrize("von,bis", [
    ("morgen", ""),
    ("2026-13-45", ""),
    ("28.08.2026", ""),
    ("", "irgendwann"),
])
def test_ein_unlesbares_datum_wird_erklaert(von, bis, tmp_path):
    datei = tmp_path / "k.ics"
    datei.write_text(ICS_EIN_TERMIN, encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von=von, bis=bis))
    assert e.ok is False
    assert "ISO" in e.display


def test_ein_unmoegliches_zeitfenster_wirft_nicht(tmp_path):
    """Gemessen: `von=0001-01-01` lief in `im_fenster` in ein nacktes
    `ValueError: year 0 is out of range` (astimezone auf den 01.01.0001),
    das aus dem Werkzeug herausflog. Im Chat stand "kalender ist mit einem
    Fehler ausgestiegen"."""
    datei = tmp_path / "k.ics"
    datei.write_text(ICS_EIN_TERMIN, encoding="utf-8")
    e = run(run_tool("kalender", {"von": "0001-01-01", "bis": "9999-12-31"}))
    assert e.ok is False
    assert "ausgestiegen" not in (e.error or ""), e.error
    assert str(FRUEHESTES.year) in (e.error or "")
    assert str(SPAETESTES.year) in (e.error or "")


def test_ein_umgedrehtes_fenster_wird_gedreht_statt_abgelehnt(tmp_path):
    datei = tmp_path / "k.ics"
    datei.write_text(ICS_EIN_TERMIN, encoding="utf-8")
    e = run(_werkzeug(datei, tmp_path).execute(von="2026-09-30",
                                               bis="2026-08-01"))
    assert e.ok is True
    assert e.data["von"] == "2026-08-01" and e.data["bis"] == "2026-09-30"


# ===========================================================================
# Die Quelle: Datei statt URL, Anmeldedaten in der Adresse
# ===========================================================================


def test_eine_datei_die_kein_ical_ist_wird_nicht_als_leer_gemeldet(tmp_path):
    """Bei der URL wurde der Inhalt seit jeher geprueft, bei der Datei nicht:
    eine PDF oder ein halber Download las sich als "0 Termine" - also genau
    wie ein leerer Kalender. Der Unterschied ist der zwischen "du hast frei"
    und "ich weiss es nicht" (Modulkopf von kalender_tools.py)."""
    datei = tmp_path / "GEHEIM-ORDNER-xyz.ics"
    datei.write_bytes(bytes(range(256)) * 40)
    e = run(_werkzeug(datei, tmp_path).execute())
    assert e.ok is False
    assert "kein iCalendar" in e.display
    assert _leckt(e) == [], _leckt(e)
    assert str(tmp_path) not in e.display + (e.error or "")


def test_file_adresse_und_fehlender_pfad_verraten_den_pfad_nicht(tmp_path):
    """`file://...` ist keine http-Adresse und landet im Datei-Zweig; der
    Pfad ist laut core/config.py ein Geheimnis."""
    for quelle in (f"file://{tmp_path}/GEHEIM-ORDNER-xyz/k.ics",
                   f"{tmp_path}/GEHEIM-ORDNER-xyz/k.ics"):
        e = run(_werkzeug(quelle, tmp_path).execute())
        assert e.ok is False
        assert "gibt es nicht" in e.display
        assert _leckt(e) == [], (quelle, _leckt(e))
        assert str(tmp_path) not in e.display + (e.error or "")


def test_eine_nicht_lesbare_datei_verraet_den_pfad_nicht(tmp_path, monkeypatch):
    """Der OSError-Zweig des Werkzeugs. Er laesst sich nicht ueber die Rechte
    ausloesen, solange der Test als root laeuft - deshalb wird der Fehler
    dort erzeugt, wo er im Betrieb entsteht."""
    def platzt(*a, **k):
        raise PermissionError(13, "Permission denied",
                              "/home/noah/GEHEIM-ORDNER-xyz/k.ics")

    monkeypatch.setattr("core.tools.kalender_tools.hole", platzt)
    e = run(_werkzeug("/irgendwo/k.ics", tmp_path).execute())
    assert e.ok is False
    assert "Kalender nicht lesbar" in e.display
    assert "PermissionError" in e.display
    assert _leckt(e) == [], _leckt(e)
    assert "/home/noah" not in e.display + (e.error or "")


def test_anmeldedaten_in_der_adresse_verlassen_das_geraet_nicht(tmp_path):
    """FIX-07: die Adresse selbst ist das Geheimnis, und mit `user:pass@`
    steckt sogar ein Passwort darin. httpx macht daraus einen
    Authorization-Kopf; `core.netz.nach_draussen` verweigert die Anfrage
    dann, statt sie still zu entschaerfen.

    Geprueft wird beides: dass NICHTS beim Transport ankommt und dass in der
    Meldung weder Adresse noch Passwort steht."""
    mit_pass = ("https://noah:SUPERGEHEIM123@calendar.google.com/calendar/"
                "ical/GEHEIM-TOKEN-xyz/basic.ics")
    gesehen = []

    def handler(request):
        gesehen.append(str(request.url))
        return httpx.Response(200, request=request, text=ICS_EIN_TERMIN)

    e = _lauf(handler, tmp_path, quelle=mit_pass)
    assert gesehen == [], "die Anfrage haette das Geraet verlassen"
    assert e.ok is False
    assert "SUPERGEHEIM123" not in e.display + (e.error or "")
    assert "noah:" not in e.display + (e.error or "")
    assert _leckt(e) == [], _leckt(e)


# ===========================================================================
# Happy Path und der Waechter selbst
# ===========================================================================


def test_happy_path_ueber_die_abo_adresse(tmp_path):
    """Damit die Faelle darueber nicht nur zeigen, dass irgendetwas
    schiefgeht."""
    e = _lauf(lambda r: httpx.Response(200, request=r, text=ICS_EIN_TERMIN),
              tmp_path, von="2026-08-28", bis="2026-08-28")
    assert e.ok is True
    assert [t["titel"] for t in e.data["termine"]] == ["Zahnarzt"]
    assert e.data["termine_gesamt"] == 1
    assert e.data["nicht_lesbar"] == 0
    assert e.data["unbekannte_zeitzonen"] == []
    assert e.data["aus_cache"] is False


def test_ist_ical_erkennt_beides():
    assert ist_ical("BEGIN:VCALENDAR\r\nEND:VCALENDAR") is True
    assert ist_ical("<html>Bitte anmelden</html>") is False
    assert ist_ical("") is False


def test_der_waechter_wuerde_ein_leck_ueberhaupt_bemerken(tmp_path):
    """Ein Waechter, der nichts fangen kann, ist der gefaehrlichste Test von
    allen (siehe tests/test_fehlertexte.py). Also die Gegenprobe."""
    from core.contracts import ToolResult

    assert _leckt(ToolResult(ok=False, error=GEHEIME_ADRESSE, display="ok"))
    assert _leckt(ToolResult(ok=False, error="ok", display=GEHEIME_ADRESSE))
    assert _leckt(ToolResult(ok=True, display="alles gut")) == []


def test_ohne_quelle_bleibt_es_beim_satz_statt_beim_leeren_ergebnis(tmp_path):
    """DoD 9 aus FIX-07, hier nur noch einmal im Zusammenhang: ein fehlender
    Dienst ist etwas anderes als ein leeres Ergebnis."""
    e = run(_werkzeug("", tmp_path).execute())
    assert e.ok is False
    assert "KALENDER_QUELLE" in e.display
    assert e.data is None
    with pytest.raises(KalenderFehler):
        run(hole("", db_path=tmp_path / "k.db"))


def test_ein_frischer_zwischenspeicher_wird_nicht_als_alt_gemeldet(tmp_path):
    """Gegenprobe zu `test_nach_einem_fehlschlag_...`: der gewoehnliche
    Cachetreffer innerhalb der 15 Minuten darf nicht nach altem Stand
    klingen."""
    handler = lambda r: httpx.Response(200, request=r, text=ICS_EIN_TERMIN)  # noqa: E731
    with _mit_transport(handler):
        erst = run(_werkzeug(GEHEIME_ADRESSE, tmp_path).execute())
        zweit = run(_werkzeug(GEHEIME_ADRESSE, tmp_path).execute())
    assert erst.data["aus_cache"] is False
    assert "Zwischenspeicher" not in erst.display
    assert zweit.data["aus_cache"] is True
    assert "gerade geholt" in zweit.display, zweit.display
    assert "Tage alt" not in zweit.display
