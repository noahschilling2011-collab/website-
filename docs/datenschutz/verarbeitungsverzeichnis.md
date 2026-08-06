# Verarbeitungsverzeichnis (Art. 30 DSGVO)

**Stand:** aus `terminassistent/src/db/schema.ts` abgeleitet, Commit-Stand siehe Git.
**Status:** fachlicher Entwurf, nicht anwaltlich geprüft. Was hier über die Anwendung
steht, ist aus dem Quelltext belegt. Was hier über Rechtsgrundlagen steht, ist eine
begründete Einordnung und kein Rechtsrat.

Dieses Verzeichnis ist bewusst so geschrieben, dass eine Anwältin es prüfen kann, ohne
den Code zu lesen — und dass umgekehrt jede Zeile im Code auffindbar ist.

---

## 0. Die eine Besonderheit, die alles andere bestimmt

Der Dienst verarbeitet **Gesundheitsdaten nach Art. 9 Abs. 1 DSGVO**, und zwar nicht
als Randfall: eine weitergeleitete Heilmittelverordnung ist der Hauptanwendungsfall
(Funktion B des Produktentwurfs). Betroffen sind dabei überwiegend **nicht die
Nutzerin**, sondern Dritte — Patientinnen, deren Angehörige, verordnende Praxen.

Daraus folgen drei Dinge, die weiter unten immer wieder auftauchen:

1. Es gibt **zwei Rollen** in einem einzigen Produkt (Abschnitt 1).
2. Der Inhalt dieser Mails geht an einen **Modellanbieter** (Abschnitt 4). Das ist die
   weitreichendste einzelne Tatsache in diesem Dokument.
3. Eine **Datenschutz-Folgenabschätzung nach Art. 35 ist wahrscheinlich Pflicht**
   (Abschnitt 8), nicht Kür.

---

## 1. Zwei Rollen, ein Produkt

| | Verantwortlicher | Betroffene | Rechtsgrundlage |
|---|---|---|---|
| **Kontodaten der Nutzerin** — Mailadresse, Name, Zeitzone, Arbeitszeiten, Zahlungsstatus | Betreiber des Dienstes | die Nutzerin | Art. 6 Abs. 1 lit. b (Vertrag) |
| **Alles Weitergeleitete** — Mailinhalte, Anhangstexte, Termine, Namen und Adressen Dritter, Gesundheitsdaten | **die Nutzerin** (z. B. die Praxis); der Betreiber ist Auftragsverarbeiter nach Art. 28 | Dritte: Patientinnen, Angehörige, Praxen, Kostenträger | für die Nutzerin i. d. R. Art. 6 Abs. 1 lit. b + Art. 9 Abs. 2 lit. h; für den Betreiber Art. 28 + Art. 29 |

Die Trennung ist keine Förmlichkeit. Sie entscheidet, **wer eine Verletzung nach
Art. 33 melden muss** (die Nutzerin, binnen 72 Stunden — der Betreiber meldet
unverzüglich an sie, Art. 33 Abs. 2) und **wer einer Patientin Auskunft schuldet**
(ebenfalls die Nutzerin).

> **Offene Frage für die Anwältin:** Ob der Betreiber wirklich durchgängig
> Auftragsverarbeiter bleibt oder für Teilverarbeitungen zum gemeinsam
> Verantwortlichen (Art. 26) wird — etwa wenn er über die Aufbewahrungsfristen und
> die Modellauswahl allein entscheidet, was er hier tut. Die Einordnung als reine
> Auftragsverarbeitung ist plausibel, aber nicht selbstverständlich.

---

## 2. Kategorien betroffener Personen und Daten

Abgeleitet Tabelle für Tabelle aus `schema.ts`.

| Tabelle | Betroffene | Daten | Art. 9? |
|---|---|---|---|
| `nutzer` | Nutzerin | Mailadresse, Name, Zeitzone, Arbeitszeiten, Weiterleitungs-Handle, Zähler freier Vorgänge, Zahlungsstatus, Kundennummer beim Zahlungsdienstleister | nein |
| `anmelde_tokens` | Nutzerin | Mailadresse, Hash des Anmeldelinks, Gültigkeit | nein |
| `calendar_connections` | Nutzerin | Art der Verbindung, **verschlüsseltes** Zugangsgeheimnis, Kalender-ID, Fehler- und Erfolgszeitpunkte | nein |
| `vorgaenge` | Nutzerin + Dritte | Titel in Alltagssprache, Mailadresse und Name des Gegenübers, Thread-Schlüssel, Fristdatum | **mittelbar ja** — ein Titel wie „Folgeverordnung Jonas Berger" ist ein Gesundheitsdatum |
| `nachrichten` | Nutzerin + Dritte | **vollständiger Text** ein- und ausgehender Mails, Absender, Empfänger, Betreff, RFC-5322-Header | **ja** |
| `anhaenge` | Dritte | Dateiname, MIME-Typ, Größe, **extrahierter Text** der PDF | **ja** |
| `termine` | Nutzerin + Dritte | Titel, Zeitraum, Zeitzone, Ort, iCalendar-UID, Platzierungsnachweis | **mittelbar ja** |
| `ausgang` | Nutzerin + Dritte | Empfänger, Betreff, **voller Text** der ausgehenden Mail, optionaler iCalendar-Teil | **ja** |
| `regeln` | Dritte | Mailadresse des Empfängers, Aktionstyp, Zähler bestätigter Sendungen | nein |
| `protokoll` | Nutzerin + Dritte | **voller Wortlaut** dessen, was rausging | **ja** |

**Nicht gespeichert wird der Rohanhang.** Aus einer PDF wird der Text extrahiert, die
Datei danach verworfen (`src/lib/mail/eingang.ts`). Gescannte PDFs ohne Textschicht
werden abgelehnt statt geraten — kein OCR, keine Vermutung.

`protokoll` ist die heikelste Tabelle: sie existiert, weil das Produkt
Nachvollziehbarkeit im Wortlaut verspricht, und enthält genau deshalb den Volltext.
Das Löschkonzept behandelt sie deshalb zweistufig (Abschnitt 5).

---

## 3. Zwecke

1. **Terminabstimmung per Mail** — freie Zeiten aus dem Kalender lesen, Vorschläge
   formulieren, Zusage erkennen, Termin eintragen.
2. **Fristen aus weitergeleiteten Dokumenten** in den Kalender eintragen.
3. **Nachfassen**, wenn keine Antwort kommt.
4. **Konto und Abrechnung** — Anmeldung per Magic Link, Zählung der freien Vorgänge,
   Abonnement.
5. **Nachvollziehbarkeit** — das Protokoll. Eigener Zweck, weil es der Ersatz für ein
   technisch unmögliches „Rückgängig" ist.
6. **Betriebssicherheit** — Überwachung still brechender Kalenderverbindungen.

---

## 4. Empfänger und Auftragsverarbeiter

Vollständige Liste mit den offenen Punkten in
[`auftragsverarbeiter.md`](auftragsverarbeiter.md). Kurzfassung, nach Eingriffstiefe
sortiert:

| Empfänger | Bekommt | Belegstelle im Code |
|---|---|---|
| **Modellanbieter (Anthropic)** | **Volltext eingehender Mails samt Anhangstext**, zur Erkennung und zur Formulierung | `src/lib/llm/extraktion.ts`, `src/lib/llm/formulierung.ts` |
| Mailversand (Resend) | ausgehende Mails samt Empfänger und Inhalt | `src/lib/mail/ausgang.ts` |
| Maileingang (Cloudflare) | eingehende Mails vor der Verarbeitung | `worker/email-worker.ts` |
| Datenbank (Neon) und Hosting (Vercel) | alles aus Abschnitt 2 | `src/db/index.ts` |
| Kalenderanbieter (Google) | Titel und Zeit eingetragener Termine; beim Lesen **nur Belegtzeiten**, keine Titel, keine Teilnehmer | `src/lib/calendar/google.ts` |
| Zahlungsdienstleister (Stripe) | Mailadresse, Zahlungsdaten — **keine** Inhalte | `src/lib/zahlung.ts` |
| Empfänger der Mails | was in der Mail steht | — |

Der erste Eintrag ist der, an dem dieses Produkt datenschutzrechtlich steht oder
fällt. Er wird in der Datenschutzerklärung deshalb ausdrücklich benannt und nicht
unter „technische Dienstleister" versteckt.

---

## 5. Löschfristen

Umgesetzt in `src/lib/datenschutz/aufbewahrung.ts`, ausgeführt im Takt
(`src/lib/datenschutz/betroffenenrechte.ts`). Die Zahlen stehen an genau einer Stelle
und werden von der Datenschutzseite daraus angezeigt — ein Text, der eigene Zahlen
nennt, läuft beim ersten Anfassen des Konzepts auseinander.

| Daten | Frist | Warum diese Länge |
|---|---|---|
| Anmelde-Token | 1 Tag nach Einlösung oder Ablauf | Zweck erfüllt |
| Abgeschlossener Vorgang samt Mails, Anhangstexten, Terminen, Ausgang | 90 Tage nach letzter Änderung | lang genug für eine Rückfrage, kurz genug, dass keine halbjährige Korrespondenz einer Praxis hier liegt |
| **Wortlaut** im Protokoll | 90 Tage | die sensibelste Spalte fällt zuerst |
| Protokolleintrag ohne Wortlaut | 180 Tage | dass etwas geschah, bleibt länger nachvollziehbar als was |
| Widerrufene Kalenderverbindung | 30 Tage | Nachvollziehbarkeit der Trennung |
| Konto ohne jede Nutzung | 24 Monate, mit Vorwarnung nach 23 | Zweckfortfall; zahlende Konten nie |

**Eine Ausnahme, die im Code steht und hier begründet gehört:** ein abgeschlossener
Vorgang mit einer Frist **in der Zukunft** wird nicht gelöscht, egal wie alt er ist.
Eine Verordnung kann ein Jahr im Voraus im Kalender stehen; verschwindet der Vorgang,
kann die Nutzerin nicht mehr nachsehen, woher der Termin kommt. Ein Test hält das fest.

---

## 6. Technische und organisatorische Maßnahmen (Art. 32)

Siehe [`tom.md`](tom.md) — dort getrennt nach *umgesetzt*, *bewusst nicht umgesetzt*
und *fehlt noch*.

---

## 7. Drittlandübermittlung

Alle in Abschnitt 4 genannten Anbieter sind US-Unternehmen oder haben US-Mutter\-
gesellschaften. Für jeden einzelnen ist vor dem ersten echten Einsatz zu klären:
Vertragspartner (EU- oder US-Entität), Serverstandort, Übermittlungsgrundlage nach
Art. 44 ff., und ob ein Transfer Impact Assessment nötig ist.

**Das ist hier bewusst nicht ausgefüllt.** Ob ein bestimmtes Unternehmen aktuell unter
dem EU-US Data Privacy Framework zertifiziert ist, ändert sich und ist gegen die
offizielle Liste zu prüfen, nicht aus dem Gedächtnis zu behaupten. Die Tabelle in
[`auftragsverarbeiter.md`](auftragsverarbeiter.md) hat für jeden Anbieter eine Zeile
mit leeren Feldern — das ist ehrlicher als ein plausibel klingender Eintrag.

---

## 8. Datenschutz-Folgenabschätzung (Art. 35)

**Einschätzung: wahrscheinlich verpflichtend.** Art. 35 Abs. 3 lit. b nennt die
umfangreiche Verarbeitung besonderer Datenkategorien ausdrücklich. Hinzu kommen zwei
Merkmale, die in den Kriterienkatalogen der Aufsichtsbehörden regelmäßig auftauchen:
Einsatz neuer Technologien und Verarbeitung von Daten besonders schutzbedürftiger
Personen.

Ob die konkrete Verarbeitung die Schwelle „umfangreich" erreicht, hängt an der Zahl
der Nutzerinnen und der Menge der Vorgänge — bei einer Handvoll Praxen ist das
diskutabel. **Das ist eine Frage für die Anwältin, keine, die dieses Dokument
entscheiden kann.** Sicher ist nur: sie muss gestellt werden, bevor die erste fremde
Mail durchläuft, und die Antwort „wir sind ja klein" trägt nicht von selbst.

Fällt die Antwort auf DSFA-Pflicht, ist außerdem zu prüfen, ob eine vorherige
Konsultation der Aufsichtsbehörde nach Art. 36 nötig wird.

---

## 9. Was dieses Dokument nicht ist

Es ist kein Verarbeitungsverzeichnis der **Nutzerin**. Die Praxis, die den Dienst
einsetzt, braucht ein eigenes nach Art. 30 Abs. 1, in dem dieser Dienst als
Auftragsverarbeiter auftaucht. Ein Muster dafür beizulegen wäre hilfreich und ist
bisher nicht geschrieben.
