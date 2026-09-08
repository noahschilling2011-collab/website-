"""Gemeinsame Einrichtungsdiagnose fuer CLI und Health, ohne Netzwerk.

`konfiguriert` bestaetigt nur lokale Einstellungen, nie Erreichbarkeit oder
gueltige Zugangsdaten bei einem Dienst. Kein Ergebnis enthaelt Secret-Werte,
Kalenderadressen oder absolute Dateipfade.
"""

from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlsplit

from core.config import Settings
from core.dateien import wurzeln_aus


def token_fehler(token: str) -> str | None:
    if any(ord(c) < 32 or ord(c) == 127 for c in token):
        return "JARVIS_TOKEN darf keine Steuerzeichen im HTTP-Header enthalten."
    if token.strip() == "bitte-hier-einen-langen-zufallswert-eintragen":
        return "JARVIS_TOKEN ist noch der oeffentliche Platzhalter. Lokal neu erzeugen."
    try:
        token.encode("latin-1")
    except UnicodeEncodeError:
        return "JARVIS_TOKEN enthaelt Zeichen, die nicht in einen HTTP-Header passen."
    return None


def _zustand(status: str, hinweis: str) -> dict[str, str]:
    return {"status": status, "hinweis": hinweis}


def _kalender(quelle: str) -> dict[str, str]:
    if not quelle.strip():
        return _zustand("nicht_eingerichtet", "KALENDER_QUELLE fehlt; Termine sind unbekannt.")
    try:
        if quelle.lower().startswith(("http://", "https://")):
            url = urlsplit(quelle)
            if url.scheme != "https" or not url.hostname or url.username or url.password:
                return _zustand("ungueltig", "Kalender-Abo braucht eine HTTPS-Adresse ohne Benutzerinfo.")
            return _zustand("konfiguriert", "Kalender-Abo eingetragen; kein Abruf bei der Diagnose.")
        # Nur eine begrenzte lokale Formatpruefung. Weder Kalenderinhalte noch
        # Titel werden aus der Diagnose ausgegeben oder gespeichert.
        with Path(quelle).expanduser().open(encoding="utf-8-sig") as datei:
            kopf = datei.read(4096)
        if not kopf.lstrip().startswith("BEGIN:VCALENDAR"):
            return _zustand("ungueltig", "Lokale Kalenderquelle beginnt nicht mit BEGIN:VCALENDAR.")
        return _zustand("konfiguriert", "Lokale ICS-Datei lesbar; das Kalenderwerkzeug prueft die Termine.")
    except (OSError, ValueError, UnicodeError):
        return _zustand("ungueltig", "KALENDER_QUELLE ist lokal nicht lesbar oder ungueltig.")


def integrationen(settings: Settings) -> dict[str, dict[str, str]]:
    """Konfiguration pruefen, ohne Provider zu bauen oder Werkzeuge aufzurufen."""
    ergebnis: dict[str, dict[str, str]] = {}
    problem = token_fehler(settings.jarvis_token)
    if problem:
        ergebnis["zugang"] = _zustand("ungueltig", problem)
    elif not settings.jarvis_token.strip():
        ergebnis["zugang"] = _zustand("temporaer", "JARVIS_TOKEN fehlt; Zugang wechselt beim Neustart.")
    elif len(settings.jarvis_token.strip()) < 32:
        ergebnis["zugang"] = _zustand("pruefen", "JARVIS_TOKEN ist kurz; einen langen Zufallswert verwenden.")
    else:
        ergebnis["zugang"] = _zustand("konfiguriert", "Dauerhafter Zugangstoken gesetzt; Wert bleibt geheim.")

    # Die Namen kommen aus derselben Registry wie build_provider.
    from core.llm import PROVIDERS

    anbieter = settings.llm_provider.strip().lower()
    if not anbieter:
        ergebnis["llm"] = _zustand("nicht_eingerichtet", "LLM nicht eingerichtet: LLM_PROVIDER fehlt.")
    elif anbieter == "fake":
        ergebnis["llm"] = _zustand("demo", "Expliziter Fake-Modus; kein echtes Modell und keine echte Auftragsantwort.")
    elif anbieter not in PROVIDERS:
        ergebnis["llm"] = _zustand("ungueltig", "LLM_PROVIDER wird nicht unterstuetzt.")
    else:
        fehlt = [name for name, wert in (("LLM_API_KEY", settings.llm_api_key),
                                         ("LLM_MODEL", settings.llm_model)) if not wert.strip()]
        ergebnis["llm"] = _zustand("nicht_eingerichtet", "LLM nicht eingerichtet: " + ", ".join(fehlt) + " fehlt.") if fehlt else _zustand(
            "konfiguriert", "Anbieter, Modell und Key gesetzt; kein Modellaufruf bei der Diagnose.")

    roh = [p for p in settings.datei_wurzeln.split(os.pathsep) if p.strip()]
    try:
        gueltig = wurzeln_aus(settings.datei_wurzeln)
    except (OSError, ValueError):
        gueltig = []
    if not roh:
        ergebnis["dateien"] = _zustand("nicht_eingerichtet", "DATEI_WURZELN fehlt; kein Dateizugriff freigegeben.")
    elif len(gueltig) != len(roh):
        ergebnis["dateien"] = _zustand("teilweise" if gueltig else "ungueltig",
            f"DATEI_WURZELN: {len(gueltig)} von {len(roh)} Ordnern vorhanden; Pfade und Trennzeichen pruefen.")
    else:
        ergebnis["dateien"] = _zustand("konfiguriert", f"{len(gueltig)} freigegebene Ordner vorhanden; Zugriff bleibt lesend.")
    if any(p == Path(p.anchor) or p == Path.home() for p in gueltig):
        ergebnis["dateien"] = _zustand("pruefen", "DATEI_WURZELN umfasst eine System- oder Benutzerwurzel; auf benoetigte Unterordner begrenzen.")

    ergebnis["kalender"] = _kalender(settings.kalender_quelle)
    ergebnis["wetter"] = _zustand("konfiguriert", "JARVIS_ORT gesetzt; Open-Meteo braucht Netz, keinen API-Key.") if settings.jarvis_ort.strip() else _zustand(
        "nicht_eingerichtet", "JARVIS_ORT fehlt; Wetter braucht einen expliziten Ort.")
    ergebnis["erinnerungen"] = _zustand("bereit", "Zustellung ohne LLM, solange JARVIS laeuft.") if settings.zeitplan_takt_s else _zustand(
        "deaktiviert", "ZEITPLAN_TAKT_S=0: automatische Zustellung aus; manuelles Ausloesen bleibt moeglich.")
    ergebnis["auftraege"] = dict(ergebnis["llm"])
    ergebnis["gedaechtnis"] = _zustand("lokal", "SQLite-Gedaechtnis; Datenbankzustand steht separat in Health.")
    if settings.vault_pfad:
        try:
            vorhanden = Path(settings.vault_pfad).expanduser().is_dir()
        except (OSError, ValueError):
            vorhanden = False
        ergebnis["gedaechtnis"] = _zustand("konfiguriert" if vorhanden else "ungueltig",
            "Obsidian-Vault vorhanden; SQLite ist der abgeleitete Index." if vorhanden else "VAULT_PFAD ist kein vorhandener Ordner.")
    ergebnis["wiki_lokal"] = _zustand("konfiguriert", "Kiwix/ZIM eingetragen; lokaler Dienst nicht abgefragt.") if settings.wiki_zim.strip() else _zustand(
        "nicht_eingerichtet", "WIKI_ZIM fehlt; lokale Wikipedia nicht eingerichtet.")
    ergebnis["wiki_live"] = _zustand("konfiguriert", "Kontakt eingetragen; Wikimedia nicht abgefragt.") if settings.wiki_kontakt.strip() else _zustand(
        "nicht_eingerichtet", "WIKI_KONTAKT fehlt fuer wiki_live und wikidata.")
    ergebnis["websuche"] = _zustand("konfiguriert", "SEARCH_API_KEY gesetzt; Suchdienst nicht abgefragt.") if settings.search_api_key.strip() else _zustand(
        "nicht_eingerichtet", "SEARCH_API_KEY fehlt.")
    ergebnis["weltlage"] = _zustand("konfiguriert", "LLM und Suche eingetragen; echte Meldungen noch nicht geprueft.") if (
        ergebnis["llm"]["status"] == "konfiguriert" and settings.search_api_key.strip()) else _zustand(
        "nicht_eingerichtet", "Aktuelle Weltlage braucht ein echtes LLM und SEARCH_API_KEY; vorhandener Cache bleibt lesbar.")
    ergebnis["satellitenbilder"] = _zustand("konfiguriert", "CDSE-Werte gesetzt; Zugang und Kontingent nicht geprueft.") if (
        settings.cdse_client_id.strip() and settings.cdse_client_secret.strip()) else _zustand(
        "nicht_eingerichtet", "CDSE-Zugangsdaten fehlen: CDSE_CLIENT_ID und CDSE_CLIENT_SECRET erforderlich.")
    ergebnis["satellitenkatalog"] = _zustand("ohne_key", "Szenensuche und TLE-Ueberfluege brauchen Netz oder Cache, keine CDSE-Credentials.")
    ergebnis["ndvi"] = _zustand("blockiert", "Rasterbeschaffung nicht implementiert; keine NDVI-Werte erfinden.")
    return ergebnis
