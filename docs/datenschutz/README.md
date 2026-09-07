# Datenschutz

Was hier liegt, ist **fachliche Vorarbeit für eine anwaltliche Prüfung** — nicht deren
Ergebnis. Der Unterschied ist wichtig genug, um ihn zuerst zu nennen: die Angaben
darüber, was die Anwendung mit Daten tut, sind aus dem Quelltext belegt und
belastbar. Die Einordnungen zu Rechtsgrundlagen sind begründet, aber kein Rechtsrat.

| Dokument | Inhalt |
|---|---|
| [`verarbeitungsverzeichnis.md`](verarbeitungsverzeichnis.md) | Art. 30: welche Daten, wozu, an wen, wie lange. Tabelle für Tabelle aus `schema.ts` abgeleitet. |
| [`tom.md`](tom.md) | Art. 32, getrennt nach *umgesetzt*, *bewusst nicht umgesetzt*, *fehlt noch*. |
| [`auftragsverarbeiter.md`](auftragsverarbeiter.md) | Art. 28 und § 203 StGB: die Arbeitsliste mit absichtlich leeren Feldern. |

Die Datenschutzerklärung selbst ist kein Dokument, sondern die Seite `/datenschutz` in
der Anwendung. Sie liest ihre Löschfristen aus `FRISTEN` — ein Text, der eigene Zahlen
nennt, läuft beim ersten Anfassen des Löschkonzepts auseinander.

---

## Was gebaut ist

Datenschutz ist hier überwiegend Code und nicht Prosa:

- **Löschkonzept** — `src/lib/datenschutz/aufbewahrung.ts`, rein und testbar, mit
  Fristen an genau einer Stelle. Ausgeführt im selben Takt wie der Mailversand; ein
  Löschjob, den jemand getrennt einrichten muss, ist der erste, den niemand einrichtet.
- **Auskunft und Übertragbarkeit** (Art. 15, 20) — Download auf Klick, ohne Antrag,
  ohne Frist, ohne Zugangsdaten in der Datei.
- **Löschung** (Art. 17) — Selbstbedienung mit Tippbestätigung; widerruft zusätzlich
  das Google-Token und räumt den Anmelde-Token weg, der an der Mailadresse hängt und
  nicht unter die Kaskade fällt.
- **Vorwarnung vor der Löschung ruhender Konten** — nie ohne Ansage.

Alles davon unter `/daten` in der Oberfläche, mit Tests unter
`src/lib/datenschutz/*.test.ts`.

## Was beim Bauen aufgefallen ist

Zwei Dinge, die vorher nicht stimmten und mehr sind als Formsache:

**Es wurde nie etwas gelöscht.** Kein Vorgang, keine Mail, kein abgelaufener
Anmelde-Token. Weitergeleitete Verordnungen mit Gesundheitsdaten lagen unbegrenzt in
der Datenbank. Das ist Art. 5 Abs. 1 lit. e, und es war kein juristisches Problem,
sondern fehlender Code.

**Sämtliche Fremdschlüssel waren im erzeugten Schema auskommentiert.** Die
`ON DELETE CASCADE` aus `schema.ts` existierte in der Datenbank nicht — mit der
seinerzeit notierten Begründung, referenzielle Integrität sei für die eingebettete
Entwicklungsdatenbank verzichtbar. Das stimmte, solange nie gelöscht wurde. In dem
Moment, in dem Löschen zur Pflicht wird, ist die Kaskade der Mechanismus, durch den
Gesundheitsdaten tatsächlich verschwinden: ohne sie hätte eine Kontolöschung die Mails
als unerreichbare Waisen in der Datenbank zurückgelassen — sichtbar für niemanden,
gelöscht aber auch nicht. Ein Test hält das jetzt fest.

---

## Was fehlt, und warum es nicht hier gelöst werden kann

Drei Fragen entscheiden über das Produkt und nicht nur über seine Dokumentation. Sie
stehen ausführlich in den Einzeldokumenten; hier die Kurzfassung in der Reihenfolge,
in der sie zu stellen sind:

1. **Darf der Volltext von Mails mit Gesundheitsdaten an den Modellanbieter gehen?**
   Deckt dessen AVV Art. 9 ab, ist ein Training mit den Inhalten ausgeschlossen, wo
   wird verarbeitet? Fällt die Antwort negativ aus, ändert sich die Architektur — nicht
   der Vertragstext. Deshalb zuerst.
2. **§ 203 Abs. 3 StGB.** Die Einbeziehung eines IT-Dienstleisters ist zulässig, aber
   nur mit Verpflichtung zur Geheimhaltung — auch der weiteren Mitwirkenden. Das
   betrifft die gesamte Anbieterliste und ist der Punkt, an dem Standardverträge
   großer Anbieter womöglich nicht ausreichen.
3. **Datenschutz-Folgenabschätzung nach Art. 35.** Nach Art. 35 Abs. 3 lit. b
   wahrscheinlich verpflichtend. Ob die Schwelle „umfangreich" bei wenigen Praxen
   erreicht ist, ist diskutabel — dass die Frage gestellt werden muss, nicht.

Dazu die handwerklichen Lücken aus [`tom.md`](tom.md): AVVs, ein Verfahren für
Datenschutzverletzungen nach Art. 33/34 (bei einer Person ohne Vertretung: was
passiert im Urlaub?), Berichtigung und Einschränkung als Funktion statt per Mail, ein
Wiederherstellungstest, und der Abgleich der eigenen Löschfristen mit den Log- und
Backup-Fristen der Anbieter. Die eigene Datenbank nach 90 Tagen zu leeren nützt wenig,
wenn dieselben Inhalte beim Mailversender länger liegen.

Nicht vergessen: **Impressum** nach § 5 DDG. Formal, aber abmahnfähig.

---

## Der Schalter

Die Seite `/datenschutz` zeigt einen Warnkasten „Ungeprüfter Entwurf", solange nicht
**beides** gilt: die Betreiberangaben sind gesetzt (`BETREIBER_NAME`,
`BETREIBER_ANSCHRIFT`, `BETREIBER_EMAIL`) **und** `DATENSCHUTZ_GEPRUEFT=ja`.

Zwei Bedingungen statt einer, damit die Bestätigung nicht versehentlich durch das
bloße Ausfüllen der Adresse mitkommt. Der Kasten soll nicht vergessen werden können.
