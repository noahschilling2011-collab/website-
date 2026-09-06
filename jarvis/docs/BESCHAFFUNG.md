# Was Noah besorgen muss — und was nichts kostet

> Stand 29.08.2026. Jede Zahl hier stammt von einer Seite, die wirklich
> abgerufen wurde, oder aus einem Befehl, der wirklich lief. Was nicht
> belegt ist, steht unter **UNSICHER** am Ende — nicht mittendrin.

**Kurz:** genau **ein** Konto, **0 €**, keine Kreditkarte, keine Firma,
keine Wartezeit. Für die Märkte-Ansicht kommen je nach Umfang null bis zwei
weitere Gratis-Schlüssel dazu.

---

## 1. Satellit — was wirklich blockiert ist

Von den drei Satelliten-Werkzeugen hängt **nur eines** an einem Schlüssel:

| Werkzeug | Braucht | Status |
|---|---|---|
| `satellite_passes` — Überflüge über einen Ort | nichts. CelesTrak ist offen | **läuft** |
| `satellite_search` — Szenen finden | **nichts mehr** (siehe unten) | **läuft** |
| `satellite_search` — Bild rendern | `CDSE_CLIENT_ID` + `CDSE_CLIENT_SECRET` | **blockiert** |
| `satellite_compare` — Vegetationsverlust in Hektar | dieselben zwei Werte + Bauarbeit | blockiert |

> Die Szenensuche brauchte bis zum 29.08.2026 einen Token — **fälschlich.**
> Der OData-Katalog ist offen; der Token machte aus einer funktionierenden
> Suche eine 403. Gemessen: ohne Header `HTTP 200`, mit falschem Bearer
> `HTTP 403`. Header entfernt, Suche läuft jetzt ohne Zugangsdaten.

## 2. Das CDSE-Konto — Schritt für Schritt

### 2.1 Registrieren

1. `https://dataspace.copernicus.eu/` → oben rechts aufs **Avatar-Logo**
2. Rechts **REGISTER**
3. Formular: *First name, Last name, Email, Password, Confirm password,
   Country, Purpose of use, Type of user, Thematic activity*
4. Passwort: **mind. 12 Zeichen**, je 1 Sonderzeichen, Groß-, Kleinbuchstabe
   und Ziffer
5. Sinnvolle Auswahl: Country **Germany**, Type of user **„Natural persons —
   personal interest"**, Purpose of use **„Natural persons for non
   commercial purposes"**
6. ⚠️ Die Checkbox **„I am also interested in accessing Copernicus
   Contributing Missions data" NICHT** setzen. Nur die löst eine
   menschliche Freigabe aus („within 1 business day"). Für Sentinel
   überflüssig.
7. **REGISTER** → Mail → **„Verify email address"**. Danach ist es fertig,
   es gibt keine weitere Freischaltung.

Im Formular gibt es **kein Feld** für Kreditkarte, IBAN, Rechnungsadresse
oder Zahlungsmittel.

### 2.2 Den OAuth-Client anlegen — hier führt die Seite in die Irre

**Es gibt zwei Dashboards.** „OAuth clients" steckt im **Sentinel Hub
Dashboard**, nicht im Copernicus Browser. Und der Link **„Dashboard" in der
Fußzeile** von `dataspace.copernicus.eu` führt **nicht** dorthin — er zeigt
auf `/copernicus-data-space-ecosystem-dashboard`, eine reine Infoseite
(nachgemessen: Seite geholt, `href` ausgelesen).

1. Eingeloggt aufrufen:
   `https://shapps.dataspace.copernicus.eu/dashboard/#/account/settings`
   *(oder: Maus aufs Profilsymbol → „Sentinel Hub")*
2. Reiter **„User Settings"** → Abschnitt **„OAuth clients"** → **„Create"**
3. Name, z. B. `jarvis`
4. **„Expiry date"** wählen — oder **„Never expire"** mit Risikobestätigung
5. ⚠️ Häkchen **„single-page application (SPA)" NICHT** setzen. JARVIS ist
   ein Server, kein Browser-Frontend.
6. **„Create"** → ID und Secret erscheinen **genau einmal**. Doku wörtlich:
   *„Ensure to copy the secret value and paste it securely as it won't be
   retrievable once the pop-up closes!"*

```
CDSE_CLIENT_ID=<Client ID>
CDSE_CLIENT_SECRET=<Client Secret>
```

Ein Feld **„Client grant type"** beschreibt die CDSE-Doku **nicht**.
Anleitungen, die es nennen, stammen vom alten Dashboard auf
`sentinel-hub.com`. Siehst du es doch: **Client Credentials**.

### 2.3 Was es kostet: nichts

Die vollständigen Terms and Conditions (~15.100 Zeichen) enthalten **null
Vorkommen** von *cost, payment, credit card, charge, price, fee, invoice,
pay*. Sie sagen: *„The access and use of Copernicus Sentinel data is
available on a free, full and open basis."* Die Quotas-Seite nennt es
„free tier resources".

Geld käme erst ins Spiel, wenn du **über** das Kontingent hinauswillst — und
dann nicht bei CDSE, sondern über einen separaten Vertrag mit dem
Drittanbieter CREODIAS. **Preise dafür sind nicht belegt und werden hier
nicht genannt.**

### 2.4 Dein Kontingent

Quotas-Seite, Zeile „Copernicus General Users", `Last-Modified` 26.08.2026:

| Weg | Grenze |
|---|---|
| **Sentinel Hub APIs** (unser Weg) | **10.000 Requests/Monat**, **10.000 Processing Units/Monat**, je 300/Minute |
| S3 / OData / STAC | 12 TB je 30 Tage, 4 Verbindungen, 20 MB/s je Verbindung |
| Direct HTTP access to COGs | 50.000 Requests/Monat — **Nachbarspalte, nicht unser Weg** |

> In unserer `.env.example` standen **50.000** — die Zahl aus der falschen
> Spalte. Korrigiert.

Überschreiten des Transferlimits sperrt nicht, es drosselt (1 MB/s, 1
Verbindung). Reset am Monatsersten, nichts sammelt sich an. PU werden **nur
bei Erfolg (2XX)** abgezogen.

## 3. NDVI — `satellite_compare` braucht **keinen** zweiten Zugang

Derselbe Client reicht. Kein zweites Konto, kein zweiter Schlüssel, keine
Zusatzfreischaltung.

**Der Weg:** Process API mit einem Evalscript auf B04/B08 und
`sampleType: FLOAT32`, Ausgabe als GeoTIFF (`format.type = "image/tiff"`).
Die Pixelwerte *sind* dann die NDVI-Zahlen. Die Doku hat dafür ein
Beispiel unter der Überschrift *„Exact NDVI values using a floating point
GeoTIFF"*. Es gibt das Raster **nicht als JSON** — `application/json` ist
dort nur der Metadaten-Output.

**Halb so teuer:** dieselbe Seite zeigt *„NDVI values as INT16 raster"* —
NDVI × 10000 als Ganzzahl, Formatfaktor 1 statt 2.

**Was NICHT reicht:** die Statistical API (`/statistics/v1`). Die liefert
min/max/mean/stDev/Histogramm über das ganze Gebiet — aus einem Mittelwert
folgt nicht, *welche* Fläche sich verändert hat.

**Kosten, gerechnet aus den PU-Faktoren der Doku:**

| Gebiet bei 10 m | PU je Raster | PU je Vergleich | Vergleiche/Monat |
|---|---|---|---|
| 1 km × 1 km | ~0,051 | ~0,10 | sehr viele |
| 5 km × 5 km | ~1,27 | ~2,54 | grob 3.900 |

**Was in JARVIS noch fehlt** — die Auswertehälfte steht schon
(`core/satellite/analysis.py`: `ndvi()`, `vergleichbar()`,
`vergleiche_raster()` rechnet bereits Hektar):

1. Eine Client-Methode, die ein NDVI-Raster holt (analog `render()`, aber
   NDVI-Evalscript und `image/tiff`)
2. **GeoTIFF → `list[float]`** — die Schnittstelle, die
   `vergleiche_raster` schon erwartet
3. Beide Zeitpunkte identisch anfordern (gleiche bbox, gleiche
   width/height) — sonst wirft `vergleiche_raster` absichtlich
4. `effektive_aufloesung_m()` durchreichen, damit die Hektarzahl stimmt
5. Ein Monatszähler gegen 10.000/10.000 — bei zwei Rastern je Vergleich
   greift das PU-Limit zuerst

⚠️ **Punkt 2 ist eine Stack-Entscheidung.** Ein GeoTIFF zu lesen heißt
`rasterio` oder GDAL — oder `Pillow`, das seit heute ohnehin in
`requirements.txt` steht und 32-Bit-Float-TIFF im Modus `F` liest. Das
gehört geprüft, bevor eine schwere Abhängigkeit dazukommt.

## 4. Märkte (FIX-06 Abschnitt 8)

> ⚠️ **Der Auftragstext für Abschnitt 8 liegt nicht im Repo** — nur der Name
> in der Kopfzeile von `docs/FIX-06.md`. Welche Daten die Ansicht zeigen
> soll, ist damit unbekannt. Diese Liste ist die *Landschaft*, keine
> Auswahl.

### Empfehlung für ein privates Projekt in Deutschland

| Was | Nimm | Warum |
|---|---|---|
| **Währungen** | **EZB direkt** (oder `api.frankfurter.dev` als Wrapper) | Kein Konto, kein Key, keine Karte, amtliche Quelle. Ein Wert je Werktag ab ~16:00 CET — öfter pollen bringt nichts |
| **Deutsche Aktien** | **Deutsche Börse Delayed Data** | Der einzige Weg, der zugleich kostenlos, ohne Konto, ohne Karte **und** lizenzrechtlich ausdrücklich abgedeckt ist. Preis: 15 Min. Verzögerung, Dateiservice statt JSON-API |
| **US-Aktien** | **Finnhub** | 60 Calls/Minute, und einer von nur zwei Anbietern mit wörtlich belegtem „keine Kreditkarte" |
| **Krypto** | **CoinGecko Demo** | Ohne Karte belegt. „Powered by CoinGecko" ist echte Vertragspflicht, keine Höflichkeit |

### Ausdrücklich **nicht** nehmen

- **Twelve Data (Gratis)** — genau unser Fall ist ausgeschlossen: *„The data
  cannot be displayed to users … or used in production systems."* Anzeigen
  kostet 79 USD/Monat.
- **Yahoo / yfinance** — technisch der bequemste Weg zu DAX-Daten und der
  einzige geprüfte, dessen AGB die Nutzung dem Wortlaut nach **auch privat**
  nicht decken.
- **Marketstack** — 100 Anfragen *im Monat* trägt kein Dashboard.

### Drei Regeln, die aus den Lizenzen folgen

1. **JARVIS lokal lassen.** Die Lizenzlage ist bei allen Aktienanbietern
   dieselbe Grundform: privat ja, öffentlich nein. Sobald die Ansicht ins
   offene Netz geht, bei keinem mehr — außer bei den Zentralbankquellen.
2. **Cache-Retention setzen.** Deutscher Rechtspunkt: § 87b Abs. 1 Satz 2
   UrhG stellt die „wiederholte und systematische Vervielfältigung … von
   nach Art und Umfang unwesentlichen Teilen" der Nutzung eines wesentlichen
   Teils gleich, und § 87c Abs. 1 Nr. 1 UrhG nimmt elektronisch zugängliche
   Datenbanken von der Privatkopie aus. *„Ist ja nur privat"* ist im
   Datenbankrecht kein Freibrief. **Reiner Gesetzestext, keine
   Rechtsprechung geprüft, kein Rechtsrat.**
3. **Quellenzeile unter die Anzeige** („Quelle: EZB", „Quelle: Deutsche
   Börse, 15 Min. verzögert"). Bei rein privater Anzeige nicht zwingend —
   macht die Frage aber gegenstandslos.

> **Zur „15-Minuten-Pflicht":** die gilt nicht dir, sondern den
> Handelsplätzen. MiFIR (EU) Nr. 600/2014 Art. 13 Abs. 2 verpflichtet
> Handelsplätze, Daten *„free of charge 15 minutes after publication"*
> zugänglich zu machen. Deine Verzögerung ergibt sich daraus, welchen Feed
> du nimmst, nicht aus einer Vorschrift an dich.

---

## UNSICHER

Nichts davon kippt „kostenlos, keine Kreditkarte" — aber hier glaubst du
besser dem Bildschirm als diesem Text.

1. **Niemand hat ein Konto angelegt.** Der Ablauf nach dem REGISTER-Klick
   stammt aus der Doku, nicht aus eigener Durchführung. **Kein echter
   authentifizierter API-Aufruf ist je gelaufen.**
2. **Das OAuth-Formular hat niemand gesehen** — es liegt hinter dem Login.
   Heißt ein Feld bei dir anders: glaub dem Bildschirm.
3. **„OAuth clients gibt es nicht im Copernicus Browser"** — das Positive
   ist belegt (die Doku verlinkt auf shapps), die Verneinung nicht.
4. **Token-Lebensdauer widersprüchlich.** Quotas-Seite: 10 Minuten. Der
   Fließtext des Beginners Guide: „expire after an hour". Das abgedruckte
   Beispiel-Token: `exp - iat` = 600 s. Der Code liest deshalb `expires_in`
   aus der Antwort, statt eine Zahl zu glauben.
5. **NDVI als FLOAT32-TIFF ist aus der Doku belegt, nicht praktisch
   verifiziert.** Erst einen kleinen Testabruf machen, bevor jemand Code
   drumherum baut.
6. **Keine Preisseite der Marktanbieter trug ein Stand- oder
   Änderungsdatum.** Gratis-Stufen ändern sich; vor dem Bauen nachsehen.
7. **Alpha Vantage: kein wörtlicher Beleg für „keine Kreditkarte"** — das
   Formular fragt nur Rolle, Organisation, E-Mail, aber es steht nicht da.
   XETRA-Symbole (`MBG.DEX`) sind dokumentiert, die Abdeckung in der
   Gratis-Stufe ist **ungetestet**.
