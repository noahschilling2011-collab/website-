# HALT Backend — echtes Konto + echter Alarm auf dein Handy

Das ist die Server-Schicht, die HALT *echt* macht: sie liest (mit Einwilligung) echte
Kontoumsätze über PSD2, lässt dieselbe getestete Engine drüberlaufen, und ruft bei einem
Alarm **wirklich** deine Nummer an / schickt eine SMS — über Twilio.

> **Wichtig, ehrlich:** Zum Testen benutzt du deine **eigene** (verifizierte) Nummer und die
> **Sandbox-Bank** mit Test-Daten. Verbinde **nicht** das echte Konto eines Angehörigen, bis
> du dessen ausdrückliche Einwilligung + eine DSGVO-Rechtsgrundlage hast — und als Minderjähriger
> einen erwachsenen Träger (Verantwortlichen). Siehe `../app/SECURITY.md`.

## Alles in der App — ohne Terminal (empfohlen)

Das Backend **serviert die App selbst**: die veröffentlichte Backend-URL *ist* die ganze App.
Du machst nichts am Terminal — du klickst nur.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/noahschilling2011-collab/website-)

> Beim Render-Blueprint-Schritt den Branch **`claude/halt-fraud-strategy-kgq7g9`** auswählen
> (dort liegt die `render.yaml`).

1. **Ein-Klick deployen** (Render, gratis): Button oben, oder in Render **New → Blueprint →
   dieses Repo + Branch wählen** → Render liest `render.yaml` automatisch.
2. **Schlüssel eintragen** — im Render-Dashboard unter **Environment** (nicht in der App!):
   `ALERT_PHONE`, `TWILIO_*`, und (für die Bank) `GOCARDLESS_*`.
3. **App öffnen**: die Render-URL (z. B. `https://halt-backend.onrender.com`) **im Handy-Browser** öffnen.
   → In der App: **Einstellungen → Live → „Test-Alarm an mein Handy"** ruft dich echt an.
   → **Konto verbinden → „Echtes Konto verbinden (Live)"** startet die Bank-Sandbox.

Die geheimen Schlüssel liegen so **nur beim Hoster**, nie in der App — genau das ist die Sicherheit.

## Läuft sofort — ganz ohne Accounts (DRY_RUN)

```bash
cd halt/backend
npm install
npm test            # 8 Tests, Engine + Mapping + Alarm-Dedupe
npm run demo-scan   # fährt die Beispiel-Historie durch die Engine
```

Ohne Zugangsdaten läuft alles im **DRY_RUN**: die komplette Logik arbeitet, aber statt echt zu
senden, wird nur geloggt, *was* gesendet würde. So kannst du alles ausprobieren, bevor du dich
irgendwo anmeldest.

## Schritt 1 — Deine Nummer klingelt wirklich (Twilio, gratis)

1. Kostenlosen **Twilio-Trial** anlegen: <https://www.twilio.com/try-twilio>
2. Im Console **deine eigene Handynummer als „Verified Caller ID"** verifizieren
   (Trial-Accounts dürfen nur an verifizierte Nummern senden).
3. Eine (kostenlose Trial-) **Twilio-Telefonnummer** holen → das ist dein `TWILIO_FROM`.
4. `Account SID` und `Auth Token` aus dem Console kopieren.
5. `.env` anlegen und ausfüllen:
   ```bash
   cp .env.example .env
   # ALERT_PHONE = deine verifizierte Nummer (+49...)
   # TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM
   ```
6. **Klingeln lassen:**
   ```bash
   npm run test-alert
   ```
   → dein Handy bekommt jetzt echt eine SMS **und** einen Anruf.
   *(Twilio hängt bei Trials „Sent from your Twilio trial account" vor die SMS — normal.)*

Danach der volle Alarm-Weg mit der Beispiel-Betrugsmasche:
```bash
npm run demo-scan   # 3 Krypto-Alarme -> 3 SMS + 3 Anrufe an deine Nummer
```

## Schritt 2 — Echtes Konto anbinden (GoCardless, gratis, Sandbox)

1. **GoCardless Bank Account Data** Konto anlegen (früher „Nordigen"):
   <https://bankaccountdata.gocardless.com/> → unter **User Secrets** `secret_id` + `secret_key` erzeugen.
2. In `.env` eintragen: `GOCARDLESS_SECRET_ID`, `GOCARDLESS_SECRET_KEY`.
   `GOCARDLESS_INSTITUTION_ID` bleibt `SANDBOXFINANCE_SFIN0000` (Test-Bank mit Fake-Daten).
3. Server starten und Verbindung anstoßen:
   ```bash
   npm start
   curl -X POST localhost:8080/connect/start
   ```
   → du bekommst einen `link`. **Im Browser öffnen**, „einloggen" (bei der Sandbox darfst du
   *beliebige* Werte eingeben) und bestätigen.
4. Konten abfragen und prüfen:
   ```bash
   curl localhost:8080/connect/status/<requisitionId>     # liefert account-ids (Status "LN")
   curl -X POST localhost:8080/scan/<accountId>           # liest Umsätze -> Engine -> ggf. Alarm
   ```

Wenn die Engine in den Umsätzen etwas Verdächtiges findet, **klingelt dein Handy** — mit echten
(Sandbox-)Daten, über denselben Code, den du später auf eine echte Bank umstellst.

## Anmeldung mit Google (optional, gratis)

1. In der **Google Cloud Console** einen OAuth-Client (Typ „Web") anlegen.
2. Als „Authorized redirect URI" `<APP_URL>/auth/google/callback` eintragen
   (z. B. `https://halt-backend.onrender.com/auth/google/callback`).
3. `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` in `.env` / im Render-Dashboard setzen.
   → In der App erscheint automatisch „Weiter mit Google".

**Apple** funktioniert genauso, braucht aber ein **Apple-Developer-Konto (99 €/Jahr)** — der Code
ist als Gerüst vorbereitet (`APPLE_*`-Variablen), bleibt aber aus, bis du das Konto hast.

## Automatische Überwachung

Sobald GoCardless konfiguriert ist, prüft das Backend **von selbst** alle verbundenen Konten
(Standard: alle 6 Stunden, `MONITOR_INTERVAL_HOURS`) und eskaliert neue Alarme an die
**bestätigte** Vertrauensperson — auch wenn niemand die App öffnet. Doppelte Alarme für dieselbe
Bewegung gibt es nie (Dedupe pro Nutzer).

> Warum 6 Stunden? Die GoCardless-Gratis-Stufe erlaubt grob **4 Umsatz-Abfragen pro Konto pro
> Tag**. 6 h = exakt 4/Tag. Nicht niedriger stellen, sonst blockt die Bank-API.

Status siehst du in `GET /health` (`monitor`) und in der App unter **Einstellungen → Live**.

## Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/health` | Status; ob Twilio/GoCardless konfiguriert sind |
| POST | `/test-alert` | Test-SMS/-Anruf an `ALERT_PHONE` |
| POST | `/demo-scan` | Beispiel-Historie durch Engine + Alarm |
| POST | `/connect/start` | GoCardless-Requisition → Einwilligungs-Link |
| GET | `/connect/status/:id` | Requisition-Status + Konto-IDs |
| POST | `/scan/:accountId` | echte Umsätze lesen, bewerten, eskalieren |

## Wie es aufgebaut ist

```
src/
  engine.js          Risiko-Engine (Port der getesteten TS-Engine) — das Produkt
  gocardless.js      PSD2/Open-Banking-Client (Token → Requisition → Transaktionen)
  twilio.js          SMS + Anruf via REST (plain fetch), + DRY_RUN-Fallback
  mapTransactions.js Bank-Format → HALT-Transaktion (+ Kategorie-Heuristik)
  notify.js          bewerten → eskalieren → benachrichtigen (mit Dedupe)
  store.js           „schon gewarnt"-Speicher (Datei; später Postgres)
  config.js          liest .env; DRY_RUN wenn keine Zugangsdaten
  server.js          Express-Endpunkte
scripts/             test-alert, demo-scan
test/                8 Tests, laufen ohne Zugangsdaten
```

## Sicherheit

- Geheimnisse **nur** in `.env` (gitignored). Nie ins Repo, nie in einen Chat.
- Twilio-Token ist ein **Server**-Secret — kommt nie in die App.
- GoCardless: nur **Lesezugriff** auf Umsätze, Einwilligung widerrufbar.
- Rate-Limits von GoCardless beachten (Umsätze cachen, nicht dauerpollen).
