# KI-Alltagsassistent — Produktentwurf

Entscheidungsgrundlage, kein Marketingtext. Harte Vorgaben: eine Person, kein
Budget, Web im Browser, erste benutzbare Version nach 6 Wochen online.

---

## TEIL 1

### 1. Die Existenzfrage

Die strukturelle Eigenschaft heißt **Fehlerkosten mal Nutzerzahl**.

Ein Fehler eines Agenten kostet Apple, Google, OpenAI und Microsoft nicht einmal
Ärger, sondern einmal Ärger pro Nutzer, plus Presse, plus Regulierer, plus
Vertragspartner. Bei 500 Millionen Nutzern ist eine Fehlerquote von 0,1 % eine
halbe Million Vorfälle. Das erzwingt bei ihnen eine Produktentscheidung, die sie
nicht zurücknehmen können: **Ihr Agent schlägt vor, er handelt nicht.** Er
formuliert Mails, die man abschickt; er zeigt Termine, die man bestätigt.

Genau das ist die verteidigbare Lücke: Aktionen, die sie aus Haftungs- und
Skalierungsgründen niemals autonom ausführen lassen, kann eine Einzelperson mit
200 Nutzern ausführen lassen — weil ihr Gesamtrisiko das Risiko von 200
Vorfällen ist, nicht von 200.000.

Die Ehrlichkeit dazu: Das ist Risiko-Arbitrage, kein Burggraben. Er hält,
solange man klein ist. Siehe Abschnitt 8.

### 2. Ein Nutzer

Katrin, 44, selbstständige Ergotherapeutin mit eigener Praxis in Kassel, zwei
Behandlungsräume, keine Rezeption. Montag bis Donnerstag 8–17 Uhr Patienten im
45-Minuten-Takt, Freitag Abrechnung und Verordnungsprüfung. Termine vereinbart
sie zwischen den Behandlungen: Anrufe, die sie nicht annehmen kann, WhatsApp,
Mails von Eltern und Pflegediensten.

Der Dienstag, an dem sie das Produkt öffnet, ist der Dienstag nach dem Freitag,
an dem eine Verordnung verfallen ist. Ein Kinderarzt hatte am 14. eine
Folgeverordnung geschickt, mit Frist. Die Mail lag unter neununddreißig anderen.
Sie hat sie am 3. gefunden, zwei Tage zu spät, und der Kasse 312 Euro nicht in
Rechnung stellen können. Am selben Dienstagmorgen schreibt eine Mutter zum
vierten Mal wegen eines Verlegungstermins; Katrin hat dreimal geantwortet, jedes
Mal nach 21 Uhr, jedes Mal war der Termin schon weg.

Sie sucht nicht nach einem KI-Assistenten. Sie sucht nach etwas, das den
Mailverkehr über Termine für sie zu Ende führt.

### 3. Drei Funktionen

**A — Terminabstimmung per Mail.** Der Assistent führt einen weitergeleiteten
Mail-Thread mit einem Dritten, schlägt aus freien Kalenderslots Termine vor,
verhandelt bis zur Zusage und legt den Termin in den Kalender.

- *Braucht:* eine eigene Weiterleitungsadresse auf der Domain des Produkts,
  Google-Calendar-OAuth (Scope für Kalenderereignisse), den Inhalt des
  weitergeleiteten Threads. Kein Postfachzugriff.
- *Irrtum:* falscher Termin gegenüber einem Patienten oder Arzt. Kosten: eine
  peinliche Korrekturmail, im Ernstfall ein Ausfalltermin — für Katrin 45
  Minuten Umsatz, ca. 40–60 Euro, plus Reputationsschaden bei genau der Person,
  die sie behalten will. Mittelschwer und sozial teuer.

**B — Fristenextraktion aus weitergeleiteten Dokumenten.** Der Assistent liest
weitergeleitete Mails und PDF-Anhänge, extrahiert Datum, Frist, Betrag und
Absender und legt daraus einen Kalendereintrag plus Erinnerung an.

- *Braucht:* dieselbe Weiterleitungsadresse, Kalenderschreibrechte, Dateispeicher
  für die Anhänge.
- *Irrtum:* falsch gelesenes Datum, übersehene Frist. Kosten: exakt der Fall aus
  Abschnitt 2 — 312 Euro und ein verfallener Anspruch. Der teuerste der drei
  Irrtümer, und der gefährlichste, weil er lautlos ist.

**C — Nachfassen bei ausbleibender Antwort.** Der Assistent überwacht einen
laufenden Thread und sendet nach einem vom Nutzer gesetzten Intervall eine
Erinnerung an denselben Empfänger.

- *Braucht:* Thread-Zustand, Versandrechte über die Produktdomain.
- *Irrtum:* Nachfassen bei jemandem, der bereits geantwortet hat, oder zu früh.
  Kosten: gering und rein sozial. Genervter Empfänger.

**Was in Wochen 1–6 bewusst nicht enthalten ist:** Reisen buchen, Einkäufe
tätigen, Geld ausgeben. Nicht weil es unwichtig wäre, sondern weil es keine
legale, frei zugängliche Buchungs-API für Einzelentwickler gibt und die Haftung
(Abschnitt 5) in sechs Wochen nicht lösbar ist. Der Auftrag verlangte einen
Assistenten, der auch bucht — ich liefere die Bezahl- und Buchungsschicht nicht,
und sage das offen, statt sie zu behaupten.

### 4. Die Nicht-Liste

1. **Chat-Interface als Hauptbedienung** — verschiebt die Arbeit zum Nutzer
   zurück, statt sie abzunehmen.
2. **Voller Posteingangszugriff (Gmail-API, Read-All)** — der teuerste
   Berechtigungsdialog der Welt, direkt am Anfang.
3. **Mobile App** — Vorgabe ist Browser; App Store wäre zwei zusätzliche Wochen
   ohne einen zusätzlichen Nutzer.
4. **Flug- und Hotelbuchung** — keine zugängliche API, unkalkulierbare Haftung.
5. **Bezahlvorgänge jeder Art** — siehe 4; zusätzlich PSD2 und
   Rückbuchungsrisiko.
6. **Einkaufslisten und Rezepte** — anderes Problem, anderer Nutzer, nur
   oberflächlich dieselbe Kategorie.
7. **Team- und Mehrbenutzerfunktionen** — Katrin ist allein; jede Rollenlogik ist
   Aufwand für einen fiktiven Kunden.
8. **Eigener Kalender** — Google Calendar existiert, funktioniert und ist da, wo
   der Nutzer schon hinschaut.
9. **Outlook-/Microsoft-Integration** — zweiter OAuth-Pfad, zweites
   Verifizierungsverfahren, halbe Woche für vielleicht 20 % der Zielgruppe.
10. **WhatsApp-Anbindung** — Business-API ist kostenpflichtig, freigabepflichtig
    und für Einzelpersonen praktisch verschlossen.
11. **Spracheingabe** — löst kein Problem aus Abschnitt 2.
12. **Eigenes Modelltraining oder Fine-Tuning** — kein Datenbestand, kein Budget,
    kein Vorteil.
13. **Automatische Mailkategorisierung des gesamten Postfachs** — setzt 2 voraus,
    das nicht gebaut wird.
14. **Analytics-Dashboard für den Nutzer** — Katrin will keine Statistik über
    ihre Termine, sie will die Termine.
15. **Kostenlose Stufe ohne Limit** — jeder Nutzer verursacht direkte API-Kosten;
    eine unbegrenzte Gratisstufe ist ein Verlustversprechen.

### 5. Das Vertrauensproblem

**Grenze zwischen fragen und handeln.** Sie verläuft nicht bei „wichtig vs.
unwichtig", sondern bei **umkehrbar vs. nicht umkehrbar**. Alles, was das System
nicht verlässt — Kalendereinträge, Erinnerungen, interne Zustände — passiert
automatisch, weil es sich rückstandslos löschen lässt. Alles, was die Außenwelt
erreicht — jede Mail an einen Dritten — braucht einen Klick. Festgelegt wird das
nicht vom Nutzer per Schieberegler, sondern pro Empfänger und Aktionstyp und
erarbeitet: Nach drei bestätigten Sendungen desselben Typs an dieselbe Adresse
bietet das System an, künftig automatisch zu senden. Vertrauen wird verdient,
nicht abgefragt.

**Zugriff ohne Abbruch beim Berechtigungsdialog.** Indem man ihn nicht stellt.
Kein Postfachzugriff: Der Nutzer bekommt eine eigene Adresse (`katrin@…`) und
leitet weiter oder setzt sie in CC. Das ist eine bewusste Entscheidung pro
Vorgang statt einer Blankovollmacht, sie ist in fünf Sekunden erklärt, und der
Nutzer versteht exakt, was das System sieht: das, was er hingeschickt hat. Der
einzige echte OAuth-Dialog ist der Kalender, und er kommt erst, wenn der erste
Termin geschrieben werden soll — nach dem ersten sichtbaren Nutzen, nicht davor.

**Haftung.** Rechtlich (keine Rechtsberatung, im Zweifel prüfen lassen): Handelt
der Nutzer über eine erteilte Vollmacht, bindet die Erklärung ihn gegenüber dem
Dritten — der Vertrag kommt mit ihm zustande. Im Innenverhältnis haftet der
Betreiber für schuldhaft verursachte Schäden, und ein Ausschluss für grobe
Fahrlässigkeit und Kardinalpflichten wäre nach AGB-Recht unwirksam. Praktisch
heißt das: Der Nutzer gibt mir die Schuld, und ich erstatte, ohne die Rechtslage
zu bemühen. Genau darum steht in Wochen 1–6 vor jeder Außenwirkung ein Klick und
kein Zahlungsmittel im System.

**Rückgängig.** Es gibt kein Rückgängig für eine gesendete Mail. Wer das
behauptet, lügt. Es gibt drei Ersatzmechanismen: **Verzögern** (60 Sekunden
Haltezeit vor jedem Versand, abbrechbar), **kompensieren** (bei Abbruch nach
Versand generiert das System eine Korrekturmail als Entwurf und storniert den
Kalendereintrag), **nachvollziehen** (vollständiges Protokoll, was wann an wen
ging, im Wortlaut). Das ist ehrlicher als ein Undo-Knopf und deckt den realen
Fall ab.

### 6. Technik, Woche 1 bis 6

- **Next.js 15 (App Router) auf Vercel.** Hobby-Tier untersagt kommerzielle
  Nutzung; Pro derzeit ca. 20 $/Monat — Konditionen prüfen.
- **Postgres bei Neon**, Drizzle ORM. Kostenloses Kontingent reicht für 100
  Nutzer; Grenzen unsicher, prüfen.
- **Auth.js v5** mit Google als Provider.
- **Eingehende Mail: Cloudflare Email Routing + Email Worker.** Existiert, bei
  eigener Domain in Cloudflare kostenlos. Nachrichtengrößen- und Ratenlimits
  **unsicher, müssen geprüft werden**. Fallback: Postmark Inbound oder Mailgun
  Routes, beide kostenpflichtig.
- **Ausgehende Mail: Resend oder Postmark**, mit SPF, DKIM und DMARC auf der
  eigenen Domain. Freikontingente und Preise **unsicher, prüfen**. Wichtig: Es
  wird **nicht** in Katrins Namen von ihrer Adresse gesendet — das ginge nur mit
  SMTP-Zugang — sondern von der Produktdomain mit sichtbarer Signatur. Das ist
  technisch ehrlicher und rechtlich sauberer.
- **Google Calendar API.** Existiert, im normalen Kontingent kostenlos. Der
  Ereignis-Scope gilt als sensibel und erfordert ein Verifizierungsverfahren;
  nicht verifizierte Apps sind auf eine kleine Zahl von Testnutzern begrenzt —
  die genaue Zahl und das Verfahren **unsicher, müssen geprüft werden**. Für die
  ersten 100 Nutzer vermutlich ausreichend, und der Zeitpunkt, das zu klären, ist
  Woche 1, nicht Woche 6.
- **Anthropic API.** `claude-haiku-4-5` (1 $ / 5 $ pro Mio. Token ein/aus) für
  Extraktion und Klassifikation, `claude-sonnet-5` (3 $ / 15 $; Einführungspreis
  2 $ / 10 $ bis 31.08.2026) für Formulierung und Verhandlung. Prompt Caching für
  den System-Prompt.
- **PDF-Text: `unpdf` oder `pdfjs-dist`.** Kein OCR — gescannte Dokumente werden
  abgelehnt statt geraten.
- **Zeitsteuerung: GitHub Actions Schedule** (kostenlos, ausreichend granular)
  statt Vercel Cron, dessen Limits im günstigen Tarif **unsicher** sind.

Erfundene Endpunkte oder Funktionsnamen stehen hier nicht.

### 7. Die riskanteste Annahme

Die Annahme lautet nicht, dass es technisch geht. Sie lautet: **Menschen
akzeptieren, dass ein Assistent in ihrem Auftrag einen Dritten anschreibt, den
sie beruflich behalten müssen.** Wenn die Antwort nein ist, ist alles ab
Abschnitt 3 wertlos, unabhängig von Qualität.

Experiment, 7 Tage, keine Zeile Code: Ich richte eine Weiterleitungsadresse ein,
die in meinem eigenen Postfach landet, und gewinne zehn Selbstständige aus
Heilberufen. Ich sage ihnen wahrheitsgemäß, dass zunächst ein Mensch die
Abstimmung übernimmt. Sie leiten Terminmails weiter, ich erledige sie von Hand
innerhalb von 30 Minuten. Kriterien vorher festgelegt: Mindestens 6 von 10 leiten
innerhalb der Woche dreimal oder öfter weiter, und höchstens 1 von 10 berichtet
eine negative Reaktion des Empfängers. Wird das verfehlt, wird nichts gebaut.

### 8. Das Gegenargument

Der stärkste Grund, es zu lassen: **Die Sechs-Wochen-Grenze und die Haftung
schneiden genau den Teil weg, der den Wert trägt.**

Was übrig bleibt, formuliert Mails und wartet auf einen Klick. Das ist ein
langsamerer Mailclient. Der Sprung von „Entwurf mit Klick" zu „erledigt es
wirklich" ist nicht der letzte Feinschliff, sondern die eigentliche Aufgabe — und
sie ist durch Unumkehrbarkeit und Haftung blockiert, nicht durch fehlende
Entwicklungszeit.

Und der Vorteil aus Abschnitt 1 erodiert genau dann, wenn das Produkt
funktioniert. Die höhere Risikotoleranz existiert, weil niemand hinschaut. Der
erste ernsthafte Fehler bei 500 Nutzern — ein verfallener Anspruch, eine falsch
zugesagte Behandlung — erzeugt in einer Person dieselbe Vorsicht, die die Großen
bereits institutionalisiert haben. Man baut also ein Produkt, dessen
Existenzberechtigung sich mit seinem Erfolg auflöst, gegen Wettbewerber, die
schon dort sind, wo man in achtzehn Monaten landen wird. Und Modellanbieter
selbst wandern die Wertschöpfungskette abwärts: Was heute Produkt ist, ist
übermorgen eine Funktion in einem Assistenten, den der Nutzer ohnehin geöffnet
hat.

Das ist kein Strohmann. Ich halte es für richtig und für nicht entscheidend —
weil das Ziel keine Firma sein muss, die zehn Jahre hält, sondern eine, die die
Frist von Katrin rettet und dafür bezahlt wird, solange das Fenster offen ist.
Deshalb Teil 2.

---

## TEIL 2

### 9. Oberfläche

**Der eine Bildschirm: eine Liste laufender Vorgänge.** Kein Chat, kein
Posteingang, kein Dashboard.

Jede Zeile ist ein Vorgang, in einem Satz in Alltagssprache, gefolgt von seinem
Zustand:

> **Termin mit Frau Berger (Mutter von Jonas)** — Warte auf Antwort seit 2 Tagen
> · nächste Erinnerung morgen 9:00
>
> **Verordnung Dr. Kaufmann** — Frist 18. August · im Kalender
>
> **Termin mit Pflegedienst Lindenhof** — 3 Vorschläge fertig · *[Senden]*

Ein Element ist visuell dominant: die Zeilen, die auf den Nutzer warten, stehen
oben und tragen den einen Knopf. Vor dem Senden zeigt ein Klick den vollständigen
Wortlaut. Nichts geht raus, was nicht vorher genau so lesbar war.

Bewusst weggelassen: Chateingabe, Postfachansicht, Einstellungen,
Onboarding-Tour, Statistiken, Suche, Ordner, Tags, alles Blaue. Ein
Fußzeilen-Link „Was ist bisher passiert" führt zum Protokoll.

Zwei weitere Ansichten, beide unselbstständig:

- **Vorgangsdetail** — der vollständige Mailverlauf, der aktuelle Entwurf,
  editierbar, und der Regelknopf („künftig automatisch an diese Adresse
  senden"). Ohne den Hauptbildschirm sinnlos, mit ihm unverzichtbar: hier findet
  Vertrauensbildung statt.
- **Verbindungen** — Weiterleitungsadresse zum Kopieren, Kalenderstatus,
  Kündigung. Existiert nur, weil OAuth und die Adresse einen Ort brauchen.

### 10. Geld

**Wer zahlt und ab wann.** Der Nutzer. Kostenlos sind die ersten fünf
abgeschlossenen Vorgänge — nicht 14 Tage, sondern fünf Ergebnisse. Ein Zeitlimit
misst, wie beschäftigt jemand war; ein Ergebnislimit misst, ob das Produkt
gearbeitet hat. Die Bezahlaufforderung erscheint genau in dem Moment, in dem der
sechste Vorgang abgeschlossen wäre — also im Moment des nachweisbaren Nutzens,
nicht davor.

**9 € pro Monat**, unbegrenzte Vorgänge, monatlich kündbar. Kein Jahresrabatt:
Ich will monatlich erfahren, ob es noch trägt.

**KI-Kosten pro aktivem Nutzer und Monat** (alle Mengen als Annahme
gekennzeichnet, Preise aus der aktuellen Anthropic-Preisliste):

Annahme: 20 Vorgänge pro Monat, pro Vorgang 3 Extraktions-/Klassifikationsläufe
und 2 Formulierungsläufe.

| Position | Modell | Menge pro Vorgang | Preis | Kosten |
|---|---|---|---|---|
| Extraktion, Klassifikation | `claude-haiku-4-5` | 3 × (3.000 ein / 300 aus) | 1 $ / 5 $ pro Mio. | 0,014 $ |
| Formulierung, Verhandlung | `claude-sonnet-5` | 2 × (4.000 ein / 500 aus) | 3 $ / 15 $ pro Mio. | 0,039 $ |
| **Summe pro Vorgang** | | | | **≈ 0,053 $** |
| **× 20 Vorgänge** | | | | **≈ 1,06 $** |

Dazu variabel: Mailversand ca. 0,10 $, Datenbank und Speicher ca. 0,10 $.
**Variable Kosten ≈ 1,30 $ pro aktivem Nutzer und Monat.** Prompt Caching für den
System-Prompt drückt das um geschätzt 20–30 %, weil der stabile Anteil des
Eingabekontexts zu Cache-Lesepreisen abgerechnet wird.

Fixkosten: Hosting ca. 20 $, Mailversand-Grundgebühr ca. 15 $, Domain
vernachlässigbar — **ca. 35 $ pro Monat**, bei 100 zahlenden Nutzern 0,35 $ pro
Kopf.

**Gesamt ≈ 1,65 $ pro Nutzer und Monat gegen 9 € Erlös.** Nach Zahlungsgebühren
(ca. 0,50 €) bleiben rund 7 € Deckungsbeitrag, Rohmarge über 75 %. Ein Vielnutzer
mit 100 Vorgängen im Monat kostet ca. 5,80 $ und ist bei 9 € immer noch
profitabel — deshalb ist die Flatrate vertretbar und braucht kein
Kontingentsystem.

**Die Rechnung geht auf.** Sie geht nicht auf bei 100 Nutzern insgesamt: 700 €
Monatserlös sind kein Einkommen. Der Break-even zu einem bescheidenen
Vollzeitgehalt liegt bei rund 400–500 zahlenden Nutzern. Das ist die eigentliche
offene Frage, nicht die Marge.

### 11. Konkurrenz

**ChatGPT mit Connectors.** Kann alles, was mein Entwurf kann, plus Gmail- und
Kalenderanbindung, die bereits gebaut, geprüft und freigegeben ist — ohne dass
ich je eine OAuth-Verifizierung durchlaufen muss. Bessere Modelle, bessere
Zusammenfassungen, bessere Fehlertoleranz beim Lesen unstrukturierter Mails. Und
die Marke: Wer OpenAI seinen Kalender gibt, tut das ohne nachzudenken; wer mir
meinen gibt, denkt nach.

**Google mit Gemini in Workspace.** Braucht keinen Berechtigungsdialog, weil das
Postfach und der Kalender ihm gehören. Kein Ratenlimit, kein Kontingent, kein
Verifizierungsverfahren, keine variablen API-Kosten pro Nutzer. Sieht den
vollständigen Kontext, den ich per Weiterleitung mühsam nachbaue — inklusive
aller Mails, die der Nutzer mir nie schicken würde.

**Reclaim.ai.** Löst Terminlogik seit Jahren produktiv: Konflikterkennung,
Puffer, Prioritäten, wiederkehrende Muster, Zeitzonen, Mehrfachkalender. Jeden
dieser Sonderfälle habe ich in Woche 3 noch nicht gesehen und werde ihn in Woche
6 falsch machen. Zusätzlich Teamfunktionen und eine gewachsene
Integrationslandschaft.

### 12. Erste 100 Nutzer

Nicht online zuerst. Die ersten zwanzig hole ich physisch: **Heilmittelerbringer
in einer Stadt.** Kassel hat mehrere Dutzend Ergo-, Logo- und
Physiotherapiepraxen ohne Rezeption; sie stehen in den Therapeutenverzeichnissen
der Krankenkassen, mit Adresse und Mailadresse. Ich gehe hin, zwischen 12 und 14
Uhr, wenn die Behandlungspause ist.

Die nächsten achtzig über drei Kanäle, in dieser Reihenfolge: **Fachverbände auf
Landesebene** (DVE, dbl — Newsletter und Mitgliederbereiche, die tatsächlich
gelesen werden), **die Facebook-Gruppen selbstständiger Therapeutinnen**, die es
pro Berufsgruppe gibt und in denen Praxisorganisation das Dauerthema ist, und
**die Hersteller von Praxissoftware**, die ich nicht ersetze — deren Nutzerforen
sind voll von Menschen mit exakt diesem Problem.

Die erste Nachricht, per Mail an eine Praxis:

> Betreff: Kurze Frage zu Ihren Terminabsprachen
>
> Guten Tag Frau [Name],
>
> ich baue etwas für Praxen ohne Rezeption und suche zehn Leute, die mir sagen,
> ob es Unsinn ist.
>
> Die konkrete Frage: Wenn eine Mutter Ihnen schreibt, dass sie den
> Donnerstagstermin verschieben muss — wie oft schreiben Sie hin und her, bis ein
> neuer Termin steht, und wann am Tag machen Sie das?
>
> Wenn Ihre Antwort „drei- bis viermal, abends nach acht" ist, hätte ich einen
> Vorschlag: Sie leiten solche Mails an eine Adresse weiter, und ich erledige die
> Abstimmung — in den ersten Wochen von Hand, damit ich sehe, wo es hakt.
> Kostenlos, keine Verpflichtung, jederzeit Schluss. Ich brauche keinen Zugang zu
> Ihrem Postfach; Sie leiten weiter, was Sie weiterleiten wollen.
>
> Zwei Sätze Antwort genügen, auch „kein Bedarf".
>
> [Name], Kassel

Kein Produktname, keine Landingpage, kein Link. Eine Frage, deren Antwort ich
brauche, und ein Angebot, das ich am selben Tag einlösen kann.

### 13. Reihenfolge

**Ende Woche 1 fertig:** Das Wizard-of-Oz-Experiment aus Abschnitt 7 läuft oder
ist bereits ausgewertet. Domain registriert, Cloudflare Email Routing
eingerichtet, eine Weiterleitungsadresse pro Testnutzer, alles landet in meinem
Postfach. Der Google-Cloud-Antrag für die OAuth-Verifizierung des
Kalender-Scopes ist eingereicht — er hat die längste Durchlaufzeit von allem und
darf nicht am Ende stehen. Code, der nicht in Woche 1 existiert: alles außer dem
Mail-Empfangs-Worker.

**Ende Woche 6 fertig:** Ein Nutzer registriert sich mit Google, verbindet seinen
Kalender, bekommt seine Weiterleitungsadresse, leitet eine Terminmail weiter und
sieht binnen Minuten drei Terminvorschläge zum Senden. Nach Zusage des Empfängers
steht der Termin im Kalender. Funktionen A und B laufen, C läuft, wenn A und B
stabil sind — sonst nicht. Die 60-Sekunden-Haltezeit, das Protokoll und die
Kündigung existieren. Bezahlung läuft über Stripe Checkout nach fünf
abgeschlossenen Vorgängen.

Was nach Woche 6 kommt, weiß ich nicht, und jede Zahl, die ich dazu schriebe,
wäre erfunden.
