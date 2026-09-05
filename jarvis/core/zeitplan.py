"""Zeitplaene: Auftraege, die JARVIS von selbst wiederholt (FIX-08).

Was das ist - und was nicht
---------------------------

Ein Zeitplan ist ein Auftragstext plus eine Regel, wann er laeuft. Zur Zeit
legt JARVIS daraus einen ganz normalen Task an und schickt ihn durch dieselbe
Kette wie einen getippten: Planer, Runner, Agenten, Werkzeuge, Budgets.
Nichts davon ist neu. Neu ist nur, dass niemand tippen muss.

Es ist KEIN Computer-Agent. CLAUDE.md streicht "Programme oder UI steuern"
dauerhaft, und daran aendert diese Datei nichts: JARVIS wiederholt seine
EIGENEN Auftraege, mehr nicht.

Die drei Regeln, die diese Datei wichtiger machen als ihre Groesse
------------------------------------------------------------------

1. NIEMAND IST DA, UM ZU BESTAETIGEN. Ein getippter Auftrag darf bis
   EXTERNAL gehen, weil der Nutzer vor dem Bildschirm sitzt und
   `send_email` per Rueckfrage freigibt. Ein Zeitplan laeuft um 07:00,
   waehrend der Nutzer schlaeft. Deshalb ist die Obergrenze hier LOCAL -
   hart, unabhaengig davon, was MAX_PERMISSION in der .env sagt. Siehe
   `PERMISSION_DECKEL`.

2. EIN ZEITPLAN KANN GELD VERBRENNEN, OHNE DASS ES JEMAND MERKT. Ein
   Auftrag, der jede Stunde laeuft und jedes Mal 8.000 Token kostet, frisst
   das Tageskontingent der freien Groq-Stufe (200.000) in einem Tag - und
   zwar still. Deshalb ein Deckel ueber ALLE Zeitplaene zusammen, ueber die
   letzten 24 Stunden, in Laeufen UND Token. Ist er erreicht, laeuft nichts
   mehr, und der Grund steht am Zeitplan.

3. VERPASSTE LAEUFE WERDEN NICHT NACHGEHOLT. War der Rechner um 07:00 aus,
   laeuft der Auftrag um 07:00 am naechsten Tag - nicht "sofort beim
   naechsten Start". Nachholen klingt freundlich, ist aber genau die Art
   Ueberraschung, die Regel 2 verhindern will: der Nutzer startet den
   Rechner, und drei Zeitplaene feuern gleichzeitig. Der verpasste Lauf
   wird gezaehlt (`verpasst`) und angezeigt, nicht verschwiegen.

Was die zweite Pruefrunde dazu gebracht hat (docs/FIX-08.md)
------------------------------------------------------------

- DER TERMIN IST DIE SPERRE. Bevor ein Lauf startet, wird der Termin in
  EINER Anweisung weitergeschoben - und nur, wenn er noch der alte ist
  (`termin_weiter`). Wer den alten Termin nicht mehr vorfindet, startet
  nicht. Das haelt auch ueber Prozessgrenzen, und ein Absturz zwischen
  Buchung und Start kann keinen zweiten Lauf mehr erzeugen.
- DAS PROTOKOLL UEBERLEBT DEN PLAN. `zeitplan_laeufe.zeitplan_id` wird
  beim Loeschen NULL, nicht mitgeloescht - sonst liesse sich der
  Tagesdeckel durch Loeschen und Neuanlegen zuruecksetzen.
- LAUFENDE TASKS ZAEHLEN MIT IHREM BUDGET, nicht mit dem, was zufaellig
  schon in der Datenbank steht (`verbrauch_24h(reserviert=...)`).
- EIN LAUF BRAUCHT EINEN MINDESTREST (`MINDEST_REST`). Ein Token uebrig
  heisst: der Planungszug kostet, dann Abbruch - das ist kein Lauf.
- VERPASST ZAEHLT TERMINE, NICHT RUNDEN (`verpasste_termine`), und der
  naechste Takt zaehlt ab dem Soll - auch nach einem verpassten Lauf.

Zeit und Zeitzone
-----------------

"taeglich 07:00" meint die ORTSZEIT des Rechners, auf dem JARVIS laeuft -
dieselbe Zone, in der der Kalender anzeigt (`core/kalender.in_anzeigezone`).
Gespeichert wird in UTC mit 'Z', im selben Format wie `core/db.utcnow()`,
damit Zeichenkettenvergleiche in SQL stimmen.

UNSICHER, bewusst dokumentiert: die Ortszeit kommt aus
`datetime.now().astimezone()`, und das ist ein FESTER Versatz zum Zeitpunkt
der Berechnung, keine IANA-Zone. Der naechste Lauf wird nach JEDEM Lauf neu
gerechnet - also stimmt die Uhrzeit wieder ab dem zweiten Lauf nach einer
Zeitumstellung. Der eine Lauf direkt nach dem Wechsel kann eine Stunde
danebenliegen. Eine IANA-Zone braeuchte den Zonennamen des Systems, und den
gibt die Standardbibliothek unter Windows nicht her.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from core.contracts import Permission
from core.db import session, utcnow

# Regel 1. Hart, keine Einstellung. Wer das aendern will, aendert es hier,
# mit Begruendung - und nicht ueber eine .env-Zeile um drei Uhr nachts.
PERMISSION_DECKEL = Permission.LOCAL

# Regel 3: wie lange ein Lauf "faellig" bleibt, bevor er als verpasst gilt.
# Die Schleife prueft jede Minute; zwei Minuten Toleranz decken einen
# langsamen Start ab, ohne dass ein Rechner, der drei Stunden aus war, beim
# Hochfahren drei Zeitplaene auf einmal loest.
TOLERANZ = timedelta(minutes=2)


def toleranz_fuer(takt_s: int | float, max_seconds: int | float = 0) -> timedelta:
    """Die Toleranz muss zum Takt UND zur Laufzeit passen.

    Prueft die Schleife nur alle 180 Sekunden, waere jeder Lauf mit fester
    2-Minuten-Toleranz "verpasst" - taeglich. Und weil Zeitplaene
    NACHEINANDER laufen (api/zeitplan.py), kann ein Plan, der waehrend eines
    anderen Laufs faellig wird, erst nach dessen Ende drankommen - also
    kommt die laengste erlaubte Laufzeit eines Auftrags dazu. Nach oben ist
    das begrenzt, weil ZEITPLAN_TAKT_S hoechstens 300 sein darf
    (core/config.py): sonst wuerde aus der Toleranz ein Nachholen.
    """
    grund = max(TOLERANZ, timedelta(seconds=2 * max(0, float(takt_s))))
    return grund + timedelta(seconds=max(0, float(max_seconds)))


# Unter so vielen Token uebrig startet kein Lauf mehr: der Planungszug
# allein kostet einige hundert, danach kaeme sofort "max_tokens erreicht" -
# ein bezahlter Abbruch mit zwei Chat-Nachrichten und ohne Ergebnis.
MINDEST_REST = 2_000

_TAEGLICH = re.compile(r"^taeglich (\d{1,2}):(\d{2})$")
_STUNDEN = re.compile(r"^alle (\d{1,3}) stunden?$")
# FIX-09: einmalig. "einmal 2026-09-06 18:00" - das Wort "einmal" darf
# fehlen, ein Datum mit Uhrzeit ist eindeutig genug.
_EINMAL = re.compile(r"^(?:einmal )?(\d{4})-(\d{2})-(\d{2}) (\d{1,2}):(\d{2})$")

# FIX-09: mehr Plaene als das braucht niemand - und ein Modell, das ueber
# erinnerung_anlegen Plaene anlegt, soll nicht unbegrenzt welche erzeugen.
MAX_PLAENE = 50
# FIX-09: nach so vielen Fehlschlaegen in Folge pausiert ein Plan sich
# selbst, mit Grund - statt jeden Morgen Planer-Token zu verbrennen.
MAX_FEHLSCHLAEGE = 3


class RegelUngueltig(ValueError):
    """Die Regel ist keine der zwei erlaubten Formen."""


@dataclass(frozen=True)
class Regel:
    art: str            # 'taeglich' | 'stunden' | 'einmal'
    stunde: int = 0     # taeglich, einmal: 0..23
    minute: int = 0     # taeglich, einmal: 0..59
    alle: int = 0       # stunden: 1..168
    datum: str = ""     # einmal: JJJJ-MM-TT (Ortszeit)

    @property
    def text(self) -> str:
        if self.art == "taeglich":
            return f"taeglich {self.stunde:02d}:{self.minute:02d}"
        if self.art == "einmal":
            return f"einmal {self.datum} {self.stunde:02d}:{self.minute:02d}"
        return f"alle {self.alle} stunden"

    @property
    def einmalig(self) -> bool:
        return self.art == "einmal"


def lies_regel(roh: str) -> Regel:
    """Genau zwei Formen. Alles andere ist ein Fehler, kein Ratespiel.

    Umlaute werden hingenommen ("täglich"), Gross-/Kleinschreibung und
    doppelte Leerzeichen auch. Aber "jeden Morgen" oder "*/6 * * * *" nicht:
    wer Cron will, bekommt eine klare Absage statt einer stillen
    Fehldeutung.
    """
    text = " ".join(str(roh or "").strip().lower().split())
    text = text.replace("täglich", "taeglich").replace("stunde ", "stunden ")
    # Was in der Absage zitiert wird: hoechstens 40 Zeichen. Wer 10.000
    # Zeichen in das Regelfeld schiebt, bekommt sie nicht zurueckgespiegelt.
    roh = str(roh or "")
    roh = roh if len(roh) <= 40 else roh[:40] + "…"
    m = _TAEGLICH.match(text)
    if m:
        h, mi = int(m.group(1)), int(m.group(2))
        if not (0 <= h <= 23 and 0 <= mi <= 59):
            raise RegelUngueltig(f"'{roh}': Uhrzeit ausserhalb von 00:00 bis 23:59.")
        return Regel(art="taeglich", stunde=h, minute=mi)
    m = _STUNDEN.match(text)
    if m:
        n = int(m.group(1))
        if not (1 <= n <= 168):
            raise RegelUngueltig(f"'{roh}': zwischen 1 und 168 Stunden (eine Woche).")
        return Regel(art="stunden", alle=n)
    m = _EINMAL.match(text)
    if m:
        j, mo, t, h, mi = (int(g) for g in m.groups())
        try:
            datetime(j, mo, t, h, mi)
        except ValueError as exc:
            raise RegelUngueltig(f"'{roh}': kein gueltiger Zeitpunkt ({exc}).") from exc
        return Regel(art="einmal", stunde=h, minute=mi, datum=f"{j:04d}-{mo:02d}-{t:02d}")
    raise RegelUngueltig(
        f"'{roh}' verstehe ich nicht. Erlaubt sind genau drei Formen: "
        f"'taeglich 07:00', 'alle 6 stunden' oder 'einmal 2026-09-06 18:00'."
    )


def _als_z(zeit: datetime) -> str:
    """Dasselbe Format wie core/db.utcnow(), damit SQL-Vergleiche stimmen."""
    return (zeit.astimezone(timezone.utc)
            .isoformat(timespec="seconds").replace("+00:00", "Z"))


def _aus_z(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def naechster_lauf(regel: Regel, ab: datetime | None = None,
                   letzter: datetime | None = None) -> str:
    """Wann der naechste Lauf faellig ist, als UTC-'Z'-Zeichenkette.

    `ab` ist "jetzt" (Test: einstellbar). `letzter` ist der letzte Lauf -
    bei 'alle N stunden' zaehlt es ab dort, sonst ab jetzt. So bleibt ein
    Stundentakt ein Takt und driftet nicht mit jeder Schleifenverzoegerung.
    """
    jetzt = (ab or datetime.now(timezone.utc)).astimezone(timezone.utc)
    if regel.art == "einmal":
        # Ein fester Zeitpunkt in Ortszeit - ob er noch kommt, prueft
        # `anlegen`; hier wird er nur umgerechnet.
        j, mo, t = (int(x) for x in regel.datum.split("-"))
        lokal = datetime(j, mo, t, regel.stunde, regel.minute).astimezone()
        return _als_z(lokal)
    if regel.art == "taeglich":
        # Ortszeit des Rechners - dieselbe Zone wie die Kalenderanzeige.
        # Siehe den UNSICHER-Absatz im Modulkopf zur Zeitumstellung.
        lokal = jetzt.astimezone()
        kandidat = lokal.replace(hour=regel.stunde, minute=regel.minute,
                                 second=0, microsecond=0)
        if kandidat <= lokal:
            kandidat += timedelta(days=1)
        return _als_z(kandidat)
    basis = (letzter.astimezone(timezone.utc) if letzter else jetzt)
    kandidat = basis + timedelta(hours=regel.alle)
    # Regel 3: liegt der Takt schon in der Vergangenheit (Rechner war aus),
    # springen wir NICHT auf "jetzt", sondern auf den naechsten Takt danach.
    while kandidat <= jetzt:
        kandidat += timedelta(hours=regel.alle)
    return _als_z(kandidat)


# --- Datenbank -------------------------------------------------------------


ARTEN = ("auftrag", "erinnerung")


def _zeit_existiert(regel: Regel) -> bool:
    """FIX-09: '02:30' am Tag der Zeitumstellung gibt es nicht - Python legt
    sie still eine Stunde frueher. Rueckrechnung entlarvt das."""
    if not regel.einmalig:
        return True
    j, mo, t = (int(x) for x in regel.datum.split("-"))
    naiv = datetime(j, mo, t, regel.stunde, regel.minute)
    return naiv.astimezone().replace(tzinfo=None) == naiv


def anlegen(db_path: Path | str, *, name: str, ziel: str, regel_text: str,
            art: str = "auftrag") -> dict:
    regel = lies_regel(regel_text)
    name = " ".join(str(name or "").split())[:80]
    ziel = str(ziel or "").strip()
    if not name:
        raise ValueError("Ein Zeitplan braucht einen Namen.")
    if not ziel:
        raise ValueError("Ein Zeitplan braucht einen Auftragstext.")
    if art not in ARTEN:
        raise ValueError(f"Unbekannte Art {art!r}.")
    termin = naechster_lauf(regel)
    if regel.einmalig and termin <= utcnow():
        raise RegelUngueltig(f"'{regel.text}' liegt in der Vergangenheit.")
    if not _zeit_existiert(regel):
        raise RegelUngueltig(f"'{regel.text}': diese Uhrzeit gibt es an dem Tag nicht "
                             f"(Zeitumstellung). Nimm eine Stunde spaeter.")
    eintrag = {
        "id": uuid.uuid4().hex[:12],
        "name": name,
        "ziel": ziel,
        "regel": regel.text,
        "aktiv": 1,
        "erstellt_am": utcnow(),
        "naechster_lauf": termin,
        "letzter_lauf": None,
        "letzter_task_id": None,
        "letzter_status": None,
        "verpasst": 0,
        "fehlschlaege": 0,
        "art": art,
        "max": MAX_PLAENE,
    }
    with session(db_path) as conn:
        # Obergrenze und Einfuegen in EINER Anweisung: zwei gleichzeitige
        # Aufrufer koennen sie sonst beide unterlaufen. Gezaehlt werden nur
        # LEBENDE Plaene - erledigte Erinnerungen fuellen die Grenze nicht.
        cur = conn.execute(
            "INSERT INTO zeitplaene (id, name, ziel, regel, aktiv, erstellt_am, "
            "naechster_lauf, letzter_lauf, letzter_task_id, letzter_status, verpasst, "
            "fehlschlaege, art) "
            "SELECT :id, :name, :ziel, :regel, :aktiv, :erstellt_am, :naechster_lauf, "
            ":letzter_lauf, :letzter_task_id, :letzter_status, :verpasst, :fehlschlaege, :art "
            "WHERE (SELECT COUNT(*) FROM zeitplaene "
            "       WHERE aktiv = 1 OR naechster_lauf IS NOT NULL) < :max",
            eintrag,
        )
        if cur.rowcount == 0:
            raise ValueError(f"Hoechstens {MAX_PLAENE} aktive Zeitplaene. Loesche oder "
                             f"schalte erst einen aus.")
    eintrag.pop("max")
    return eintrag


def alle(db_path: Path | str) -> list[dict]:
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT * FROM zeitplaene ORDER BY erstellt_am"
        ).fetchall()
    return [dict(z) for z in zeilen]


def hole(db_path: Path | str, zeitplan_id: str) -> dict | None:
    with session(db_path) as conn:
        z = conn.execute("SELECT * FROM zeitplaene WHERE id = ?",
                         (zeitplan_id,)).fetchone()
    return dict(z) if z else None


def loeschen(db_path: Path | str, zeitplan_id: str) -> bool:
    with session(db_path) as conn:
        cur = conn.execute("DELETE FROM zeitplaene WHERE id = ?", (zeitplan_id,))
    return cur.rowcount > 0


def schalten(db_path: Path | str, zeitplan_id: str, aktiv: bool) -> dict | None:
    """An oder aus. Beim Einschalten wird der naechste Lauf NEU gerechnet -
    sonst feuert ein Zeitplan, der drei Tage aus war, sofort (Regel 3)."""
    plan = hole(db_path, zeitplan_id)
    if plan is None:
        return None
    if aktiv and plan["aktiv"] and plan.get("naechster_lauf"):
        # Schon an: nichts anfassen. Sonst schiebt ein zweiter Klick (oder
        # ein zweiter Browser-Tab) einen faelligen Termin still auf morgen.
        return plan
    regel = lies_regel(plan["regel"])
    naechster = naechster_lauf(regel) if aktiv else None
    if aktiv and regel.einmalig and naechster <= utcnow():
        # Eine Erinnerung, deren Zeitpunkt vorbei ist, laesst sich nicht
        # wieder einschalten - sie wuerde sofort als verpasst gebucht. Der
        # Status bleibt, wie er war ('done' ist eine Wahrheit, keine
        # Anzeige); der Grund geht als Fehler an den Aufrufer.
        raise RegelUngueltig("Diese Erinnerung ist einmalig und ihr Zeitpunkt ist vorbei. "
                             "Leg eine neue an.")
    with session(db_path) as conn:
        # FIX-09: Einschalten setzt die Fehlschlaege zurueck - das ist der
        # Weg, einen selbst pausierten Plan wieder laufen zu lassen.
        conn.execute(
            "UPDATE zeitplaene SET aktiv = ?, naechster_lauf = ?, "
            "fehlschlaege = CASE WHEN ? THEN 0 ELSE fehlschlaege END WHERE id = ?",
            (1 if aktiv else 0, naechster, 1 if aktiv else 0, zeitplan_id),
        )
    return hole(db_path, zeitplan_id)


def faellige(db_path: Path | str, jetzt: datetime | None = None) -> list[dict]:
    """Aktive Zeitplaene, deren naechster Lauf jetzt oder frueher ist."""
    grenze = _als_z(jetzt or datetime.now(timezone.utc))
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT * FROM zeitplaene WHERE aktiv = 1 AND naechster_lauf IS NOT NULL "
            "AND naechster_lauf <= ? ORDER BY naechster_lauf",
            (grenze,),
        ).fetchall()
    return [dict(z) for z in zeilen]


def ist_verpasst(plan: dict, jetzt: datetime | None = None,
                 toleranz: timedelta | None = None) -> bool:
    """Regel 3: faellig seit laenger als die Toleranz heisst verpasst, nicht
    nachholen. Passiert, wenn der Rechner aus war. Die Schleife gibt
    `toleranz_fuer(takt)` mit; ohne Angabe gilt TOLERANZ."""
    if not plan.get("naechster_lauf"):
        return False
    soll = _aus_z(plan["naechster_lauf"])
    ist = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    return ist - soll > (toleranz or TOLERANZ)


def termin_weiter(db_path: Path | str, plan: dict, status: str,
                  jetzt: datetime | None = None) -> bool:
    """Den Termin weiterschieben - in EINER Anweisung, und nur, wenn er noch
    der ist, den der Aufrufer gelesen hat. Das ist die Sperre gegen jeden
    Doppelstart: wer False bekommt, war zu spaet (ein anderer Aufrufer, ein
    anderer Prozess, oder der Nutzer hat den Plan inzwischen ausgeschaltet).

    Der naechste Takt zaehlt ab dem SOLL-Termin, nicht ab jetzt: sonst
    schiebt jede Runde den Takt um ihre Verzoegerung nach hinten (erste
    Pruefrunde, Fund 4 - 18 Minuten am Tag).
    """
    if not plan.get("naechster_lauf"):
        return False
    regel = lies_regel(plan["regel"])
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    soll = _aus_z(plan["naechster_lauf"])
    with session(db_path) as conn:
        if regel.einmalig:
            # Erledigt heisst erledigt: kein naechster Termin, Plan aus.
            cur = conn.execute(
                "UPDATE zeitplaene SET naechster_lauf = NULL, aktiv = 0, letzter_status = ? "
                "WHERE id = ? AND naechster_lauf = ? AND aktiv = 1",
                (status, plan["id"], plan["naechster_lauf"]),
            )
        else:
            cur = conn.execute(
                "UPDATE zeitplaene SET naechster_lauf = ?, letzter_status = ? "
                "WHERE id = ? AND naechster_lauf = ? AND aktiv = 1",
                (naechster_lauf(regel, ab=zeitpunkt, letzter=soll), status,
                 plan["id"], plan["naechster_lauf"]),
            )
    return cur.rowcount > 0


def setze_status(db_path: Path | str, zeitplan_id: str, status: str) -> None:
    with session(db_path) as conn:
        conn.execute("UPDATE zeitplaene SET letzter_status = ? WHERE id = ?",
                     (status, zeitplan_id))


def verbuche_start(db_path: Path | str, plan: dict, task_id: str,
                   *, ausloeser: str, status: str = "laeuft",
                   jetzt: datetime | None = None) -> None:
    """Ein Lauf hat begonnen: Protokollzeile und letzter Lauf am Plan.

    Den Termin fasst diese Funktion NICHT an. Fuer die Schleife hat ihn
    `termin_weiter` schon vor dem Start weitergeschoben (die Sperre); ein
    Handlauf ("Jetzt") laesst ihn ohnehin, wie er ist. Beide zaehlen fuer
    den Deckel - Token sind Token, egal wer den Lauf ausgeloest hat.

    Geschrieben wird nur, was sich aendert: der `plan` des Aufrufers kann
    Sekunden alt sein.
    """
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    with session(db_path) as conn:
        conn.execute(
            "INSERT INTO zeitplan_laeufe (zeitplan_id, task_id, gestartet_am, "
            "ausloeser) VALUES (?, ?, ?, ?)",
            (plan["id"], task_id, _als_z(zeitpunkt), ausloeser),
        )
        conn.execute(
            "UPDATE zeitplaene SET letzter_lauf = ?, letzter_task_id = ?, "
            "letzter_status = ? WHERE id = ?",
            (_als_z(zeitpunkt), task_id, status, plan["id"]),
        )


def verbuche_erinnerung(db_path: Path | str, plan: dict, *, ausloeser: str,
                        jetzt: datetime | None = None) -> None:
    """FIX-09: eine Erinnerung wurde zugestellt - ohne Task. Protokollzeile
    ohne task_id (zaehlt fuer den Laeufe-Deckel, kostet null Token) und
    'done' am Plan. Den Termin hat `termin_weiter` schon weitergeschoben
    bzw. bei einmalig auf NULL gesetzt."""
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    with session(db_path) as conn:
        conn.execute(
            "INSERT INTO zeitplan_laeufe (zeitplan_id, task_id, gestartet_am, ausloeser) "
            "VALUES (?, NULL, ?, ?)",
            (plan["id"], _als_z(zeitpunkt), ausloeser),
        )
        conn.execute(
            "UPDATE zeitplaene SET letzter_lauf = ?, letzter_status = 'done' WHERE id = ?",
            (_als_z(zeitpunkt), plan["id"]),
        )


def verpasste_termine(regel: Regel, soll: datetime, jetzt: datetime) -> int:
    """Wie viele Termine zwischen Soll (einschliesslich) und jetzt lagen.
    Drei Tage aus heisst bei 'taeglich' vier verpasste Termine, nicht einer.
    Bei 'taeglich' ueber 24-Stunden-Schritte gerechnet - an einem
    Zeitumstellungstag kann das um einen danebenliegen (siehe UNSICHER im
    Modulkopf)."""
    if jetzt < soll:
        return 0
    if regel.einmalig:
        return 1
    schritt = timedelta(days=1) if regel.art == "taeglich" else timedelta(hours=regel.alle)
    return int((jetzt - soll) // schritt) + 1


def verbuche_verpasst(db_path: Path | str, plan: dict,
                      jetzt: datetime | None = None) -> bool:
    """Regel 3, die Buchung: Termine zaehlen, Takt ab Soll weiterschieben,
    nicht starten. Dieselbe Sperre wie `termin_weiter`: nur, wenn der
    Termin noch der gelesene ist und der Plan an ist."""
    if not plan.get("naechster_lauf"):
        return False
    regel = lies_regel(plan["regel"])
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    soll = _aus_z(plan["naechster_lauf"])
    anzahl = verpasste_termine(regel, soll, zeitpunkt)
    status = f"verpasst ({plan['naechster_lauf']}), nicht nachgeholt"
    with session(db_path) as conn:
        if regel.einmalig:
            cur = conn.execute(
                "UPDATE zeitplaene SET verpasst = verpasst + ?, letzter_status = ?, "
                "naechster_lauf = NULL, aktiv = 0 "
                "WHERE id = ? AND naechster_lauf = ? AND aktiv = 1",
                (anzahl, status, plan["id"], plan["naechster_lauf"]),
            )
        else:
            cur = conn.execute(
                "UPDATE zeitplaene SET verpasst = verpasst + ?, "
                "letzter_status = ?, naechster_lauf = ? "
                "WHERE id = ? AND naechster_lauf = ? AND aktiv = 1",
                (anzahl, status, naechster_lauf(regel, ab=zeitpunkt, letzter=soll),
                 plan["id"], plan["naechster_lauf"]),
            )
    return cur.rowcount > 0


FEHLSCHLAG = ("failed", "aborted_budget")


def nachtrag_ergebnis(db_path: Path | str, task_id: str, status: str) -> None:
    """Wenn der Task fertig ist: den Ausgang an den Zeitplan schreiben, damit
    die Liste 'done' oder 'failed' zeigt und nicht ewig 'laeuft'.

    FIX-09, die Bremse: Fehlschlaege in Folge werden gezaehlt ('done' setzt
    zurueck). Ab MAX_FEHLSCHLAEGE schaltet sich der Plan aus und sagt
    warum - ein Plan, der jeden Morgen an einem fehlenden Kalender
    scheitert, verbrennt sonst taeglich Planer-Token, und niemand merkt es.
    Einschalten setzt den Zaehler zurueck (`schalten`).
    """
    with session(db_path) as conn:
        conn.execute(
            "UPDATE zeitplaene SET letzter_status = ?, "
            "fehlschlaege = CASE WHEN ? THEN fehlschlaege + 1 "
            "                    WHEN ? THEN 0 ELSE fehlschlaege END "
            "WHERE letzter_task_id = ?",
            (status, 1 if status in FEHLSCHLAG else 0, 1 if status == "done" else 0,
             task_id),
        )
        z = conn.execute(
            "SELECT id, fehlschlaege, aktiv FROM zeitplaene WHERE letzter_task_id = ?",
            (task_id,),
        ).fetchone()
        if z and z["aktiv"] and z["fehlschlaege"] >= MAX_FEHLSCHLAEGE:
            conn.execute(
                "UPDATE zeitplaene SET aktiv = 0, naechster_lauf = NULL, letzter_status = ? "
                "WHERE id = ?",
                (f"pausiert nach {z['fehlschlaege']} Fehlschlaegen in Folge ({status}). "
                 f"Einschalten setzt den Zaehler zurueck.", z["id"]),
            )


ENDZUSTAENDE = ("done", "failed", "aborted_budget", "cancelled")


def abgleich(db_path: Path | str, laufende_ids: set[str] | frozenset[str]) -> list[str]:
    """Nach einem Neustart: Plaene, die noch 'laeuft' oder 'startet' sagen,
    obwohl ihr Task laengst fertig ist - und Tasks, die nie zu Ende liefen.

    Ein Task, der in der Datenbank noch 'pending' oder 'running' steht,
    aber in keinem Speicher mehr laeuft, ist beim Herunterfahren gestorben
    (oder der Start ist nach der Buchung gescheitert). Er bekommt 'failed'
    mit dem Grund, damit die Auftragsliste nicht ewig einen laufenden
    Auftrag zeigt - und der Plan den Ausgang, falls er noch 'laeuft' sagt.
    """
    geaendert: list[str] = []
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT z.id, z.letzter_status, z.letzter_task_id AS task_id, t.status "
            "FROM zeitplaene z JOIN tasks t ON t.id = z.letzter_task_id "
            "WHERE z.letzter_status IN ('laeuft', 'startet') "
            "   OR t.status IN ('pending', 'running')"
        ).fetchall()
        for z in zeilen:
            if z["task_id"] in laufende_ids:
                continue
            if z["status"] in ENDZUSTAENDE:
                neu = z["status"]
            else:
                neu = "abgebrochen: Neustart waehrend des Laufs"
                conn.execute(
                    "UPDATE tasks SET status = 'failed', abort_reason = ?, "
                    "finished_at = ? WHERE id = ? AND status IN ('pending', 'running')",
                    ("Neustart waehrend des Laufs.", utcnow(), z["task_id"]),
                )
            if z["letzter_status"] in ("laeuft", "startet"):
                conn.execute("UPDATE zeitplaene SET letzter_status = ? WHERE id = ?",
                             (neu, z["id"]))
            geaendert.append(z["id"])
    return geaendert


@dataclass(frozen=True)
class Verbrauch:
    laeufe: int
    token: int


def verbrauch_24h(db_path: Path | str, jetzt: datetime | None = None,
                  reserviert: dict[str, int] | None = None) -> Verbrauch:
    """Regel 2, die Messung: was ALLE Zeitplaene in den letzten 24 Stunden
    gestartet und verbraucht haben. Ueber die echten Tasks gerechnet, nicht
    ueber einen Zaehler, den jemand von Hand pflegt.

    `reserviert` sind laufende Tasks (task_id -> Budget in Token). Ein
    laufender Task zaehlt mit seinem Budget - denn was in der Datenbank
    steht, ist der Stand nach der Planung, nicht der Stand jetzt (zweite
    Pruefrunde). Das Protokoll ueberlebt das Loeschen eines Plans
    (zeitplan_id wird NULL), deshalb wird hier nicht ueber zeitplaene
    gejoint.
    """
    seit = _als_z((jetzt or datetime.now(timezone.utc)) - timedelta(hours=24))
    reserviert = reserviert or {}
    with session(db_path) as conn:
        zeilen = conn.execute(
            "SELECT l.task_id, COALESCE(t.spent_tokens, 0) AS spent "
            "FROM zeitplan_laeufe l LEFT JOIN tasks t ON t.id = l.task_id "
            "WHERE l.gestartet_am >= ?",
            (seit,),
        ).fetchall()
    token = 0
    for z in zeilen:
        spent = int(z["spent"] or 0)
        token += max(spent, reserviert.get(z["task_id"], 0))
    return Verbrauch(laeufe=len(zeilen), token=token)


def _de(n: int) -> str:
    """50.000, nicht 50,000 - dieselbe Schreibweise wie die Oberflaeche."""
    return f"{n:,}".replace(",", ".")


def deckel_erreicht(verbrauch: Verbrauch, *, max_laeufe: int, max_token: int) -> str | None:
    """Regel 2, die Entscheidung. Gibt den Grund zurueck oder None."""
    if verbrauch.laeufe >= max_laeufe:
        return (f"Tagesdeckel erreicht: {verbrauch.laeufe} von {max_laeufe} "
                f"Laeufen in 24 Stunden (ZEITPLAN_MAX_LAEUFE_24H).")
    if verbrauch.token >= max_token:
        return (f"Tagesdeckel erreicht: {_de(verbrauch.token)} von {_de(max_token)} "
                f"Token in 24 Stunden (ZEITPLAN_MAX_TOKEN_24H).")
    rest = max_token - verbrauch.token
    if rest < MINDEST_REST:
        return (f"Tagesdeckel fast erreicht: nur noch {_de(rest)} Token uebrig, "
                f"ein Lauf braucht mindestens {_de(MINDEST_REST)} (ZEITPLAN_MAX_TOKEN_24H).")
    return None
