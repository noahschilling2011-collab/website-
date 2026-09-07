# Terminassistent

Umsetzung des Entwurfs aus [`docs/ki-alltagsassistent-entwurf.md`](../docs/ki-alltagsassistent-entwurf.md)
und der Anbindungsentscheidung aus
[`docs/kalender-anbindung-entscheidung.md`](../docs/kalender-anbindung-entscheidung.md).

Ein Assistent für selbstständige Therapeutinnen ohne Rezeption. Er führt
Terminabsprachen per Mail zu Ende, trägt Fristen aus weitergeleiteten Dokumenten
in den Kalender und fasst nach, wenn keine Antwort kommt.

## Sofort ausprobieren

Ohne Datenbank, ohne API-Schlüssel, ohne Mailkonto:

```bash
npm install
npm run db:generate     # Schema-SQL erzeugen (einmalig)
npm run seed            # Katrin aus Abschnitt 2 des Entwurfs anlegen
npm run dev
```

Dann auf <http://localhost:3000> mit `katrin@praxis-weber.example` anmelden. Es
gibt kein Passwort: Sie bekommen einen sechsstelligen Code per Mail. Im
Demo-Modus wird nichts versendet — der Code steht auf der Konsole, auf der
`npm run dev` läuft.

Im Demo-Modus läuft die Datenbank eingebettet (PGlite in `.pglite/`), Texte
werden regelbasiert erzeugt statt von einem Modell, und Mails landen auf der
Konsole statt im Netz.

Weiter ausprobieren:

```bash
npm run tick              # fällige Sendungen und Erinnerungen abarbeiten
npm run tick -- --vor 2h  # so tun, als wären zwei Stunden vergangen
npm test                  # 116 Tests
```

## Was gebaut ist

| Funktion aus dem Entwurf | Stand |
|---|---|
| **A** Terminabstimmung per Mail | Vollständig. Freie Slots aus dem Kalender, drei Vorschläge über Tage *und* Tageszeiten verteilt, Verhandlung im selben Mail-Thread, Zusage wird erkannt und eingetragen. |
| **B** Fristenextraktion aus Dokumenten | Vollständig. PDF-Textextraktion inklusive; gescannte PDFs ohne Textschicht werden abgelehnt statt geraten (kein OCR). |
| **C** Nachfassen | Vollständig, inklusive der Vertrauensregel: nach drei bestätigten Sendungen an dieselbe Adresse *bietet* das System die Automatik an. |
| Haltezeit, Protokoll, Kompensieren | Vollständig. Alle drei Ersatzmechanismen für ein Rückgängig: verzögern (60 Sekunden Haltezeit), nachvollziehen (Protokoll im Wortlaut), kompensieren (Termin absagen mit SEQUENCE+1, Korrektur als Entwurf). |
| Kalender verbinden | Alle drei Wege der Anbindungsentscheidung: Google-OAuth mit Zustimmungs-Flow (Weg A), geheime iCal-Adresse plus eigener Feed (Weg B), Einladung per Mail (Weg C, iMIP). |
| Bezahlschranke | Gebaut: fünf freie abgeschlossene Vorgänge, danach wird die Mail noch gespeichert, aber nicht mehr bearbeitet. Der Stripe-Teil ist als einziges Stück im Projekt **ungetestet** — siehe „Was fehlt". |
| Datenschutz, soweit er Code ist | Löschkonzept mit festen Fristen, automatisch im Takt. Auskunft und Datenübertragbarkeit als Download auf Klick, Kontolöschung als Selbstbedienung. Siehe [`docs/datenschutz/`](../docs/datenschutz/). |
| Buchen (Reisen, Einkäufe) | **Nicht gebaut**, wie in Abschnitt 3 des Entwurfs begründet. |

## Die drei Regeln, an denen der Code hängt

**1. Was das System nicht verlässt, passiert automatisch. Was die Außenwelt
erreicht, braucht einen Klick.** Diese Entscheidung steht an genau einer
Stelle: [`src/lib/vorgang/zustand.ts`](src/lib/vorgang/zustand.ts). Die Engine
enthält keine einzige eigene Entscheidung darüber, nur Seiteneffekte.

**2. Anwendungscode kennt den Kalenderkanal nicht.** `CalendarSource` und
`CalendarSink` sind getrennt, weil Lesen und Schreiben beim ICS-Weg physisch
verschiedene Kanäle sind. Der Kanalname kommt in genau einer Datei vor:
[`src/lib/calendar/registry.ts`](src/lib/calendar/registry.ts). Überall sonst
werden `capabilities` abgefragt.

Das ist nicht nur Architekturhygiene — es wirkt sich aus. `maxStalenessSeconds`
sagt, wie alt die gelesenen Belegtzeiten höchstens sind; die Slot-Berechnung
hält entsprechend Abstand zu Zeiten, die gerade erst belegt worden sein könnten.
Beim Wechsel von ICS auf OAuth fällt der Wert auf 0 und die Vorschläge werden
ohne Codeänderung präziser. Ein Test hält das fest.

**3. Eine Platzierung hat drei Zustände, keinen boolean.** `placed` heißt „steht
im Kalender", `dispatched` heißt „Einladung ist raus, Eintrag unbestätigt",
`published` heißt „steht im Feed, Abruf unbekannt". Der Unterschied schlägt bis
in die Zeile durch, die die Nutzerin liest.

Regel 1 hat eine Folge, die im iMIP-Weg sichtbar wird: `ImipMailSink` verschickt
nicht selbst. Er übergibt die fertige Einladung an einen Kanal, den die Engine
stellt — den Ausgang mit derselben 60-Sekunden-Haltezeit wie jede andere Mail.
Sonst hätte dieser eine Sink die Fähigkeit, an der Vertrauensmechanik vorbei
Post an einen echten Menschen zu schicken.

Und eine Regel, die keine Entwurfsentscheidung ist, sondern eine Konsequenz:
**jede Aktion aus der Oberfläche prüft, ob der Vorgang der angemeldeten Person
gehört.** Die Vorgangs-ID steht in einem versteckten Formularfeld, kommt also
aus dem Browser. `eigenerVorgang()` ist deshalb ein Pflichtargument von
`sendenAusloesen`, `haltezeitAbbrechen` und `kompensiere` und keine Höflichkeit
— ein vergessener Aufruf ist ein Typfehler, kein stiller Zugriff auf fremde
Post. Ein Test spannt beide Nutzerinnen gegeneinander.

## Aufbau

```
src/
  db/schema.ts                  Datenmodell (Abschnitt 5 der Anbindungsentscheidung)
  lib/
    calendar/types.ts           CalendarSource / CalendarSink / PlacementResult
    calendar/google.ts          Weg A: OAuth, freebusy.query + events
    calendar/ics.ts             Weg B: Feed lesen, Feed schreiben, iMIP erzeugen
    calendar/imip.ts            Weg C: Einladung per Mail, immer über den Ausgang
    calendar/registry.ts        der einzige Ort, der Kanalnamen kennt
    google-oauth.ts             Zustimmungs-Flow, signierter state, Code-Tausch
    abrechnung.ts               die Bezahlschranke, rein und ohne Datenbank
    zahlung.ts                  Stripe Checkout — ungetestet, siehe „Was fehlt"
    slots.ts                    freie Zeiten, mit Alterspuffer
    zeit.ts                     UTC-Instant + IANA-TZID, ohne Zeitzonenbibliothek
    mail/eingang.ts             MIME zerlegen, PDF-Text, Scans ablehnen
    mail/ausgang.ts             Versand mit Threading-Headern
    mail/threading.ts           In-Reply-To / References / Thread-Schlüssel
    llm/extraktion.ts           claude-haiku-4-5, Structured Outputs
    llm/formulierung.ts         claude-sonnet-5
    vorgang/zustand.ts          die Zustandsmaschine, rein und testbar
    vorgang/engine.ts           Seiteneffekte
    vorgang/darstellung.ts      die Zeile, die die Nutzerin liest
    sitzung.ts                  Anmeldung per Code, Fehlversuchszähler, Sitzung
    datenschutz/aufbewahrung.ts Löschfristen, rein und testbar
    datenschutz/betroffenenrechte.ts  Aufräumen, Export, Kontolöschung
  app/                          der eine Bildschirm plus zwei Ansichten
worker/email-worker.ts          Cloudflare Email Worker
```

## In Betrieb nehmen

`.env.example` nach `.env.local` kopieren und ausfüllen. Reihenfolge nach
Vorlaufzeit, nicht nach Aufwand:

1. **Google Cloud Console**, OAuth-Client anlegen, Rückleitung auf
   `<APP_URL>/api/google/callback`, `GOOGLE_CLIENT_ID` und
   `GOOGLE_CLIENT_SECRET` setzen. Die App läuft dabei **in Production,
   unverifiziert**: kein Calendar-Scope steht auf der Restricted-Liste, also
   keine CASA-Prüfung und keine Gebühr, aber ein Zähler von 100 Nutzerinnen,
   der projektgebunden und laut Google „cannot be reset or changed" ist.
   Deshalb: Entwicklung und Tests in einem **separaten** GCP-Projekt.
   Die Begründung steht in der Anbindungsentscheidung, Weg A.
2. **Domain zu Cloudflare**, Email Routing einschalten, Worker aus `worker/`
   deployen. Cloudflare verlangt seine eigenen Nameserver.
3. **Resend**, Domain verifizieren (SPF, DKIM, DMARC), `MAIL_ABSENDER` setzen.
4. **Neon**, `DATABASE_URL` setzen, `npm run db:push`.
5. **Cron** auf `/api/takt`, minütlich, mit `x-webhook-secret`. Der Takt sendet
   nicht nur fällige Post, er meldet auch still gebrochene
   Kalenderverbindungen — ohne ihn merkt niemand, dass der Kalender seit
   Tagen nicht mehr gelesen wird.
6. **Stripe** (optional), Produkt und Preis anlegen, `STRIPE_SECRET_KEY` und
   `STRIPE_PREIS_ID` setzen. Ohne die beiden läuft alles außer der
   Freischaltung. Vorher im Testmodus durchspielen, siehe „Was fehlt".
7. **Datenschutz**, und zwar bevor die erste fremde Mail durchläuft, nicht
   danach: [`docs/datenschutz/`](../docs/datenschutz/) durchgehen,
   `BETREIBER_*` setzen und erst nach anwaltlicher Prüfung
   `DATENSCHUTZ_GEPRUEFT=ja`. Solange das fehlt, steht auf `/datenschutz`
   sichtbar „Ungeprüfter Entwurf" — das ist Absicht.

Laufende Kosten nach der geprüften Recherche: Resend Pro 20 $, Cloudflare
Workers Paid 5 $, Vercel Pro 20 $ — zusammen 45 $ im Monat, plus Modellkosten
von rund 1,10 $ pro aktiver Nutzerin.

## Abweichungen vom Entwurf

Drei, alle absichtlich:

**Anmeldung per Mailcode statt Auth.js mit Google.** Der Entwurf nennt in
Abschnitt 6 „Auth.js v5 mit Google", fordert aber zwei Absätze vorher, dass der
Kalender-OAuth erst nach dem ersten sichtbaren Nutzen kommt. Google-Login bei
der Registrierung wäre genau der Dialog, den der Entwurf nach hinten schieben
will. Eine Anmeldung per Mail passt außerdem zum Produkt: es ist ein
Mail-Produkt, das Postfach ist ohnehin offen.

Der Weg hinein ist ein sechsstelliger **Code** zum Abtippen; in derselben Mail
steht zusätzlich ein Link. Der Code ist der Weg, der immer funktioniert — ein
Link, den das Mailprogramm in seinem eigenen eingebauten Browser öffnet, meldet
in einer Sitzung an, die die Nutzerin anschließend nicht wiederfindet. Sechs
Ziffern sind nur sicher, solange sie nicht beliebig oft geraten werden dürfen:
fünf Fehlversuche verbrauchen den Code, ein neuer geht frühestens nach 60
Sekunden und höchstens fünfmal je Stunde raus. Der Code wird mit Schlüssel
gehasht, nicht bloß mit SHA-256 — eine Million Möglichkeiten wären sonst offline
in Sekunden durchprobiert.

**Kein Prompt Caching.** Der Entwurf schreibt „Prompt Caching für den
System-Prompt". Das trägt hier nicht: die cachebare Mindestlänge liegt bei
Haiku 4.5 bei 4096 und bei Sonnet 5 bei 1024 Token, die System-Prompts liegen
deutlich darunter. Ein `cache_control`-Marker würde stillschweigend nichts
cachen. Deshalb steht er nicht im Code.

**Cloudflare Cron statt GitHub Actions.** Der Entwurf schlug GitHub Actions vor.
Deren kürzestes Intervall sind fünf Minuten — zu grob für eine
60-Sekunden-Haltezeit. Cloudflare Cron ist minutengenau, und der Worker läuft
für den Maileingang ohnehin.

## Was fehlt

Ehrlich benannt, damit es niemand für fertig hält:

- **Der Stripe-Teil ist ungetestet.** `src/lib/zahlung.ts` ist nie gegen echte
  Stripe-Endpunkte gelaufen; hier gibt es kein Stripe-Konto. Die Feldnamen
  stammen aus der dokumentierten Checkout-API, aber vor dem ersten echten
  Einsatz gehört das im Testmodus durchgespielt. Alles andere im Projekt ist
  getestet, das hier nicht — deshalb steht der Hinweis auch im Dateikopf.
- **Kein Stripe-Webhook.** Freigeschaltet wird bei der Rückkehr aus dem
  Checkout, durch eine Rückfrage bei Stripe — nicht durch das, was in der URL
  steht. Der Preis dafür ist bekannt: kehrt jemand nach der Zahlung nicht
  zurück, bleibt die Freischaltung aus, bis er die Seite das nächste Mal
  öffnet. Eine Webhook-Signaturprüfung, die niemand verifizieren kann, wäre
  gefährlicher als keine.
- **Kein automatisches Erneuern des Google-Zugriffs bei langer Pause.** Läuft
  ein Refresh-Token nach Monaten ohne Nutzung ab, erkennt der Takt das und
  schreibt die Nutzerin an — neu verbinden muss sie selbst.
- **Die anwaltliche Prüfung.** Der technische Datenschutz ist gebaut (siehe unten),
  die Vorarbeit liegt in [`docs/datenschutz/`](../docs/datenschutz/). Drei Fragen
  entscheiden aber über das Produkt und nicht nur über seine Papiere: ob der
  Volltext von Mails mit Gesundheitsdaten an den Modellanbieter gehen darf, wie
  § 203 Abs. 3 StGB auf die Anbieterkette anzuwenden ist, und ob eine
  Datenschutz-Folgenabschätzung nach Art. 35 Pflicht ist. Fällt die erste negativ
  aus, ändert sich die Architektur — nicht der Vertragstext.
- **Kein Impressum** nach § 5 DDG. Formal, aber abmahnfähig.

## Tests

116 Tests, ohne Netz und ohne externe Konten:

```bash
npm test
```

Die interessanten sind: `slots.test.ts` (Zeitzonen über die Sommerzeitumstellung,
Alterspuffer, Verteilung der Vorschläge), `zustand.test.ts` (jeder Übergang der
Zustandsmaschine, besonders „angeboten ist nicht eingeschaltet"),
`engine.test.ts` (voller Durchstich von der eingehenden Mail bis zum
Kalendereintrag, dazu Kompensieren, Bezahlschranke und der Zugriff auf fremde
Vorgänge), `eingang.test.ts` (echte PDF-Extraktion samt Ablehnung gescannter
Dokumente), `google-oauth.test.ts` (manipulierter und abgelaufener `state`,
und dass genau zwei Scopes angefragt werden — nicht mehr) und
`sitzung.test.ts` (falscher Code, Sperre nach fünf Versuchen, fremder Code,
Wiederverwendung, und dass Code und Link derselben Mail zusammen nur einmal
gelten) und `datenschutz/betroffenenrechte.test.ts` (dass beim Löschen eines Vorgangs die
Mails mit Gesundheitsdaten wirklich mitgehen und nicht als Waisen liegen
bleiben, und dass ein Vorgang mit einer Frist in der Zukunft trotzdem bleibt).
