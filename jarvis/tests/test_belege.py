"""Erfundene Quellen fliegen raus.

Anlass: der erste Lauf mit einem echten Modell. Der Satelliten-Agent
scheiterte korrekt an fehlenden CDSE-Zugangsdaten und haengte drei
Quellen-URLs an - obwohl er weder `web_search` noch `fetch_url` hat und
also nichts abgerufen haben kann.
"""

from __future__ import annotations

from core.belege import (
    MARKIERUNG,
    belegte_urls,
    finde_urls,
    ohne_unbelegte_links,
)


DER_ECHTE_FALL = (
    "Der Versuch, das neueste wolkenarme Sentinel-2-Bild zu holen, schlug "
    "fehl, weil die Zugangsdaten nicht hinterlegt sind "
    "(https://sentinel.esa.int/web/sentinel/missions/sentinel-2; "
    "https://en.wikipedia.org/wiki/Germany). Ohne Authentifizierung kann "
    "die Datenbank nicht abgefragt werden (https://dataspace.copernicus.eu/)."
)


def test_der_echte_fall_verliert_alle_drei_links():
    text, entfernt = ohne_unbelegte_links(DER_ECHTE_FALL, belegt=set())
    assert entfernt == 3
    assert "http" not in text.replace(MARKIERUNG.format(n=3), "")
    assert "3 Link(e) entfernt" in text
    # Der Inhalt bleibt stehen - nur die Behauptung, es sei nachgeschlagen.
    assert "Zugangsdaten nicht hinterlegt" in text


def test_leere_klammern_bleiben_nicht_zurueck():
    text, _ = ohne_unbelegte_links(DER_ECHTE_FALL, belegt=set())
    assert "( ;" not in text
    assert "()" not in text
    assert " )" not in text


def test_ein_belegter_link_bleibt_stehen():
    text = "Laut Suche kostet es 5 Euro (https://example.org/preise)."
    bereinigt, entfernt = ohne_unbelegte_links(
        text, belegt=belegte_urls(["https://example.org/preise"])
    )
    assert entfernt == 0
    assert bereinigt == text          # unveraendert, kein Hinweis angehaengt


def test_belegt_und_erfunden_gemischt():
    text = ("Preis von https://example.org/preise, "
            "Hintergrund auf https://erfunden.example/artikel.")
    bereinigt, entfernt = ohne_unbelegte_links(
        text, belegt=belegte_urls(["https://example.org/preise"])
    )
    assert entfernt == 1
    assert "https://example.org/preise" in bereinigt
    assert "erfunden.example" not in bereinigt


def test_der_schlusspunkt_ueberlebt():
    """Ohne Ruecksicht auf Satzzeichen wird aus 'siehe https://x.de.' ein
    'siehe' ohne Punkt - und der Vergleich mit dem Beleg schlaegt fehl,
    weil der Punkt an der Adresse klebt."""
    text = "Steht auf https://example.org."
    bereinigt, entfernt = ohne_unbelegte_links(text, belegt=set())
    assert entfernt == 1
    assert bereinigt.startswith("Steht auf.")


def test_ein_link_mit_punkt_am_ende_gilt_trotzdem_als_belegt():
    text = "Steht auf https://example.org/seite."
    bereinigt, entfernt = ohne_unbelegte_links(
        text, belegt=belegte_urls(["https://example.org/seite"])
    )
    assert entfernt == 0
    assert bereinigt == text


def test_ein_schraegstrich_am_ende_macht_keinen_unterschied():
    bereinigt, entfernt = ohne_unbelegte_links(
        "Siehe https://example.org/",
        belegt=belegte_urls(["https://example.org"]),
    )
    assert entfernt == 0


def test_dieselbe_erfundene_adresse_zaehlt_jedes_mal():
    """Dreimal dieselbe erfundene Adresse ist dreimal eine Behauptung."""
    text = "a https://x.example b https://x.example c https://x.example"
    _, entfernt = ohne_unbelegte_links(text, belegt=set())
    assert entfernt == 3


def test_eine_url_im_werkzeugtext_gilt_als_belegt():
    """Nicht jedes Werkzeug fuellt `sources`. Steht die Adresse im Ergebnis,
    ist sie nachgeschlagen."""
    anzeige = "Treffer: Berlin - https://de.wikipedia.org/wiki/Berlin (10 kB)"
    bereinigt, entfernt = ohne_unbelegte_links(
        "Mehr dazu: https://de.wikipedia.org/wiki/Berlin",
        belegt=belegte_urls([], [anzeige]),
    )
    assert entfernt == 0
    assert "wikipedia" in bereinigt


def test_ohne_links_bleibt_alles_wie_es_war():
    text = "Zwei mal einundzwanzig ist zweiundvierzig."
    assert ohne_unbelegte_links(text, belegt=set()) == (text, 0)


def test_leerer_text_stuerzt_nicht_ab():
    assert ohne_unbelegte_links("", belegt=set()) == ("", 0)


def test_ein_text_der_nur_aus_einem_link_besteht_wird_zum_hinweis():
    bereinigt, entfernt = ohne_unbelegte_links("https://erfunden.example", set())
    assert entfernt == 1
    assert bereinigt == MARKIERUNG.format(n=1)


def test_finde_urls_laesst_das_satzzeichen_draussen():
    assert finde_urls("Siehe https://example.org/a, und https://example.org/b.") == [
        "https://example.org/a",
        "https://example.org/b",
    ]


def test_gross_und_kleinschreibung_im_host_ist_egal():
    _, entfernt = ohne_unbelegte_links(
        "Siehe https://Example.ORG/Seite",
        belegt=belegte_urls(["https://example.org/Seite"]),
    )
    assert entfernt == 0


# --- Der ganze Weg: durch einen echten Agenten ----------------------------


def test_ein_agent_ohne_netzwerkzeug_liefert_keine_links_mehr():
    """Der Fall vom 26.08.2026, durch den echten `ToolAgent`.

    Der Satelliten-Agent hat weder `web_search` noch `fetch_url`. Was er an
    Adressen anhaengt, kommt aus dem Gedaechtnis des Modells. Hier antwortet
    ein geskripteter Fake genau so wie das echte Modell damals - und was
    hinten rauskommt, darf die Links nicht mehr enthalten.
    """
    from core.agents import baue_agenten
    from core.contracts import Permission, Step, Task
    from core.llm import FakeLLMProvider
    from tests.conftest import run

    provider = FakeLLMProvider(replies=[DER_ECHTE_FALL])
    satellit = baue_agenten(provider, max_permission=Permission.READ)["satellite"]

    # Kein Netzwerkzeug - genau der Punkt.
    assert "web_search" not in satellit.tools
    assert "fetch_url" not in satellit.tools

    task = Task(goal="Zeig mir Deutschland von oben")
    schritt = Step(id=1, description="Sentinel-2-Bild holen")
    ergebnis = run(satellit.run(task, schritt))

    assert "http" not in ergebnis.display
    assert "Link(e) entfernt" in ergebnis.display
    # Der Inhalt der Meldung bleibt - nur die Quellenbehauptung faellt.
    assert "Zugangsdaten" in ergebnis.display
    assert ergebnis.sources == []


def test_nur_die_weltlage_ist_vom_filter_ausgenommen():
    """Die Ausnahme in beide Richtungen festgenagelt.

    `weltlage` liefert JSON an einen Parser - dort eine URL herauszuschneiden
    zerstoert den Datensatz, statt eine Behauptung zu entschaerfen. Gemessen:
    ohne diese Ausnahme fielen 21 Weltlage-Tests, weil `core/weltlage.py`
    jede Meldung ohne gueltige `quell_url` verwirft.

    Umgekehrt darf die Ausnahme nicht auf andere ueberspringen: jeder Agent,
    dessen Antwort ein Mensch liest, wird geprueft.
    """
    from core.agents import baue_agenten
    from core.contracts import Permission
    from core.llm import FakeLLMProvider

    agenten = baue_agenten(FakeLLMProvider(), max_permission=Permission.READ)
    ohne_filter = sorted(
        name for name, a in agenten.items() if not a._links_pruefen
    )
    assert ohne_filter == ["weltlage"]


def test_die_weltlage_behaelt_ihre_links():
    from core.agents import baue_agenten
    from core.contracts import Permission, Step, Task
    from core.llm import FakeLLMProvider
    from tests.conftest import run

    json_mit_url = (
        '{"meldungen": [{"schlagzeile": "x", "medium": "Tagesschau", '
        '"quell_url": "https://www.tagesschau.de/artikel"}]}'
    )
    welt = baue_agenten(
        FakeLLMProvider(replies=[json_mit_url]), max_permission=Permission.READ
    )["weltlage"]
    ergebnis = run(welt.run(Task(goal="Lage"), Step(id=1, description="Lage")))
    assert "https://www.tagesschau.de/artikel" in ergebnis.display
    assert "Link(e) entfernt" not in ergebnis.display
