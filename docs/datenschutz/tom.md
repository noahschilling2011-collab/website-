# Technische und organisatorische Maßnahmen (Art. 32 DSGVO)

**Status:** aus dem Quelltext belegt. Jede Zeile unter „umgesetzt" ist im Code
auffindbar; jede Zeile unter „fehlt" ist es nicht.

Der Sinn dieser Trennung: eine TOM-Liste, in der alles abgehakt ist, ist bei einem
Ein-Personen-Projekt unglaubwürdig. Diese hier ist es hoffentlich nicht.

---

## Umgesetzt

### Vertraulichkeit

| Maßnahme | Wo |
|---|---|
| Kalender-Zugangsdaten (OAuth-Refresh-Token, geheime iCal-Adresse) verschlüsselt mit AES-256-GCM, nie im Klartext in der Datenbank, nie im Log | `src/lib/krypto.ts`, `src/lib/calendar/registry.ts` |
| Anmeldung ohne Passwort (Magic Link); gespeichert wird nur der **Hash** des Tokens | `src/lib/sitzung.ts` |
| Sitzungscookie HMAC-signiert, mit Ablauf, `httpOnly` | `src/lib/sitzung.ts` |
| Jede Aktion aus der Oberfläche prüft die **Zugehörigkeit des Vorgangs** zur angemeldeten Person — als Pflichtargument, nicht als Höflichkeit | `eigenerVorgang()` in `src/lib/vorgang/engine.ts` |
| Datenexport enthält **keine** entschlüsselten Zugangsdaten | `exportiereDaten()` in `src/lib/datenschutz/betroffenenrechte.ts` |
| Google-OAuth mit genau zwei engen Scopes; Belegtzeiten werden **ohne Termintitel und ohne Teilnehmer** gelesen | `src/lib/google-oauth.ts`, `src/lib/calendar/google.ts` |
| OAuth-`state` HMAC-signiert mit 10-Minuten-Ablauf; der Rückweg prüft zusätzlich die aktuelle Sitzung | `src/app/api/google/callback/route.ts` |
| Keine freien Texte aus der Adresszeile auf der Seite — nur feste Codes, damit ein fremder Link keinen beliebigen Satz unterschieben kann | `src/app/verbindungen/page.tsx`, `src/app/page.tsx` |
| Zahlungsfreischaltung durch Rückfrage bei Stripe, nicht durch die URL | `src/app/api/zahlung/zurueck/route.ts` |
| Webhook-Endpunkte (Maileingang, Takt) durch gemeinsames Geheimnis geschützt | `src/app/api/mail/eingang/route.ts`, `src/app/api/takt/route.ts` |

### Datenminimierung (Art. 5 Abs. 1 lit. c)

| Maßnahme | Wo |
|---|---|
| **Der Rohanhang wird nie gespeichert** — aus der PDF wird Text extrahiert, die Datei danach verworfen | `src/lib/mail/eingang.ts` |
| Gescannte PDFs ohne Textschicht werden **abgelehnt statt geraten** (kein OCR) | `src/lib/mail/eingang.ts` |
| Weiterleitungsadresse statt Postfachzugriff: der Dienst sieht nur, was ihm geschickt wird — nicht das Postfach | Produktentwurf, Abschnitt 5 |
| Kein Tracking, keine Analyse, keine Werbe-Cookies, keine externen Schriftarten oder Skripte | gesamte `src/app/` |

### Speicherbegrenzung (Art. 5 Abs. 1 lit. e)

| Maßnahme | Wo |
|---|---|
| Automatische Löschung nach festen Fristen, im selben Takt wie der Mailversand — kein separater Job, den jemand einrichten muss | `raeumeAuf()` in `src/lib/datenschutz/betroffenenrechte.ts` |
| Protokoll zweistufig: erst fällt der Wortlaut, später der Eintrag | `aufbewahrung.ts` |
| Ruhende Konten werden gelöscht — **mit Vorwarnung per Mail**, nie ohne | `behandleRuhendeKonten()` |
| `ON DELETE CASCADE` auf allen Fremdschlüsseln, damit beim Löschen nichts als Waise zurückbleibt | `src/db/schema.ts`, `scripts/schema-sql.ts` |

### Betroffenenrechte als Funktion, nicht als Postanschrift

| Maßnahme | Wo |
|---|---|
| Auskunft und Übertragbarkeit (Art. 15, 20): Download auf Klick, ohne Antrag und ohne Frist | `/api/daten/export` |
| Löschung (Art. 17): Selbstbedienung, mit Tippbestätigung der eigenen Mailadresse | `kontoLoeschen()` in `src/app/aktionen.ts` |
| Beim Kontoschluss wird zusätzlich das Google-Token bei Google widerrufen (bestmöglich) und der an der **Mailadresse** hängende Anmelde-Token gelöscht — beides fällt nicht unter die Kaskade | `loescheKonto()` |
| Transparenz: das Protokoll zeigt im Wortlaut, was der Dienst getan hat | `/protokoll` |

### Nachvollziehbarkeit und Eingabekontrolle

Das Protokoll ist zugleich die Eingabe- und Weitergabekontrolle: jede ausgehende
Nachricht steht dort im Wortlaut, mit Zeitpunkt und Anlass.

---

## Bewusst nicht umgesetzt, mit Begründung

| Nicht umgesetzt | Warum |
|---|---|
| **Verschlüsselung der Mailinhalte in der Datenbank** | Ohne echte Schlüsseltrennung wäre es Selbsttäuschung: der Anwendungsserver bräuchte den Schlüssel ohnehin ständig, und er läge auf derselben Plattform. Eine Verschlüsselung, die nur gegen einen Angreifer schützt, der die Datenbank hat, aber die Anwendung nicht, ist ein schmaler Fall. **Ehrlicher: Verschlüsselung ruhender Daten auf Speicherebene beim Datenbankanbieter, plus kurze Löschfristen.** Ob das genügt, gehört in die DSFA. |
| **Stripe-Webhook** | Eine Signaturprüfung, die niemand verifizieren kann, ist gefährlicher als keine. Stattdessen Rückfrage bei Stripe beim Rückkehr-Aufruf. |
| **Termine im Kalender bei Kontolöschung absagen** | Das sind die Termine der Nutzerin in ihrem Kalender. Ein Kontoschluss, der still den Wochenplan leerräumt, wäre ein Übergriff. |

---

## Fehlt noch — vor dem ersten echten Einsatz

| Fehlt | Warum es zählt |
|---|---|
| **Auftragsverarbeitungsverträge** mit allen Anbietern aus [`auftragsverarbeiter.md`](auftragsverarbeiter.md) | Ohne AVV ist jede Übermittlung an sie rechtswidrig, unabhängig von der Technik |
| **Verpflichtung auf die Schweigepflicht nach § 203 Abs. 3 StGB** | Betrifft den Betreiber persönlich, strafbewehrt |
| **Datenschutz-Folgenabschätzung** (Art. 35) | Siehe Verarbeitungsverzeichnis, Abschnitt 8 |
| **Verfahren für Datenschutzverletzungen** (Art. 33/34) — wer merkt es, wer meldet in 72 Stunden, an wen | Bei einer Person ohne Vertretung ist das keine Formalie, sondern die Frage, was im Urlaub passiert |
| **Berichtigung und Einschränkung** (Art. 16, 18) als Funktion | Bisher nur per Mail an den Betreiber, also mit Frist und Handarbeit |
| **Wiederherstellungstest** (Art. 32 Abs. 1 lit. c) | Eine Sicherung, die nie zurückgespielt wurde, ist keine |
| **Löschung bei den Auftragsverarbeitern** nachweisen | Die eigene Datenbank zu leeren genügt nicht, wenn Logs beim Mailversender bleiben |
| **Protokollierung administrativer Zugriffe** | Wer als Betreiber in die Produktionsdatenbank sieht, steht nirgends |
| **Zwei-Faktor-Schutz der Betreiberkonten** bei allen Anbietern | Ein übernommenes Vercel- oder Neon-Konto ist der kürzeste Weg zu allen Gesundheitsdaten auf einmal |
| **Impressum** nach § 5 DDG und **Datenschutzerklärung** in geprüfter Fassung | Formal, aber abmahnfähig |

Der Punkt zur Verschlüsselung ruhender Daten steht bewusst in der mittleren und nicht
in der ersten Tabelle: aktiviert ist sie beim Datenbankanbieter üblicherweise ab Werk,
**belegt ist sie für dieses Projekt nicht**, weil hier keine Produktionsdatenbank
existiert. Vor dem Einsatz nachsehen und hier eintragen.
