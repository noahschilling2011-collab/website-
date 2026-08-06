# Kalender- und Mail-Anbindung: Entscheidungsvorlage

Ergänzung zu [`ki-alltagsassistent-entwurf.md`](./ki-alltagsassistent-entwurf.md),
Abschnitt 6. Beantwortet die dort offene Frage: **Wie verknüpft man Kalender und
Mail so, dass es als Einzelperson ohne Firma und ohne Budget tatsächlich läuft?**

Alle Werte gegen die Herstellerdokumentation geprüft, Stand 2026-08-05. Was nicht
belegt werden konnte, steht in Abschnitt 7 und darf nicht in eine Entscheidung
eingehen.

---

## 1. Die Ausgangsannahme war falsch

Der Entwurf ging davon aus, dass die Google-OAuth-Verifizierung für
Kalender-Zugriff der harte Blocker ist — mit Sicherheitsprüfung, Kosten und
Wochen an Vorlauf. **Das trifft nicht zu.**

Kein Google-Calendar-Scope steht auf der Restricted-Liste; dort stehen Gmail,
Drive, Fit, Chat, Data Portability, Photos Ambient und Health
([Quelle](https://support.google.com/cloud/answer/13464325)). Die jährliche
CASA-Sicherheitsprüfung gilt ausdrücklich nur für restricted Scopes: „5. Security
Assessment (For restricted scopes only)"
([Quelle](https://support.google.com/cloud/answer/13464321)). Die kursierenden
Beträge von 500 bzw. 3.000–6.000 USD stammen aus der MASA-FAQ für den Play Store,
nicht aus CASA ([Quelle](https://appdefensealliance.dev/masa/faq)). Für die
Verifizierung selbst ist in keiner geprüften Google-Quelle eine Gebühr
dokumentiert.

Damit fällt der teuerste Teil des vermuteten Blockers weg. Der reale Blocker ist
ein anderer und kleiner — aber er ist unwiderruflich.

## 2. Der reale Blocker

**Nicht die Verifizierung blockiert, sondern der Publishing-Status.**

| Status | Was passiert | Ab wann es blockiert |
|---|---|---|
| **Testing** | „limited to up to 100 test users"; Autorisierung **und** Refresh-Token laufen nach 7 Tagen ab. Die Ausnahme gilt nur für `name`/`email`/`profile` — „If your app requests any other OAuth scopes, then this exception does not apply." | **Ab Nutzer 1.** Nach einer Woche muss jede Nutzerin neu verbinden. Unbrauchbar. |
| **In production, unverifiziert** | Dauerhafte Token, aber „100 new users in total, after the app presents the unverified app screen". Der Zähler gilt „over the entire lifetime of the project" und „cannot be reset or changed". Ausschöpfung „might result in… Google sign-in to be disabled". | **Ab Nutzer 101.** Unwiderruflich. |
| **Verifiziert** | Kein Cap. | — |

Quellen: [Publishing-Status und
Limits](https://support.google.com/cloud/answer/15549945), [User
Cap](https://support.google.com/cloud/answer/13464323), [Folgen der
Ausschöpfung](https://support.google.com/cloud/answer/13463817).

Google verbietet den unverifizierten Betrieb ausdrücklich nicht: „If the app is
for your personal use (fewer than 100 users), you and your limited number of
users can continue using the app without going through verification (users will
be allowed to click through unverified app warning screens during sign-in)."

Was die Verifizierung später verlangt, ist belegt und machbar: eigene verifizierte
Domain mit Nachweis über die Google Search Console, korrekte Markendarstellung,
eine Homepage, die die Funktionalität beschreibt und „can not be only a login
page", ein Datenschutz-Link auf der Homepage identisch mit dem im Consent-Screen,
ein englischsprachiges Demo-Video als „Unlisted" auf YouTube mit sichtbarer
Client-ID in der Adressleiste, und eine Scope-Begründung. Dauern laut Google:
Brand Verification 2–3 Werktage, Sensitive Scope Verification 10 Werktage,
Restricted 6 Wochen — „these estimates are not guaranteed". Bei Ablehnung müssen
alle Unterlagen neu eingereicht werden.

## 3. Drei Wege, den Kalender anzubinden

CalDAV steht bewusst **nicht** in dieser Liste. Google verlangt für CalDAV
ausdrücklich OAuth 2.0 und ein Cloud-Projekt und lehnt Basic Auth mit HTTP 401 ab
— man bekäme OAuth *plus* XML-Protokoll bei identischen Quotas
([Quelle](https://developers.google.com/workspace/calendar/caldav/v2/guide)).
Microsoft unterstützt CalDAV nicht; die Protokollliste nennt es nicht, und
`outlook.office365.com/.well-known/caldav` antwortet mit HTTP 404 (eigene Messung
2026-08-05). Bliebe iCloud mit app-spezifischen Passwörtern, die zugleich Mail und
Kontakte freischalten, auf 25 begrenzt sind und bei **jeder** Apple-Passwortänderung
sämtlich widerrufen werden ([Quelle](https://support.apple.com/en-us/102654)).

### Weg A — Google OAuth, eng gefasst, unverifiziert in Production

**Technik.** OAuth 2.0 Authorization Code Flow mit `access_type=offline`,
Refresh-Token verschlüsselt in der eigenen Datenbank. Verfügbarkeit über
`freebusy.query` mit dem engsten dafür zulässigen Scope
`https://www.googleapis.com/auth/calendar.freebusy`
([Referenz](https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query)),
Schreiben über `events.insert`/`patch`/`delete` mit `calendar.events`.

**Was die Nutzerin einmalig tut.** „Google-Kalender verbinden" klicken →
Google-Login → Bildschirm „Google hat diese App nicht überprüft" → „Erweitert" →
„Zu <App> (unsicher) wechseln" → Berechtigungen bestätigen. Ein Redirect, ein
Warnbildschirm, zwei zusätzliche Klicks.

**Was nicht geht.** Apple- und Outlook-Nutzerinnen sind nicht abgedeckt
(Microsoft bräuchte einen separaten Graph-Weg, iCloud hat keinen OAuth-Weg).
Nutzerin 101 kann sich nicht verbinden. Der Warnbildschirm steht am Anfang jeder
Verbindung — bei einer Zielgruppe, die mit Patientendaten arbeitet, ist das ein
Vertrauensproblem, kein Funktionsproblem.

**Aufwand: 5–7 Personentage (Schätzung).** GCP-Projekt und Consent-Screen 0,5–1,
OAuth-Flow mit Token-Handling 2–3, Calendar-API 2–3.

**Bricht:** bei Nutzerin 101, unwiderruflich. Bei jeder Nicht-Google-Nutzerin
sofort. Bei 6 Monaten Nichtnutzung läuft das Refresh-Token ab.

### Weg B — ICS-Feed lesen, eigenen ICS-Feed zum Abonnieren schreiben

**Technik.** Lesen: HTTPS-GET auf die private iCal-URL des Nutzerkalenders,
geparst mit `node-ical` 0.27.1 (RRULE-Expansion, EXDATE, RECURRENCE-ID) oder
`ical.js` 2.2.1. Schreiben: **nicht** in den Fremdkalender. Die App ist der
Terminspeicher und stellt pro Nutzerin einen tokenisierten HTTPS-Endpunkt bereit,
der ein VCALENDAR mit `Content-Type: text/calendar` ausliefert (`ical-generator`
11.1.0, ohne METHOD — PUBLISH-Semantik). Diesen Link abonniert die Nutzerin
einmalig; die Termine erscheinen als separater, schreibgeschützter Kalender.

**Was die Nutzerin einmalig tut.** Zwei Kopier-Einfüge-Vorgänge in fremder UI:
- *Lesen, Google:* Einstellungen → „Einstellungen für meine Kalender" → Kalender
  → „Kalender integrieren" → „Geheime Adresse im iCal-Format" kopieren.
  Googles eigener Hinweis dazu: „Only you should know the Secret Address."
- *Schreiben, Google:* „Weitere Kalender" → „+" → „Per URL" → Link einfügen.
- Für Outlook.com und iCloud existieren äquivalente Wege (Outlook: „Kalender
  veröffentlichen" mit drei Detailstufen; iCloud: „Öffentlicher Kalender" und
  `webcal` durch `http` ersetzen).

**Was nicht geht.** Die Termine sind im Nutzerkalender schreibgeschützt — die
Therapeutin kann sie dort nicht verschieben. Änderungen, die sie im
Google-Kalender macht, fließen nie zurück. Kein Push, keine Bestätigung des
Abrufs. Der Feed liefert beim Lesen den **vollen** Kalender inklusive Titel und
Teilnehmern, nicht nur Belegtzeiten. Widerruf nur global: Googles „Reset"
invalidiert die Adresse für alle Konsumenten gleichzeitig. Bei Firmen- und
Schulkonten kann der Admin die Secret Address abgeschaltet haben. iCloud liefert
nur −6 Monate bis +3 Jahre.

**Aufwand: 8–12 Personentage (Schätzung).** Lesepfad mit RRULE, VTIMEZONE,
Polling, Deduplizierung 4–6; Feed-Endpunkt mit Token, Zeitzonen, ETag 2–3;
Mailversand ohne iMIP 2–3.

**Bricht:** sobald die Nutzerin erwartet, einen Termin im eigenen Kalender direkt
zu verschieben. Und potenziell an der Aktualisierungslatenz des Abonnements —
**dieser Wert ist bei keinem der drei Anbieter dokumentiert und muss mit echten
Konten gemessen werden**, bevor man sich darauf festlegt. Microsoft sagt
ausdrücklich: „How often your ICS calendar syncs depends on the recipient's email
provider." Skalierungsseitig bricht dieser Weg nicht: kein Nutzerlimit, keine
Verifizierung, keine Anbieter-Quota.

### Weg C — ICS-Feed lesen, Termine als Mail-Einladung schicken (iMIP)

**Technik.** Lesen wie in Weg B. Schreiben als echte Kalendereinladung per Mail:
`ical-generator` erzeugt ein VEVENT mit `ICalCalendarMethod.REQUEST`, `nodemailer`
9.0.4 verschickt es als MIME-Part `Content-Type: text/calendar; method=REQUEST;
charset=UTF-8; component=vevent` (RFC 5545 + RFC 5546 + RFC 6047). Ändern: gleiche
UID, erhöhte SEQUENCE, erneut METHOD:REQUEST. Absagen: METHOD:CANCEL, SEQUENCE+1,
STATUS:CANCELLED. Zusagen kommen als METHOD:REPLY-Mails zurück und müssen selbst
empfangen, geparst und über die UID zugeordnet werden.

**Was die Nutzerin einmalig tut.** Für den Schreibpfad: nichts. Die Einladung
kommt per Mail. Genau das ist zugleich das Problem.

**Was nicht geht.** Keine Bestätigung, ob der Termin im Kalender gelandet ist —
keine Event-ID zurück, kein Statuscode, keine Diagnose bei Ausbleiben. RFC 6047
sagt es selbst: ORGANIZER und ATTENDEE „cannot be reliably inferred by the
[RFC5322] 'Sender' or 'Reply-To' header field values"; als Authentifizierung
nennt der RFC nur S/MIME. Ob eine Einladung automatisch im Kalender erscheint,
entscheidet **der Empfänger**, nicht der Absender: Gmail kennt drei Stufen („From
everyone" / „Only if the sender is known" / „When I respond to the invitation in
email"), Apple und Microsoft haben eigene Schalter, in Workspace setzt sie der
Admin zentral. Diese Einstellung ist nicht auslesbar und nicht als Fehlerursache
erkennbar.

**Aufwand: 13–20 Personentage (Schätzung).** Lesepfad 4–6, Schreibpfad mit
korrekter MIME-Struktur, SEQUENCE- und CANCEL-Logik und Tests gegen echte Gmail-,
Outlook- und iCloud-Postfächer 5–8, RSVP-Rücklesen 4–6.

**Bricht:** still. Bei falsch gebauter MIME-Struktur degradiert Outlook die
Einladung wortlos zum Anhang (MS-STANOICAL V0341 und V0343). Bei
Exchange-Raumpostfächern ohne `Set-CalendarProcessing -ProcessExternalMeetingMessages
$True`. Und dauerhaft an der Zustellbarkeit: Gmail verlangt seit 01.02.2024 von
allen Absendern SPF oder DKIM, gültige Forward-/Reverse-DNS, TLS und eine
Spam-Rate unter 0,3 %.

## 4. Empfehlung für Woche 1 bis 6

**Weg A** — Google OAuth mit `calendar.freebusy` und `calendar.events`,
Publishing-Status „In production", ohne Verifizierungsantrag. Mit zwei Auflagen:

1. **Vor allem anderen die Scope-Einstufung ablesen.** Cloud Console → *Data
   Access → Add or remove scopes*. „Added scopes are classified as non-sensitive,
   sensitive, or restricted." Nur dort steht, ob `calendar.events` als sensitive
   gilt. Kostet 15 Minuten und entscheidet über Demo-Video und
   Verifizierungspflicht.
2. **Entwicklung und Tests in einem separaten GCP-Projekt.** Der 100-Nutzer-Cap
   gilt laut Wortlaut projektgebunden („over the entire lifetime of the
   project"). Das Produktivprojekt startet damit mit unverbrauchtem Kontingent.
   *Diese Ableitung stützt sich auf den Wortlaut, ist aber keine ausdrückliche
   Google-Zusage.*

**Begründung.** In sechs Wochen mit einer Person sind 100 Nutzerinnen nicht
erreichbar. OAuth ist zugleich der kleinste Weg — 5–7 Personentage gegen 8–12 und
13–20 — und liefert als einziger echte Belegtzeiten ohne Termininhalte, echtes
Schreiben und eine Bestätigung, dass der Termin steht. Der Warnbildschirm kostet
Vertrauen, nicht Funktion.

**Das Kriterium, an dem die Entscheidung hängt:** Ob mehr als 100 Nutzerinnen im
ersten Jahr realistisch sind. Darunter → Weg A, Verifizierung später. Darüber →
Weg B sofort bauen, weil er kein Nutzerlimit kennt und die Verifizierung ohnehin
drei bis vier Wochen Vorlauf plus Homepage, Datenschutzerklärung und
englischsprachiges Demo-Video braucht.

Weg B bleibt als zweiter Provider hinter derselben Schnittstelle — gebaut, wenn
die erste Nutzerin ohne Google auftaucht.

## 5. Die Abstraktion, die den Wechsel billig macht

Lesen und Schreiben sind bei den ICS-Wegen physisch **verschiedene Kanäle** und
dürfen deshalb nicht in einem Interface stecken. Zwei getrennte Schnittstellen:

```ts
type BusyInterval = { start: Date; end: Date; source: string };

interface CalendarSource {
  readonly connectionId: string;
  getBusy(range: { from: Date; to: Date }): Promise<BusyInterval[]>;
  capabilities: {
    push: boolean;                 // false bei ICS
    detail: 'busy' | 'full';       // 'full' beim ICS-Feed, 'busy' bei freebusy.query
    maxStalenessSeconds: number;   // Polling-Alter; bei OAuth nahe 0
    horizonPast?: Date;            // iCloud: −6 Monate
    horizonFuture?: Date;          // iCloud: +3 Jahre
  };
}

interface CalendarSink {
  create(draft: EventDraft): Promise<PlacementResult>;
  update(ref: PlacementRef, draft: EventDraft): Promise<PlacementResult>;
  cancel(ref: PlacementRef, reason?: string): Promise<PlacementResult>;
  capabilities: {
    confirmsPlacement: boolean;      // nur bei OAuth
    userEditable: boolean;           // false beim ICS-Abo
    deliversToThirdParties: boolean; // nur bei iMIP
  };
}

type PlacementRef = { kind: 'google_event_id' | 'icalendar_uid'; value: string };

type PlacementResult =
  | { status: 'placed';     ref: PlacementRef }  // OAuth: verifiziert im Kalender
  | { status: 'dispatched'; ref: PlacementRef }  // iMIP: Mail raus, Ausgang unbekannt
  | { status: 'published';  ref: PlacementRef }; // Feed: im Feed, Abruf unbekannt
```

### Fünf Entscheidungen, die in Woche 1 fallen müssen

1. **Eigene iCalendar-UID ab Tag 1, auch im OAuth-Pfad.** Form nach RFC-822
   addr-spec (`<opaque>@meine-domain.de`). Google-Event-IDs werden zusätzlich
   gespeichert, nie als Primärschlüssel. Ohne eigene UID ist Weg C später nicht
   nachrüstbar.
2. **Eigener SEQUENCE-Zähler ab Tag 1.** Erhöht bei jeder Änderung von DTSTART,
   DTEND, DURATION, DUE, RRULE, RDATE, EXDATE, STATUS und bei jeder Absage — genau
   nach RFC 5546. Im OAuth-Pfad tot, kostet eine Spalte. Ohne ihn fehlt später die
   Historie.
3. **`PlacementResult` mit drei Zuständen statt `boolean`.** Der Unterschied
   zwischen „steht im Kalender", „Mail ist raus" und „steht im Feed" schlägt bis
   in die UI durch. Wer das auf `success: true` reduziert, muss beim Wechsel jeden
   UI-Text anfassen.
4. **Eine Verbindungstabelle mit Diskriminator, nicht zwei Tabellen:**
   ```
   calendar_connections(
     id, user_id,
     kind,        -- 'google_oauth' | 'ics_secret_url' | 'ics_publish' | 'imip_mail'
     secret_ref,  -- Zeiger auf verschlüsselte Ablage
     last_ok_at, last_error, last_error_at,
     created_at, revoked_at
   )
   ```
   `last_ok_at` und `last_error` sind Pflicht, keine Kür: **beide Wege brechen
   still.** Bei OAuth läuft das Refresh-Token nach 6 Monaten Nichtnutzung ab, bei
   ICS invalidiert ein Reset der Secret Address die URL ohne jede Meldung. Ein
   Job, der `last_ok_at` überwacht und die Nutzerin anschreibt, ist Teil des
   Produkts, nicht des Betriebs.
5. **Zeit ausschließlich als UTC-Instant plus IANA-TZID.** Der ICS-Feed liefert
   VTIMEZONE-Blöcke, die Calendar API RFC-3339-Strings mit Offset. Beide müssen
   auf dieselbe interne Form abbilden, bevor Anwendungscode sie sieht. Sonst ist
   der Providerwechsel eine Datenmigration.

**Was sich nicht abstrahieren lässt:** der Onboarding-Flow. „Mit Google
verbinden" ist ein Redirect; „kopiere deine geheime iCal-Adresse hierher" sind
fünf Klicks in fremder UI. Das sind zwei UI-Flows, die nebeneinander existieren
müssen. Dafür in Woche 1 eine `ConnectFlow`-Komponente pro `kind` vorsehen, kein
generisches Formular mit einem Textfeld.

**Geschätzter Zusatzaufwand für den späteren Wechsel bei sauberer Abstraktion:**
4–6 Personentage für `IcsFeedSource` plus `IcsPublishSink`, weitere 6–10 für
`ImipMailSink` inklusive RSVP-Rückkanal.

## 6. Mail: eingehend und ausgehend

**Ausgehend — Resend Pro, 20 $/Monat.** Einziger geprüfter Dienst ohne
Freigabeprozess: „Resend does not require production approval… There is no
sandbox mode, no approval process, and no waiting period." Und der einzige mit
dokumentiertem Threading über `In-Reply-To` und `References` — konstitutiv für
Funktion A und C, denn ein Nachfassen, das beim Empfänger einen neuen Thread
aufmacht, ist ein anderes Produkt. Free scheidet aus: 3.000 Mails im Monat, aber
hartes Tageslimit 100, und eingehende Mails zählen gegen dasselbe Kontingent. Pro
liefert 50.000 Mails ohne Tageslimit, danach 0,90 $ je 1.000.

Warum die anderen ausscheiden:

| Dienst | Grund |
|---|---|
| Brevo Free | „Standard email headers are not supported" — kein `In-Reply-To` per API. Zusätzlich „Sent with Brevo"-Footer und Kontofreigabe vor dem ersten Versand. |
| Postmark | Manuelle Kontoprüfung; Preislücke von 100 Mails/Monat direkt auf 10.000; günstigster Plan mit Inbound ist Pro für 16,50 $. |
| Mailgun | Free 100 Mails/Tag, 1 Tag Log-Retention, und ein dokumentierter Selbstwiderspruch zur eigenen Domain zwischen Preisseite und FAQ. |
| Amazon SES | Mit 0,10 $ je 1.000 Mails der billigste Versand und mit eu-central-1 in der EU. Dagegen: Sandbox mit 200 Mails/24 h und 1 Mail/s, Production-Antrag mit Pflichtfeld „Website URL", kein Kostendeckel. Für Monat 1–6 zu viel Prozess für ~19 $ Ersparnis; als Migrationsziel bei hohem Volumen richtig. |

**Eingehend — Cloudflare Email Routing plus Workers Paid, ab 5 $/Monat.** Der
Grund ist Funktion B: Die Fristen stecken in weitergeleiteten PDFs, und Cloudflare
ist der einzige geprüfte Weg, der die vollständige Rohnachricht liefert
(`ForwardableEmailMessage.raw` als ReadableStream, von Cloudflare selbst mit
`postal-mime` zum Parsen empfohlen). Resend Inbound liefert per Webhook
ausdrücklich nur Metadaten: „Webhooks do not include the email body, headers, or
attachments, only their metadata." Ob sich Volltext und Anhang über die
Resend-API nachladen lassen, ist **nicht belegt und sollte geprüft werden** —
falls ja, spart man die 5 $ und den DNS-Umzug.

Der Free-Plan reicht nicht: 10 ms CPU pro Nachricht sind für MIME-Zerlegung,
Base64-Dekodierung und PDF-Textextraktion nicht realistisch; die Doku nennt für
genau diesen Fall den Fehler `EXCEEDED_CPU`. Paid hebt auf 30 Sekunden Default,
konfigurierbar bis 5 Minuten.

**Was man dafür in Kauf nimmt, belegt:** Zwangsumzug der gesamten DNS-Hoheit zu
Cloudflare („You must be using Cloudflare DNS to use Email Service"). Kein
Postfach und keine Speicherung — bricht der Worker ab, ist die Mail weg. Keine
Weiterleitung von Non-Delivery-Reports an den Absender. Kein SLA und keine
Supportpflicht; Cloudflare „reserves the right to modify or discontinue
Cloudflare Email Routing at any time". Eingehende Mails, die weder SPF noch DKIM
bestehen, werden abgelehnt. Die Nutzung ist vertraglich auf „Transactional
Emails" auf eigenen Domains begrenzt.

**Summe: 25 $/Monat** (Resend Pro 20 + Cloudflare Workers Paid 5), plus Vercel Pro
20 $. Das ist gegenüber der Kalkulation in Abschnitt 10 des Entwurfs eine
Erhöhung der Fixkosten von ~35 $ auf ~45 $ im Monat — bei 100 zahlenden Nutzern
0,45 $ pro Kopf statt 0,35 $. Die Deckungsbeitragsrechnung bleibt tragfähig.

## 7. Weiterhin unbelegt

Diese Punkte haben die Quellenprüfung **nicht** bestanden und dürfen nicht in eine
Entscheidung eingehen:

1. **Sensitivitäts-Einstufung von `calendar.events`.** Belegt ist nur „nicht
   restricted". Eine positive Einstufung als „sensitive" steht in keiner
   öffentlichen Google-Quelle; ablesbar nur in der Cloud Console. *Wichtigste
   offene Frage dieses Dokuments.*
2. Einstufung von `calendar.freebusy` und `calendar.events.freebusy` — dito.
3. „Readonly-Scopes bestehen die Begründungsprüfung leichter" — Vermutung, keine
   Google-Aussage.
4. **Refresh-Intervall abonnierter ICS-Feeds.** Die kursierenden 8–24 Stunden sind
   in keiner Herstellerdoku belegt. Microsoft sagt ausdrücklich, es hänge vom
   Provider ab. Für Weg B muss dieser Wert mit echten Konten gemessen werden.
5. Rate-Limits auf ICS-Endpunkte bei Google, Apple, Microsoft — keine Quelle.
6. **Google-Default für „Add invitations to my calendar".** Das Wort „default"
   kommt auf der Seite nicht vor. Man darf nicht zusagen, dass eine Einladung
   automatisch im Kalender erscheint.
7. Dass irgendein Hersteller die Annahme einer iMIP-Einladung eines
   Dritt-Absenders zusagt. Weg C ist prinzipiell Best-Effort.
8. Ob Email-Worker-Invocations gegen Cloudflares 100.000 Requests/Tag zählen;
   Cloudflares konkretes tägliches Sendelimit („conservative daily quota… scale
   up over time"); ob `message.reply()` im Free-Plan funktioniert.
9. **Alle DSGVO- und Impressumsaussagen** — DDG § 5, Art. 28/32/33 DSGVO,
   Drittlandtransfer, § 203 StGB, Haftung ohne Rechtsträger. Gegen keine
   Rechtsquelle geprüft, anwaltlich zu klären.
