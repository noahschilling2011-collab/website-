# Auftragsverarbeiter, Drittland und Schweigepflicht

**Status:** Arbeitsliste. Die leeren Felder sind Absicht — sie zu füllen ist Arbeit am
Vertrag, nicht am Code, und ein plausibel klingender Eintrag wäre hier schlimmer als
ein leerer.

---

## 1. Warum diese Liste kurz sein muss

Jeder Anbieter in dieser Liste ist eine Stelle, an der Gesundheitsdaten aus einer
Praxis landen können. Bei einem Ein-Personen-Betrieb ohne Rechtsabteilung ist jeder
zusätzliche AVV echter Aufwand — Prüfen, Verhandeln, Nachhalten. Die Liste kurz zu
halten ist deshalb kein Purismus, sondern Betriebsfähigkeit.

Sortiert nach Eingriffstiefe, nicht alphabetisch.

---

## 2. Die Liste

### 2.1 Modellanbieter — Anthropic

**Bekommt: den Volltext eingehender Mails samt Anhangstext.** Belegstellen:
`src/lib/llm/extraktion.ts` (Erkennung), `src/lib/llm/formulierung.ts` (Antwortentwurf).

Das ist die weitreichendste Übermittlung im ganzen Produkt und die einzige, die sich
nicht durch Sorgfalt kleiner machen lässt: die Funktion *besteht* darin, den Inhalt zu
verstehen.

| Zu klären | Eintrag |
|---|---|
| Vertragspartner (EU- oder US-Entität) | |
| AVV nach Art. 28 abgeschlossen | ☐ |
| Verarbeitung besonderer Kategorien vertraglich zulässig | ☐ |
| Zusicherung: **keine Nutzung der Inhalte zum Training** | ☐ |
| Aufbewahrungsdauer der übermittelten Inhalte beim Anbieter | |
| Unterauftragsverarbeiter (u. a. Hyperscaler) und deren Standorte | |
| Übermittlungsgrundlage Art. 44 ff. | |
| Region wählbar? Verarbeitung in der EU möglich? | |

> **Die harte Frage zuerst:** Ist die Verarbeitung von Gesundheitsdaten unter den
> Bedingungen des Anbieters überhaupt zulässig, und deckt der AVV Art. 9 ab? Fällt
> die Antwort negativ aus, ist das kein Detail, sondern das Ende dieser
> Produktarchitektur — dann bliebe nur ein Modell in eigener Hoheit oder ein
> Verzicht auf Funktion B. Diese Frage gehört **an den Anfang** der anwaltlichen
> Prüfung, nicht ans Ende.

### 2.2 Maileingang — Cloudflare (Email Routing, Workers)

**Bekommt: jede eingehende Mail, bevor der Dienst sie sieht.**
Belegstelle: `worker/email-worker.ts`.

| Zu klären | Eintrag |
|---|---|
| Vertragspartner | |
| AVV abgeschlossen | ☐ |
| Wie lange liegen Mails/Logs beim Anbieter | |
| Übermittlungsgrundlage Art. 44 ff. | |

### 2.3 Mailversand — Resend

**Bekommt: jede ausgehende Mail samt Empfänger und Inhalt.**
Belegstelle: `src/lib/mail/ausgang.ts`.

| Zu klären | Eintrag |
|---|---|
| Vertragspartner | |
| AVV abgeschlossen | ☐ |
| Log-Aufbewahrung, und ob Inhalte darin stehen | |
| Übermittlungsgrundlage Art. 44 ff. | |

> Der Punkt Log-Aufbewahrung ist mehr als Routine: die eigene Datenbank nach 90 Tagen
> zu leeren nützt wenig, wenn dieselben Mailinhalte beim Versender länger liegen.
> **Die Löschfristen der Anbieter müssen zum eigenen Löschkonzept passen**, sonst ist
> es Fassade.

### 2.4 Datenbank — Neon

**Bekommt: alles.** Belegstelle: `src/db/index.ts`.

| Zu klären | Eintrag |
|---|---|
| Vertragspartner | |
| AVV abgeschlossen | ☐ |
| **Region auf EU gesetzt** | ☐ |
| Verschlüsselung ruhender Daten (belegen, nicht annehmen) | ☐ |
| Aufbewahrung von Sicherungen und Point-in-Time-Recovery — wie lange überlebt eine gelöschte Zeile dort? | |

> Der letzte Punkt ist der, den man übersieht: Löschen nach Art. 17 und ein
> 30-Tage-Backup-Fenster vertragen sich nicht von selbst. Es braucht eine Antwort
> darauf, wann eine gelöschte Zeile wirklich weg ist — und die gehört in die
> Datenschutzerklärung, nicht nur hierher.

### 2.5 Hosting — Vercel

**Bekommt: alles, was durch die Anwendung läuft.**

| Zu klären | Eintrag |
|---|---|
| Vertragspartner | |
| AVV abgeschlossen | ☐ |
| Region der Funktionsausführung | |
| Was steht in den Laufzeit-Logs, und wie lange | |

> Konkret prüfen: dass keine Mailinhalte in Logs landen. Der Code schreibt sie nicht
> absichtlich hinein, aber eine unbehandelte Ausnahme mit Nutzlast im Text tut es
> beiläufig.

### 2.6 Kalender — Google

Nur wenn die Nutzerin einen Kalender verbindet.
**Bekommt: Titel und Zeit der eingetragenen Termine.** Gelesen werden ausschließlich
Belegtzeiten — keine Titel, keine Teilnehmer (`calendar.freebusy`).

Sonderfall: Google ist hier **nicht ohne Weiteres Auftragsverarbeiter des Betreibers**.
Die Nutzerin autorisiert den Zugriff auf ihr eigenes Konto, das sie ohnehin unterhält.
Wie das einzuordnen ist, gehört in die anwaltliche Prüfung. Praktisch relevant: ein
Termintitel wie „Folgeverordnung Jonas Berger" ist ein Gesundheitsdatum, das dadurch
in einem Google-Kalender liegt.

### 2.7 Zahlung — Stripe

**Bekommt: Mailadresse und Zahlungsdaten. Keine Inhalte, keine Gesundheitsdaten.**
Belegstelle: `src/lib/zahlung.ts`.

| Zu klären | Eintrag |
|---|---|
| Vertragspartner | |
| AVV abgeschlossen | ☐ |
| Rolle (Auftragsverarbeiter oder eigener Verantwortlicher) | |

---

## 3. § 203 StGB — Schweigepflicht

Betrifft den Betreiber **persönlich und strafbewehrt**, unabhängig von der DSGVO.

Ergotherapeutinnen gehören zu den Heilberufen mit staatlich geregelter Ausbildung und
unterliegen damit § 203 Abs. 1 StGB. Seit der Neuregelung von 2017 erlaubt § 203
Abs. 3 StGB ausdrücklich, **sonstige mitwirkende Personen** — dazu zählen IT-Dienst\-
leister — einzubeziehen. Die Bedingungen dafür sind kein Beiwerk:

| Bedingung | Was zu tun ist |
|---|---|
| Offenbarung nur, soweit für die Mitwirkung **erforderlich** | Datenminimierung belegen — was hier durch den Verzicht auf Postfachzugriff und Rohanhänge bereits gestützt wird |
| Die mitwirkende Person ist **zur Geheimhaltung verpflichtet** | Verpflichtungserklärung des Betreiters, schriftlich, vor der ersten Mail |
| **Weitere** Mitwirkende (Unterauftragnehmer) ebenso verpflichten | Das betrifft die gesamte Liste aus Abschnitt 2 — und ist der schwierigste Punkt: einen US-Cloudanbieter auf § 203 zu verpflichten ist nicht das, was dessen Standardvertrag vorsieht |
| Sorgfaltspflicht bei der Auswahl | dokumentieren |

> **Der ungelöste Knoten:** Abschnitt 2 nennt sechs bis sieben Dienstleister. § 203
> Abs. 3 verlangt eine Verpflichtung auch der weiteren Mitwirkenden. Wie das mit
> Standardverträgen großer Anbieter zusammengeht, ist die zweite Frage, die vor
> allem anderen zu klären ist. Sie könnte dazu führen, dass die Architektur weniger
> Dienstleister vertragen muss als sie derzeit hat.

Das ist ausdrücklich **keine Rechtsauskunft**. Die Paragrafen sind benannt, damit die
Anwältin nicht bei null anfängt — die Bewertung ist ihre.

---

## 4. Reihenfolge

Nicht nach Aufwand, sondern nach Vorlaufzeit und Abbruchrisiko:

1. **Anthropic: Art. 9 und Trainingsausschluss klären.** Fällt das negativ aus,
   ändert sich das Produkt, nicht nur der Vertrag. Alles andere ist dann verfrüht.
2. **§ 203 Abs. 3 mit einer Anwältin durchgehen**, inklusive der Frage zu den
   Unterauftragnehmern.
3. **DSFA** nach Art. 35 — siehe Verarbeitungsverzeichnis, Abschnitt 8.
4. Übrige AVVs abschließen, Regionen auf EU stellen, Log- und Backup-Fristen abfragen
   und mit dem eigenen Löschkonzept abgleichen.
5. Datenschutzerklärung und Impressum in geprüfter Fassung,
   `DATENSCHUTZ_GEPRUEFT=ja` setzen.
