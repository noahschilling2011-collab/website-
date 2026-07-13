# Konto, Anmeldung & Sicherheit

Status wie in [`FEATURES.md`](FEATURES.md): ✅ live · 🟡 heuristik/teilweise · 🔵 design.
Der Auth-Service läuft **ohne externe Abhängigkeiten** (Node-Bordmittel: scrypt,
HMAC-JWT, TOTP) und **ohne Datenbank** (In-Memory-Store, swap-fähig gegen
[`db/migrations/003_accounts.sql`](../db/migrations/003_accounts.sql)).

## Konto & Anmeldung
| Funktion | Reife | Umsetzung |
| --- | --- | --- |
| E-Mail + Passwort | ✅ | `POST /v1/auth/register` · `/login`; scrypt-Hash (Prod: Argon2id) |
| Google / Apple / Microsoft | 🟡 | `GET /v1/auth/oauth/:provider/start` + `/callback` (OIDC Auth-Code); aktiv sobald Client-ID/Secret gesetzt |
| Zwei-Faktor (2FA) | ✅ | TOTP (RFC 6238): `/2fa/enroll` → `/2fa/enable`; Login verlangt Code; Backup-Codes |
| Passkeys (passwortlos) | 🟡 | WebAuthn-Options live (`/passkey/register-options`, `/login-options`); Verifikation via `@simplewebauthn/server` (s. u.) |
| Geräteverwaltung | ✅ | `GET /v1/auth/sessions` listet alle aktiven Sitzungen (Gerät, IP, zuletzt aktiv) |
| Sitzungen aus der Ferne beenden | ✅ | `DELETE /v1/auth/sessions/:id` · `POST /v1/auth/logout-all` |
| Profilbild & Profil | ✅ | `PATCH /v1/me` (Name, Avatar-Farbe); Foto-Upload → Object Storage (Prod) |
| Cloud-Synchronisierung | ✅ | Sync-Service (v1) + konto-gebundene Favoriten/Routen |
| Familienkonten | 🔵 | Datenmodell `families`/`family_members`; Endpunkte Roadmap |
| Gastmodus | ✅ | `POST /v1/auth/guest` — flüchtiges Konto ohne Anmeldung |

## Sicherheit
| Funktion | Reife | Umsetzung |
| --- | --- | --- |
| E2E-Verschlüsselung sensibler Daten | ✅ | Client AES-256-GCM (WebCrypto, Schlüssel aus Passwort via PBKDF2); Server speichert nur Chiffrat: `PUT/GET /v1/vault/:key` |
| Verschlüsselte Speicherung | ✅/🔵 | Vault = Chiffrat; ruhende DB-Verschlüsselung auf Storage-Ebene (Prod) |
| Biometrische Anmeldung (Face/Touch ID) | 🟡 | Gleicher WebAuthn-Flow wie Passkeys (Plattform-Authenticator) |
| Login-Warnungen bei neuem Gerät | ✅ | Neues Gerät/IP → `new_device_login`-Event + `newDevice`-Flag in der Login-Antwort |
| Erkennung verdächtiger Anmeldungen | ✅/🟡 | Neu-Gerät-Heuristik + Refresh-Reuse-Detection; erweiterbar (Geo-Velocity) |
| Auto-Sperre nach Fehlversuchen | ✅ | Nach 5 Fehlversuchen 15 Min. Sperre (`account_locked`) |
| Datenschutz-Dashboard | ✅ | `GET/PUT /v1/account/permissions` |
| Berechtigungen einzeln (Standort/Kamera/Mikro) | ✅ | Feingranulare Toggles im Permissions-Objekt |
| Backup & Wiederherstellung | ✅/🔵 | `GET /v1/account/export` (DSGVO-Export); Restore via Import (Roadmap) |
| Sicherheitsprotokoll aller Aktivitäten | ✅ | `GET /v1/account/security-log` (unveränderliches Event-Log) |
| Recht auf Vergessenwerden | ✅ | `DELETE /v1/account` |

## Token-Modell
- **Access-Token:** JWT HS256, 15 Min., `typ:"access"`, enthält `sub` (User) + `sid` (Session).
- **Refresh-Token:** Zufalls-Token, 30 Tage, **rotierend**. Bei jedem Refresh wird ein
  neues ausgegeben; das alte gilt als „verbraucht".
- **Reuse-Detection:** Wird ein bereits rotiertes Refresh-Token erneut vorgelegt,
  gilt die Session als kompromittiert → **sofortige Sperre der Session-Familie** +
  `refresh_reuse`-Sicherheitsevent.

## OAuth einrichten (Beispiel Google)
1. In der Google Cloud Console OAuth-Client (Web) anlegen.
2. Redirect-URI: `${APP_URL}/v1/auth/oauth/google/callback`.
3. `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` in `.env` setzen.
4. Client ruft `GET /v1/auth/oauth/google/start` → leitet auf `url` weiter →
   Callback tauscht Code gegen Token, holt Userinfo, legt Konto an/verknüpft →
   Redirect zur App mit Tokens im URL-Fragment.
Microsoft analog (`MS_CLIENT_ID`…). **Apple** benötigt zusätzlich ein signiertes
JWT-Client-Secret (Team-ID, Key-ID, .p8-Key) — Struktur in `oauth.ts` vorgesehen.

## Passkeys / Biometrie vervollständigen
Die Options-Endpunkte (Challenge, RP, Nutzer, Algorithmen) sind live. Für die
kryptografische Prüfung:
```bash
npm i @simplewebauthn/server -w @meridian/gateway
```
Dann in `routes/passkey.ts` die beiden `*-verify`-Handler mit
`verifyRegistrationResponse` / `verifyAuthenticationResponse` implementieren und
Credential (public_key, sign_count) in `webauthn_credentials` speichern. Face ID /
Touch ID / Windows Hello sind Plattform-Authenticatoren desselben Flows — keine
zusätzliche Integration nötig.

## Datenschutz-Prinzipien
Siehe [`SECURITY.md`](SECURITY.md): On-Device-first, Datenminimierung, k-Anonymität
& Differential Privacy für Verkehrsdaten, kein Datenverkauf. Der E2E-Vault stellt
sicher, dass sensible Orte (Zuhause/Arbeit) den Server **nur verschlüsselt** erreichen.
