# HALT — Mobile App (MVP)

React Native (Expo Router + TypeScript). Das MVP baut das *richtige* Produkt aus der Strategie:
**nicht** einen Chatbot, sondern den **Geld-Trigger + Eskalations-Anruf** an eine Vertrauensperson.

> Ausgelöst von der Kontobewegung, nicht vom Zweifel des Opfers. Entschieden von einem Menschen, der ihn liebt.

## Was drin ist

**Vollständiger Ablauf, lauffähig mit Mock-Daten:**

1. **Onboarding für Angehörige** — Wen schützt du? → Wer wird gewarnt (Alarm-Kreis)? → Konto verbinden.
2. **Aktivitäts-Feed** — alle Kontobewegungen, verdächtige farblich markiert.
3. **Warnungen** — nur was der Motor als „Alarm" einstuft.
4. **Warnungs-Detail** — *warum* HALT gewarnt hat, in Klartext, plus „Anrufen" / „Ich kümmere mich" / „Alles ok". Der Mensch entscheidet, nie die App.
5. **Nachricht prüfen** — Offline-Heuristik für verdächtige SMS/WhatsApp (der erlaubte Passiv-Kanal).

## Das Herzstück: die Regel-Engine

`src/lib/ruleEngine.ts` ist das eigentliche Produkt. Sie lernt aus dem eigenen Verhalten der Person
eine Baseline und bewertet jede Bewegung dagegen. Regeln:

| Regel | Wofür |
|---|---|
| `high_risk_category` | Krypto, Edelmetalle, Geschenkkarten, Bargeld-Transfer — irreversible Cash-out-Wege |
| `new_payee` | völlig neuer Empfänger, gewichtet nach Höhe |
| `unusual_amount` | über dem 1,5-fachen der bisher höchsten Zahlung |
| `foreign_country` | untypisches Zielland |
| `velocity` | mehrere neue Empfänger in kurzer Zeit (Muster „unter Anleitung") |
| `cash_spike` | ungewöhnlich viel Bargeld in kurzer Zeit |

Der Motor sagt **nie** „das ist Betrug". Er entscheidet nur eine Sache: **ob ein Mensch geweckt wird.**

### Tests (ohne Installation lauffähig)

```bash
npm test          # node --experimental-strip-types --test __tests__/*.test.ts
```

13 Tests, decken Baseline, alle Regeln und die Nachrichten-Heuristik ab. Läuft mit purem Node 22 —
keine Jest-, keine Build-Abhängigkeit.

## Starten (echte App)

```bash
npm install
npm start          # Expo Dev-Server → QR-Code scannen (Expo Go) oder i/a für Simulator
```

## Was gestubbt ist (und wo die echten Kanäle andocken)

Diese drei brauchen Lizenzen/Zugangsdaten und sind bewusst als **markierte Integrationspunkte** gebaut:

| Datei | Stub | Produktion |
|---|---|---|
| `src/lib/mockBank.ts` | Mock-Umsätze | Lizenzierter PSD2-Anbieter (Tink / finAPI / GoCardless). HALT hält **keine** eigene Banklizenz. |
| `src/lib/escalation.ts` → `placeEscalationCall` | `console.log` | Twilio Programmable Voice, serverseitig (Token nie in der App). |
| `src/lib/escalation.ts` → `sendPush` | `console.log` | Expo Notifications → APNs/FCM. |

Die App-Logik drumherum (entscheiden → benachrichtigen → protokollieren) ist echt — nur die zwei
ausgehenden Leitungen sind Platzhalter.

## Architektur — bewusst für 100 Nutzer, nicht für Millionen

- **Expo Router** (dateibasiertes Routing) · **Zustand** für State · keine Persistenz-Ceremony.
- Engine ist rein & serverfähig — dieselbe Datei läuft später in einer Backend-Function, die die
  PSD2-Umsätze im Hintergrund pollt (dort gehört der Trigger produktiv hin, nicht ins Handy).

## Struktur

```
app/                     Expo-Router-Screens
  index.tsx              Willkommen
  onboarding/            Person → Alarm-Kreis → Konto verbinden
  (tabs)/                Aktivität · Warnungen · Einstellungen
  alert/[id].tsx         Warnungs-Detail (Mensch entscheidet)
  check.tsx              Nachricht prüfen
src/
  lib/ruleEngine.ts      ← das Produkt
  lib/messageCheck.ts    Offline-Nachrichten-Heuristik
  lib/mockBank.ts        PSD2-Stub
  lib/escalation.ts      Twilio/Push-Stubs
  store/useStore.ts      App-State + Ablauf-Orchestrierung
  components/ui.tsx       UI-Primitive
  theme.ts               Marken-Tokens (synchron zur Landingpage)
__tests__/               Engine- & Heuristik-Tests
```
