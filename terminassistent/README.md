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

Dann auf <http://localhost:3000> mit `katrin@praxis-weber.example` anmelden. Der
Anmeldelink wird nicht versendet, sondern auf die Konsole geschrieben, auf der
`npm run dev` läuft.

Im Demo-Modus läuft die Datenbank eingebettet (PGlite in `.pglite/`), Texte
werden regelbasiert erzeugt statt von einem Modell, und Mails landen auf der
Konsole statt im Netz.

Weiter ausprobieren:

```bash
npm run tick              # fällige Sendungen und Erinnerungen abarbeiten
npm run tick -- --vor 2h  # so tun, als wären zwei Stunden vergangen
npm test                  # 59 Tests
```

## Was gebaut ist

| Funktion aus dem Entwurf | Stand |
|---|---|
| **A** Terminabstimmung per Mail | Vollständig. Freie Slots aus dem Kalender, drei Vorschläge über Tage *und* Tageszeiten verteilt, Verhandlung im selben Mail-Thread, Zusage wird erkannt und eingetragen. |
| **B** Fristenextraktion aus Dokumenten | Vollständig. PDF-Textextraktion inklusive; gescannte PDFs ohne Textschicht werden abgelehnt statt geraten (kein OCR). |
| **C** Nachfassen | Vollständig, inklusive der Vertrauensregel: nach drei bestätigten Sendungen an dieselbe Adresse *bietet* das System die Automatik an. |
| Haltezeit, Protokoll, Kompensieren | Haltezeit und Protokoll vollständig. Zum Kompensieren siehe „Was fehlt". |
| Bezahlen und Buchen | **Nicht gebaut**, wie in Abschnitt 3 des Entwurfs begründet. |

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

## Aufbau

```
src/
  db/schema.ts                  Datenmodell (Abschnitt 5 der Anbindungsentscheidung)
  lib/
    calendar/types.ts           CalendarSource / CalendarSink / PlacementResult
    calendar/google.ts          Weg A: OAuth, freebusy.query + events
    calendar/ics.ts             Weg B: Feed lesen, Feed schreiben, iMIP erzeugen
    calendar/registry.ts        der einzige Ort, der Kanalnamen kennt
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
  app/                          der eine Bildschirm plus zwei Ansichten
worker/email-worker.ts          Cloudflare Email Worker
```

## In Betrieb nehmen

`.env.example` nach `.env.local` kopieren und ausfüllen. Reihenfolge nach
Vorlaufzeit, nicht nach Aufwand:

1. **Google-Scopes prüfen** — Cloud Console → *Data Access*. Dort steht, ob
   `calendar.events` als sensitive gilt. Das ist öffentlich nirgends
   dokumentiert und entscheidet über den weiteren Weg. Kostet 15 Minuten.
   Entwicklung in einem **separaten** Projekt, weil der 100-Nutzer-Zähler
   projektgebunden und nicht rücksetzbar ist.
2. **Domain zu Cloudflare**, Email Routing einschalten, Worker aus `worker/`
   deployen. Cloudflare verlangt seine eigenen Nameserver.
3. **Resend**, Domain verifizieren (SPF, DKIM, DMARC), `MAIL_ABSENDER` setzen.
4. **Neon**, `DATABASE_URL` setzen, `npm run db:push`.
5. **Cron** auf `/api/takt`, minütlich, mit `x-webhook-secret`.

Laufende Kosten nach der geprüften Recherche: Resend Pro 20 $, Cloudflare
Workers Paid 5 $, Vercel Pro 20 $ — zusammen 45 $ im Monat, plus Modellkosten
von rund 1,10 $ pro aktiver Nutzerin.

## Abweichungen vom Entwurf

Drei, alle absichtlich:

**Anmeldung per Magic Link statt Auth.js mit Google.** Der Entwurf nennt in
Abschnitt 6 „Auth.js v5 mit Google", fordert aber zwei Absätze vorher, dass der
Kalender-OAuth erst nach dem ersten sichtbaren Nutzen kommt. Google-Login bei
der Registrierung wäre genau der Dialog, den der Entwurf nach hinten schieben
will. Ein Magic Link passt außerdem zum Produkt: es ist ein Mail-Produkt.

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

- **Der Kompensationsmechanismus.** Verzögern und Nachvollziehen sind gebaut,
  der automatische Korrekturentwurf nach einem Fehlversand nicht.
- **Google-OAuth-Flow in der Oberfläche.** `GoogleCalendarSource` und
  `GoogleCalendarSink` sind fertig und getestet, der Zustimmungs-Flow zum
  Einsammeln des Refresh-Tokens fehlt. Über die Oberfläche verbindbar sind
  bisher der ICS-Weg und die Attrappe.
- **Der iMIP-Weg** (Weg C) ist als Erzeugung vorhanden (`baueEinladung`), aber
  nicht als Sink verdrahtet — bewusst, weil die Anbindungsentscheidung ihn als
  schwächsten der drei Wege einstuft.
- **Der Überwachungsjob für `last_ok_at`.** Das Feld wird geschrieben, aber
  niemand schreibt die Nutzerin an, wenn eine Verbindung still bricht. Das ist
  laut Anbindungsdokument Teil des Produkts, nicht des Betriebs.
- **Bezahlung.** Der Zähler für die fünf freien Vorgänge läuft mit, Stripe ist
  nicht angebunden.
- **Alles Rechtliche.** Kein AVV, kein Verarbeitungsverzeichnis, keine
  Datenschutzerklärung, kein Impressum. Weitergeleitete Dokumente von
  Therapeutinnen enthalten Gesundheitsdaten — das ist vor der ersten fremden
  Mail anwaltlich zu klären, nicht danach.

## Tests

59 Tests, ohne Netz und ohne externe Konten:

```bash
npm test
```

Die interessanten sind: `slots.test.ts` (Zeitzonen über die Sommerzeitumstellung,
Alterspuffer, Verteilung der Vorschläge), `zustand.test.ts` (jeder Übergang der
Zustandsmaschine, besonders „angeboten ist nicht eingeschaltet"),
`engine.test.ts` (voller Durchstich von der eingehenden Mail bis zum
Kalendereintrag) und `eingang.test.ts` (echte PDF-Extraktion samt Ablehnung
gescannter Dokumente).
