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


def toleranz_fuer(takt_s: int | float) -> timedelta:
    """Die Toleranz muss zum Takt passen. Prueft die Schleife nur alle
    180 Sekunden, waere jeder Lauf mit fester 2-Minuten-Toleranz "verpasst" -
    taeglich. Zwei Takte sind der Spielraum, mindestens die zwei Minuten."""
    return max(TOLERANZ, timedelta(seconds=2 * max(0, float(takt_s))))

_TAEGLICH = re.compile(r"^taeglich (\d{1,2}):(\d{2})$")
_STUNDEN = re.compile(r"^alle (\d{1,3}) stunden?$")


class RegelUngueltig(ValueError):
    """Die Regel ist keine der zwei erlaubten Formen."""


@dataclass(frozen=True)
class Regel:
    art: str            # 'taeglich' | 'stunden'
    stunde: int = 0     # taeglich: 0..23
    minute: int = 0     # taeglich: 0..59
    alle: int = 0       # stunden: 1..168

    @property
    def text(self) -> str:
        if self.art == "taeglich":
            return f"taeglich {self.stunde:02d}:{self.minute:02d}"
        return f"alle {self.alle} stunden"


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
    raise RegelUngueltig(
        f"'{roh}' verstehe ich nicht. Erlaubt sind genau zwei Formen: "
        f"'taeglich 07:00' oder 'alle 6 stunden'."
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


def anlegen(db_path: Path | str, *, name: str, ziel: str, regel_text: str) -> dict:
    regel = lies_regel(regel_text)
    name = " ".join(str(name or "").split())[:80]
    ziel = str(ziel or "").strip()
    if not name:
        raise ValueError("Ein Zeitplan braucht einen Namen.")
    if not ziel:
        raise ValueError("Ein Zeitplan braucht einen Auftragstext.")
    eintrag = {
        "id": uuid.uuid4().hex[:12],
        "name": name,
        "ziel": ziel,
        "regel": regel.text,
        "aktiv": 1,
        "erstellt_am": utcnow(),
        "naechster_lauf": naechster_lauf(regel),
        "letzter_lauf": None,
        "letzter_task_id": None,
        "letzter_status": None,
        "verpasst": 0,
    }
    with session(db_path) as conn:
        conn.execute(
            "INSERT INTO zeitplaene (id, name, ziel, regel, aktiv, erstellt_am, "
            "naechster_lauf, letzter_lauf, letzter_task_id, letzter_status, verpasst) "
            "VALUES (:id, :name, :ziel, :regel, :aktiv, :erstellt_am, :naechster_lauf, "
            ":letzter_lauf, :letzter_task_id, :letzter_status, :verpasst)",
            eintrag,
        )
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
    naechster = naechster_lauf(lies_regel(plan["regel"])) if aktiv else None
    with session(db_path) as conn:
        conn.execute(
            "UPDATE zeitplaene SET aktiv = ?, naechster_lauf = ? WHERE id = ?",
            (1 if aktiv else 0, naechster, zeitplan_id),
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


def verbuche_start(db_path: Path | str, plan: dict, task_id: str | None,
                   *, ausloeser: str, status: str,
                   jetzt: datetime | None = None) -> None:
    """Ein Lauf hat begonnen (oder wurde uebersprungen): Protokoll schreiben
    und den naechsten Termin setzen.

    Geschrieben wird NUR, was sich aendert. Der `plan`, den der Aufrufer
    hier hereingibt, kann Sekunden alt sein - inzwischen hat vielleicht ein
    Handlauf `letzter_task_id` gesetzt. Wer alte Werte zurueckschreibt,
    macht genau das rueckgaengig (erste Pruefrunde, Fund 1).

    `ausloeser='hand'` (der Knopf "Jetzt") laesst den Termin, wie er ist: ein
    Probelauf um 15:00 verschiebt "taeglich 07:00" nicht und setzt auch
    "alle 6 stunden" nicht neu an. Er zaehlt aber fuer den Deckel - Token
    sind Token, egal wer den Lauf ausgeloest hat.

    Der naechste Takt zaehlt ab dem SOLL-Termin, nicht ab dem Zeitpunkt, an
    dem die Schleife ihn bemerkt hat. Sonst schiebt jede Runde den Takt um
    ihre Verzoegerung nach hinten - 18 Minuten am Tag bei "alle 1 stunde",
    gemessen in der ersten Pruefrunde (Fund 4).
    """
    regel = lies_regel(plan["regel"])
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    soll = _aus_z(plan["naechster_lauf"]) if plan.get("naechster_lauf") else zeitpunkt
    with session(db_path) as conn:
        if task_id:
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
        else:
            conn.execute(
                "UPDATE zeitplaene SET letzter_status = ? WHERE id = ?",
                (status, plan["id"]),
            )
        if ausloeser != "hand":
            conn.execute(
                "UPDATE zeitplaene SET naechster_lauf = ? WHERE id = ?",
                (naechster_lauf(regel, ab=zeitpunkt, letzter=soll), plan["id"]),
            )


def verbuche_verpasst(db_path: Path | str, plan: dict,
                      jetzt: datetime | None = None) -> None:
    """Regel 3, die Buchung: zaehlen, Termin weiterschieben, nicht starten."""
    regel = lies_regel(plan["regel"])
    zeitpunkt = (jetzt or datetime.now(timezone.utc)).astimezone(timezone.utc)
    with session(db_path) as conn:
        conn.execute(
            "UPDATE zeitplaene SET verpasst = verpasst + 1, "
            "letzter_status = ?, naechster_lauf = ? WHERE id = ?",
            (f"verpasst ({plan['naechster_lauf']}), nicht nachgeholt",
             naechster_lauf(regel, ab=zeitpunkt), plan["id"]),
        )


def nachtrag_ergebnis(db_path: Path | str, task_id: str, status: str) -> None:
    """Wenn der Task fertig ist: den Ausgang an den Zeitplan schreiben, damit
    die Liste 'done' oder 'failed' zeigt und nicht ewig 'laeuft'."""
    with session(db_path) as conn:
        conn.execute(
            "UPDATE zeitplaene SET letzter_status = ? WHERE letzter_task_id = ?",
            (status, task_id),
        )


@dataclass(frozen=True)
class Verbrauch:
    laeufe: int
    token: int


def verbrauch_24h(db_path: Path | str, jetzt: datetime | None = None) -> Verbrauch:
    """Regel 2, die Messung: was ALLE Zeitplaene in den letzten 24 Stunden
    gestartet und verbraucht haben. Ueber die echten Tasks gerechnet, nicht
    ueber einen Zaehler, den jemand von Hand pflegt."""
    seit = _als_z((jetzt or datetime.now(timezone.utc)) - timedelta(hours=24))
    with session(db_path) as conn:
        z = conn.execute(
            "SELECT COUNT(l.id) AS laeufe, COALESCE(SUM(t.spent_tokens), 0) AS token "
            "FROM zeitplan_laeufe l LEFT JOIN tasks t ON t.id = l.task_id "
            "WHERE l.gestartet_am >= ?",
            (seit,),
        ).fetchone()
    return Verbrauch(laeufe=int(z["laeufe"] or 0), token=int(z["token"] or 0))


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
    return None
