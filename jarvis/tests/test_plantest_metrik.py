"""Die Metrik der Messstrecke (FIX-10 Schritt A).

**Warum das hier steht, obwohl DoD-Kriterium 7 "pytest unberuehrt" verlangt.**
Das Skript selbst ruft echte Modelle und gehoert nicht in `pytest` - genau
deshalb liegt es unter `scripts/`. Die Metrik ruft gar nichts. Sie ist eine
reine Funktion ueber zwei Mengen, und sie entscheidet ueber jede Zahl, die
diese Messstrecke je ausgibt.

Eine ungetestete Metrik macht alles Nachgelagerte unpruefbar: fiele der
Sonderfall "beide leer" falsch aus, waeren 6 der 30 Faelle systematisch falsch
bewertet - und niemand saehe es, weil die Zahl ja eine Zahl ist.

Die Abweichung von Kriterium 7 ist damit bewusst und steht so im Bericht:
die Testanzahl steigt um diese Datei, und um nichts sonst.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts.plantest import f1, json_aus_text, mittel


# --- Der Sonderfall, der ueber 6 von 30 Faellen entscheidet ---------------


def test_beide_leer_ist_voller_treffer():
    """"Kein Werkzeug noetig" richtig erkannt IST die richtige Antwort -
    nicht ein unbewertbarer Fall."""
    assert f1(set(), set()) == 1.0


def test_erwartet_leer_aber_werkzeug_gegriffen_ist_null():
    """Der Planer, der bei jeder Frage irgendwas greift. Genau das soll die
    Messstrecke finden."""
    assert f1(set(), {"clock"}) == 0.0


def test_erwartet_etwas_aber_nichts_gegriffen_ist_null():
    assert f1({"clock"}, set()) == 0.0


# --- Die gewoehnlichen Faelle --------------------------------------------


def test_volltreffer():
    assert f1({"a", "b"}, {"a", "b"}) == 1.0


def test_reihenfolge_ist_egal():
    """`werkzeuge` ist laut Auftrag eine Menge ohne Reihenfolge."""
    assert f1({"a", "b"}, {"b", "a"}) == 1.0


def test_haelfte_richtig():
    # Praezision 1/2, Trefferquote 1/1 -> F1 = 2*(0.5*1)/(0.5+1) = 0.666...
    assert f1({"a"}, {"a", "b"}) == pytest.approx(2 / 3)


def test_haelfte_gefunden():
    assert f1({"a", "b"}, {"a"}) == pytest.approx(2 / 3)


def test_voellig_daneben():
    assert f1({"a"}, {"b"}) == 0.0


def test_kanten_sind_paare_und_gehen_genauso():
    """Dieselbe Funktion, andere Elemente - Kanten sind Tupel."""
    assert f1({("a", "b")}, {("a", "b")}) == 1.0
    assert f1({("a", "b")}, {("b", "a")}) == 0.0, "Richtung muss zaehlen"


def test_symmetrie():
    """F1 ist symmetrisch - vertauscht man erwartet und bekommen, kommt
    dasselbe heraus. Waere es das nicht, haette die Zahl keine Bedeutung."""
    a, b = {"x", "y"}, {"y", "z", "w"}
    assert f1(a, b) == pytest.approx(f1(b, a))


def test_immer_zwischen_null_und_eins():
    mengen = [set(), {"a"}, {"a", "b"}, {"a", "b", "c"}, {"x"}]
    for e in mengen:
        for g in mengen:
            assert 0.0 <= f1(e, g) <= 1.0, (e, g)


# --- Mittelwert -----------------------------------------------------------


def test_mittel_ueber_leere_liste_ist_null_und_wirft_nicht():
    assert mittel([]) == 0.0


def test_mittel_rechnet():
    assert mittel([1.0, 0.0]) == 0.5


# --- Die Antwort des Modells lesen ---------------------------------------


def test_nacktes_json():
    assert json.loads(json_aus_text('{"werkzeuge": []}')) == {"werkzeuge": []}


def test_json_im_markdown_block():
    text = 'Hier ist der Plan:\n```json\n{"werkzeuge": ["clock"]}\n```\nViel Erfolg!'
    assert json.loads(json_aus_text(text)) == {"werkzeuge": ["clock"]}


def test_json_mit_geschwaetz_davor():
    text = 'Klar! {"werkzeuge": ["clock"], "kanten": []}'
    assert json.loads(json_aus_text(text))["werkzeuge"] == ["clock"]


def test_unlesbares_bleibt_unlesbar():
    """Kein Rateversuch. Eine unlesbare Antwort zaehlt im Skript als
    Fehlschlag - wer sie ueberspringt, schoent den Durchschnitt."""
    with pytest.raises(json.JSONDecodeError):
        json.loads(json_aus_text("Ich weiss es nicht."))


# --- Der Pruefsatz selbst -------------------------------------------------

FAELLE = Path(__file__).resolve().parent / "plandaten" / "faelle.json"


@pytest.mark.skipif(not FAELLE.is_file(), reason="Pruefsatz noch nicht geschrieben")
def test_der_pruefsatz_ist_in_sich_stimmig():
    """Nicht die Guete der Annotationen - die kann kein Test pruefen -,
    sondern die Form. Ein Tippfehler im Werkzeugnamen wuerde sonst als
    Planungsfehler durchgehen und die Zahl still verfaelschen."""
    from core.tools import registry

    faelle = json.loads(FAELLE.read_text(encoding="utf-8"))
    bekannt = set(registry.names())

    assert len(faelle) == 30, f"{len(faelle)} Faelle, erwartet 30"
    ids = [f["id"] for f in faelle]
    assert len(set(ids)) == len(ids), "doppelte ids"

    leer = 0
    for f in faelle:
        assert f["auftrag"].strip(), f["id"]
        assert f["begruendung"].strip(), f["id"]
        for w in f["werkzeuge"]:
            assert w in bekannt, f"{f['id']}: {w!r} gibt es nicht"
        for a, b in f["kanten"]:
            assert a in f["werkzeuge"], f"{f['id']}: Kante von {a!r}, aber nicht in werkzeuge"
            assert b in f["werkzeuge"], f"{f['id']}: Kante nach {b!r}, aber nicht in werkzeuge"
            assert a != b, f"{f['id']}: Kante auf sich selbst"
        if not f["werkzeuge"]:
            assert not f["kanten"], f"{f['id']}: keine Werkzeuge, aber Kanten"
            leer += 1

    assert leer == 6, f"{leer} Faelle ohne Werkzeug, erwartet 6"
