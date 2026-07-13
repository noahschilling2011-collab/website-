# Sicherheit & Datenschutz

Meridian behandelt Standort als **besonders schützenswertes** Datum. Leitlinie:
*so wenig wie möglich erheben, so lokal wie möglich verarbeiten.*

## 1. Datenschutz-Grundsätze (DSGVO-konform)
- **On-Device-first:** Standort, Suchverlauf, häufige Orte werden bevorzugt lokal
  gehalten. Server erhält nur, was eine Funktion zwingend braucht.
- **Datenminimierung:** Routing-Requests brauchen kein Konto; anonyme Nutzung möglich.
- **Kurze Aufbewahrung:** Roh-Standortsonden werden nach Map-Matching sofort
  aggregiert und verworfen; keine dauerhaften Bewegungsprofile.
- **Zweckbindung & Opt-in:** Verkehrsbeitrag (Floating-Car-Data), Analytics und
  Personalisierung sind einzeln opt-in.
- **Kein Datenverkauf.** Keine Werbe-IDs. Klare Datenexport-/Löschfunktion
  (Recht auf Auskunft & Vergessenwerden).

## 2. Anonymisierung von Verkehrsdaten
- Sonden ohne Konto-Bezug, zufällige rotierende Sitzungs-IDs.
- **Trip-Chopping:** Fahrten werden fragmentiert; Start/Ende (Zuhause/Arbeit)
  abgeschnitten (Fuzzing der ersten/letzten X Meter).
- **Differential Privacy** bei Aggregation von Geschwindigkeiten je Kante.
- k-Anonymität: Kanten-Aggregate erst ab k Sonden veröffentlicht.

## 3. Transport & Speicherung
- TLS 1.3 überall; HSTS; Zertifikats-Pinning in mobilen Apps.
- Ruhende Daten verschlüsselt (Storage-Level). Sensible Konto-Felder
  (Heim/Arbeit, Sammlungen) **E2E**-verschlüsselt: Client-Key aus Nutzer-Passwort
  (Argon2id) abgeleitet; Server speichert nur Chiffrat.
- Secrets über Vault/KMS, nie im Repo. `.env` nur lokal.

## 4. Authentifizierung & Autorisierung
- JWT Access (15 min) + rotierendes Refresh-Token (httpOnly, sicher gespeichert);
  Refresh-Reuse-Detection.
- Passwörter: Argon2id. Optional Passkeys/WebAuthn (Roadmap v3).
- **Row-Level-Security** in PostgreSQL: Zugriff nur auf eigene Zeilen.
- Least-Privilege-Service-Accounts pro Microservice.

## 5. API-Härtung
- Schema-Validierung aller Eingaben (Fastify JSON-Schema/Zod).
- Rate-Limiting (Redis Token-Bucket) je IP/Konto; strengere Limits für teure
  Endpunkte (Routing/KI).
- CORS-Allowlist, strenge CSP im Web-Client, `helmet`-Header.
- Circuit-Breaker & Timeouts zu Upstreams; keine Fehler-Details nach außen.

## 6. Missbrauch & Bot-Schutz
- Anomalie-Erkennung auf Request-Mustern; Proof-of-Work/Captcha bei Verdacht.
- Signierte Client-Attestation für kostenintensive Endpunkte.

## 7. Compliance & Governance
- DSGVO (EU), plus regionale Anpassungen. DPA/AVV mit Sub-Prozessoren.
- Datenschutz-Folgenabschätzung (DSFA) für Standortverarbeitung.
- Audit-Logs (wer/was/wann) für Admin-Zugriffe, unveränderlich gespeichert.
- Regelmäßige Pentests, Dependency-Scanning (SCA), SBOM, Secret-Scanning in CI.

## 8. Sichere Entwicklung
- Branch-Protection, Code-Review, signierte Commits.
- CI: SAST + `npm audit`/`osv-scanner` + Container-Scan.
- Keine Geheimnisse in Logs; PII-Redaction in Telemetrie.
