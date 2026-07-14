# HALT — Sicherheit & Datenschutz

HALT verarbeitet mit das Sensibelste, was es gibt: die Kontobewegungen und das
Umfeld einer schutzbedürftigen Person. Dieses Dokument sagt ehrlich, was heute
umgesetzt ist — und was ein Backend braucht, bevor echte Menschen echte Daten
eingeben. Kein Sicherheits-Theater.

## Grundhaltung

- **Datensparsamkeit:** HALT bekommt nur **Lesezugriff** auf Umsätze (PSD2/AIS). Keine
  Überweisungsrechte, kein Zugriff auf das Geld, kein Mitlesen von Nachrichten.
- **Der Client ist nie die Autorität.** Passwörter, Bank-Token und Twilio-Zugänge
  gehören auf den Server. Die App hält nur ein undurchsichtiges Session-Token.
- **Ein Fehlalarm ist billig, ein Datenleck ist teuer.** Im Zweifel weniger speichern.

## Was in dieser App umgesetzt & getestet ist

| Kontrolle | Umsetzung | Datei |
|---|---|---|
| App-Sperre (PIN) | 6-stelliger PIN, salted-SHA-256, Hash im Hardware-Keychain | `src/lib/appLock.ts`, `src/lib/hash.ts` |
| Biometrie | Face ID / Fingerabdruck als Entsperrung | `src/lib/appLock.ts` |
| Brute-Force-Schutz | Eskalierende Sperre, Wipe nach 10 Fehlversuchen | `src/lib/lockPolicy.ts` |
| Sichere Ablage von Secrets | iOS Keychain / Android Keystore, `WHEN_UNLOCKED_THIS_DEVICE_ONLY` | `src/lib/secureStore.ts` |
| Auto-Sperre | Sperrt, sobald die App in den Hintergrund geht | `app/_layout.tsx` |
| Privatsphäre-Overlay | Verdeckt Kontodaten im App-Switcher-Snapshot | `app/_layout.tsx` |
| Eingabevalidierung | E-Mail / Passwort / PIN / Telefon, Control-Char-Sanitizing | `src/lib/validation.ts` |
| Timing-sicherer Vergleich | `constantTimeEqual` für Hash-Prüfung | `src/lib/hash.ts` |
| Konstante Antwortzeit beim Login | Decoy-Hash, auch wenn das Konto nicht existiert | `src/lib/authService.ts` |
| Vollständiger Wipe | Löscht Konto, PIN und alle Secrets (Recht auf Löschung) | `src/store/useSession.ts` |

Alles davon ist durch **26 Tests** abgedeckt (`npm test`) und typgeprüft (`npm run typecheck`).

## Bewusste Grenzen — was ein Backend braucht (nicht faken)

- **Account-Passwörter serverseitig hashen.** Die lokale Demo-Auth (`authService.ts`)
  ist nur, damit der Flow offline läuft. Produktiv: **Supabase Auth** — Passwörter mit
  **Argon2id/bcrypt** auf dem Server, verifizierte E-Mail, echte JWT-Sessions.
  Integrationspunkt ist im File auskommentiert vorbereitet.
- **PSD2-Zugriff** läuft über einen lizenzierten TPP (Tink/finAPI). Das Consent-Token
  liegt **serverseitig**, nie in der App.
- **Twilio-Eskalationsanruf** wird von einem Backend-Endpunkt ausgelöst; der Twilio-Token
  ist ein Server-Secret.
- **At-Rest-Verschlüsselung großer Daten:** Umsätze werden im MVP **gar nicht** persistiert
  (nur im Speicher). Für Offline-Persistenz: symmetrischer Schlüssel im Keychain +
  verschlüsselter Blob (z. B. `react-native-quick-crypto` / SQLCipher) — `expo-crypto`
  allein kann das nicht und wird dafür bewusst **nicht** vorgetäuscht.
- **Row-Level-Security (RLS):** Auf dem Server muss jede Zeile an die `user_id` gebunden
  sein, sodass niemand fremde Kontodaten abfragen kann — die wichtigste Server-Kontrolle.
- **Transport:** Nur HTTPS/TLS; für die Bank-/Anruf-Backends Certificate Pinning erwägen.
- **Rate-Limiting & Audit-Logs** für Login und Eskalation gehören aufs Backend.

## DSGVO-Kurzcheck

- **Rechtsgrundlage:** ausdrückliche, **widerrufbare** Einwilligung des Kontoinhabers
  (Art. 6 Abs. 1 a). Widerruf muss den Datenfluss sofort stoppen.
- **Art.-9-Risiko:** „fällt auf Betrug rein" kann als Proxy für kognitiven Abbau in
  Gesundheitsdaten kippen — deshalb keine Diagnosen, keine Scores über die Person
  speichern, nur konkrete Transaktions-Signale.
- **Betroffenenrechte:** Auskunft, Löschung (im MVP: „Konto & alle Daten löschen"),
  Datenexport — serverseitig auszubauen.
- **Auftragsverarbeiter:** TPP, Twilio, Push-Dienst, Hosting — je ein AV-Vertrag (Art. 28).
- **Standort:** Verarbeitung/Hosting in der EU (z. B. Frankfurt).
- **Träger:** Verantwortlicher i. S. d. DSGVO muss eine **geschäftsfähige Person/Firma**
  sein. Bis dahin braucht das Projekt einen erwachsenen Träger.

## Verantwortungsvolle Meldung von Schwachstellen

Sicherheitslücken bitte **nicht** öffentlich als Issue posten, sondern privat melden
(Kontakt: siehe Landingpage). Wir antworten und beheben, bevor Details veröffentlicht werden.
