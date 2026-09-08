# ASTRA_REPORT — JARVIS / Mehmet

Stand: 08.09.2026. Arbeitsbranch: `astra/integration`.

## Ergebnis und Abnahmegrenze

Der credential-freie Integrationsschritt ist implementiert und lokal geprüft.
**Keine Gesamtabnahme, keine Phase auf FERTIG gesetzt.** Echte Modellantworten,
CDSE-Bilder, aktuelle externe Daten und die noch offenen FIX-11-Arbeiten sind
damit ausdrücklich nicht abgenommen. Die vollständige CI dieses Branches steht
zum Zeitpunkt dieses Berichtstands noch aus; der lokale Lauf umfasst 1.436
bestandene Tests und 110 ausdrücklich ausgeschlossene Browserfälle.

## Ausgangspunkt und Zusammenarbeit

- Repository: `noahschilling2011-collab/website-`.
- [PR #11](https://github.com/noahschilling2011-collab/website-/pull/11): offen,
  Draft, nicht gemergt. Analysierter Head:
  `8063688fc53c9c394ce93752f574093915b5bd01` auf
  `claude/jarvis-ai-os-1u7ied`.
- Der Standardbranch `claude/enterprise-ai-productivity-app-et6zq7` ist nicht
  der aktuelle JARVIS-Stand. Deshalb basiert Astra auf dem PR-Head.
- Der PR-Text nennt noch FIX-09 und 1.408 Tests; der tatsächliche Head enthält
  bereits FIX-10 und FIX-11 Welle 1 und die Baseline sammelt 1.510 Tests.
- [CI des Ausgangsstands](https://github.com/noahschilling2011-collab/website-/actions/runs/34038393675)
  war erfolgreich: JARVIS, Datenpipeline und App. Das ist ein historischer
  Nachweis des Ausgangscodes, kein Nachweis dieser Änderungen.
- Eigener isolierter Checkout, eigener Branch. Kein Push auf Claudes Branch,
  kein Merge von PR #11, keine Änderung seiner PR-Beschreibung oder Kommentare.
  Keine fremden Arbeitsbaumänderungen ersetzt. Kein weiterer Agent gestartet.
- Claudes Startup/Sicherungs-/Migrationslogik, Erinnerungsformular,
  READ-Grenze für Zeitpläne und UI-Code bleiben erhalten.

## Analysierte Architektur

Die Repository-Wurzel ist eine Werkstatt pro Branch. `blitzerwarner/` enthält
ein älteres TypeScript-/Expo-Projekt samt eigener Datenpipeline; es wurde
inventarisiert, aber nicht verändert. JARVIS liegt vollständig in `jarvis/`.

Geprüft wurden Root- und JARVIS-README, CLAUDE.md, STATUS.md, Verträge,
Entscheidungen, FIX-/Integrationsdokumentation, PR/Issue-Stand, vollständige
Datei- und Python-Modulstruktur, Environment-Verbraucher, Testaufbau, CI,
Containerkonfiguration sowie die relevanten Ein- und Ausgabepfade der Module.
Die produktive Python-Struktur am Ausgangsstand umfasst 48 Core-, 10 API-
und 10 Skriptmodule; hinzu kommen `main.py`, die HTML-Seiten und lokale Assets.
Dies ist eine Architektur-/Integrationsprüfung, kein zeilenweises Audit der
vendorten Three.js-Dateien oder der älteren Blitzerwarner-Anwendung.

| Bereich | Datenfluss und Verantwortung |
|---|---|
| Start | `main.py` → Konfiguration → `datenbank_start` → FastAPI-Lifespan. SQLite quick_check, Sicherung, Schema/Migration; danach Provider und Werkzeugkonfiguration. |
| Oberfläche | `index.html`, `weltlage.html`, `static/globus.js`; Vanilla JS und lokales Three.js. Token im Header, SSE über fetch statt Token in URL. |
| Gespräch | `/api/chat` → Verlauf + Gedächtniskontext → Tool-Schleife → Dispatcher → SQLite-Nachrichten/Tool-/LLM-Protokolle. |
| Aufträge | `/api/tasks` → TaskRegistry → Planner → Runner → Agenten → dieselbe Tool-Schleife/Dispatcher. Budgets, Abbruch, Bestätigungen und SSE. |
| Erinnerungen | `/api/zeitplaene` → zentrale Zeitplanlogik. Erinnerungen schreiben direkt eine Nachricht samt Herkunft und Ereignis: kein Planner/LLM. |
| Automatisierte Aufträge | Zeitplan → derselbe `starte_task`; harte READ-Decke und gemeinsame rollierende Tagesbudgets. Kein Nachholen verpasster Läufe. |
| Dateien | Allowlist-Wurzeln + Sperrliste + aufgelöste Pfade/Symlinkprüfung; Lesen/Suchen, keine Computersteuerung. |
| Kalender | Lokale ICS oder konfiguriertes Abo → Parser → lokales Datumsfenster; Herkunft/Cachezustand, kein Terminschreiben. |
| Memory/Obsidian | Ohne Vault SQLite/FTS5; mit Vault sind Markdown-Dateien die Wahrheit und SQLite ein erneuerbarer Index. Gemeinsamer `gedaechtnis`-Leseweg. |
| Wissen | Kiwix, Wikimedia und Wikidata mit gemeinsamem Lookup-Cache, Herkunft und Snapshot; keine Vektor-DB. |
| Wetter | Open-Meteo-Geocoding/-Forecast über httpx, Standardort aus Settings, begrenzter Cache. Werkzeug selbst braucht kein LLM. |
| Weltlage | Länderroute/Cache → normaler Runner → eigener Agent → Quellen-/Bildprüfung; keine ersatzweise erfundenen Meldungen. |
| Satelliten | CDSE-Katalog, getrennte authentifizierte Bildverarbeitung; TLE/Skyfield für Bahnen; NDVI-Auswertung existiert, Rasterbeschaffung fehlt. |
| Betrieb | SQLite/WAL, Sicherungen/Migrationen, Ereignisbus; Docker-Healthcheck prüft nur Erreichbarkeit, nicht vollständige Modulbereitschaft. |

Die Registry hält prozessweite Werkzeuginstanzen. Deshalb bleibt die vorhandene
Ein-Prozess-Vorgabe relevant; dies ist keine Mehrmandanten- oder Multiworker-Abnahme.
Computer-/Desktopsteuerung ist laut CLAUDE.md und decisions.md dauerhaft Non-Goal.
Der aktuelle Auftrag wurde nicht als Freigabe zum Einbau eines neuen Computer-Agenten ausgelegt.

## Vorgenommene Änderungen

1. **Kein automatischer Fake-Erfolg.** Ein leeres `LLM_PROVIDER` erzeugt einen
   kontrollierten Konfigurationsfehler. Die vorhandene `UnavailableProvider`-
   Integration hält die App erreichbar. Health: `degraded`; Chat: HTTP 503;
   Modellaufträge: `failed`, ohne erfolgreichen Modellverbrauch. Der
   ausdrücklich gewählte Modus `LLM_PROVIDER=fake` bleibt für Tests/Demos erhalten.
2. **Einrichtungsbefehl ohne Tokenausgabe.**
   `python -m scripts.konfiguration --init` legt nur eine neue `.env` an,
   mit `secrets.token_urlsafe(32)`, exklusivem Anlegen und POSIX-Modus 0600.
   Vorhandene Dateien und Symlink-Ziele werden nicht überschrieben.
3. **Gemeinsame Moduldiagnose.** `core/konfig_pruefung.py` versorgt die CLI und
   das additive Feld `health.integrationen`. Sie unterscheidet fehlend,
   ungültig, teilweise vorhanden, konfiguriert, Demo und deaktiviert.
   `konfiguriert` behauptet ausdrücklich keine externe Erreichbarkeit.
   Keine Zugangsdaten, Kalenderadressen, Ortswerte oder absoluten Dateipfade
   in diesem Modulbericht; keine externen Aufrufe bei der Diagnose.
4. **Token-Logging geschlossen.** Automatisch erzeugte Zugangstoken erscheinen
   nicht mehr im Startlog. Öffentlicher Vorlagen-Platzhalter und Steuerzeichen
   werden abgelehnt; Validierungsfehler wiederholen keine Tokenwerte.
5. **Katalog und Bilder integriert.** Der bereits öffentliche CDSE-Katalog
   bleibt ohne Credentials nutzbar. Die bestehende Zugangsprüfung steht am
   Bildabruf; Token-/Process-API werden ohne Zugangsdaten nicht aufgerufen.
   Metadaten und fehlender Bildzugang werden getrennt weitergereicht, auch
   bis zur Ortsansicht. Kein Ersatzbild, keine erfundenen Rasterdaten.
6. **Klarere Fehlerpfade.** Die Weltlage meldet einen nicht eingerichteten
   Provider als 503, statt ihn als kaputtes Modell-JSON darzustellen.
   Bereits vorhandene Cache-Treffer bleiben lesbar. Die Ortsansicht behält
   Ortsdaten, erklärt fehlendes LLM/CDSE und hinterlässt bei fehlgeschlagener
   Textgenerierung keinen fälschlich laufenden Task.
7. **Reproduzierbare Tests.** Gemeinsame Test-Settings wählen den Fake jetzt
   ausdrücklich. Der Smoke-Test erzwingt ohne `--real` den Fake und leere
   externe Credentials/Quellen, auch bei entsprechender Shell-Konfiguration.
   Ein vorher echter DNS-Aufruf in der Offline-Suite ist durch eine lokale
   DNS-Testantwort ersetzt; die eigentliche Adressprüfung bleibt aktiv.
8. README und `.env.example` sind für den neuen Einrichtungs-/Fehlerpfad
   aktualisiert; die veraltete LOCAL-Angabe in der Vorlage lautet nun READ.

## Tests und tatsächliche Ergebnisse

Ausgeführt mit Python 3.12.13; Abhängigkeiten aus `requirements.txt` in einer
isolierten Umgebung. `pip check`: **No broken requirements found**.
Für die SOCKS-Proxy-Umgebung wurde `socksio` nur in der lokalen Testumgebung
installiert, nicht als neue Produktabhängigkeit aufgenommen.

| Prüfung | Ergebnis / Aussagegrenze |
|---|---|
| Unveränderte Baseline: `python -m pytest -p no:randomly -W ignore` | 1.510 gesammelt, 1.371 bestanden, 139 Fehler, 0 übersprungen. |
| Baseline-Fehleranalyse | 110 Browserfälle: Playwright-Treiber/Chromium lokal nicht ausführbar/verfügbar. 28 Proxy-/fehlende-socksio-Folgefehler. Ein echter externer DNS-Aufruf im Offline-Test. |
| Neue LLM-/Tokenregressionen vor Fix | 14 von 14 rot; fehlender LLM-Status, Fake-Erfolge und Token-Log konkret reproduziert. |
| Erster LLM-/Token-Fix einschließlich vorhandener API-/LLM-Tests | 100 bestanden. |
| Konfiguration/API/Satelliten-Zwischenprüfungen | 137 bzw. 149 bestanden; relevante Regressionen nach den Änderungen erneut ausgeführt. |
| Katalog-/Ortsregression vor Integration | 3 von 3 rot; nach Fix zusammen mit vorhandenen Satelliten-/Starttests grün. |
| Abschließender lokaler Systemlauf | **1.436 bestanden, 110 Browserfälle ausdrücklich per Test-ID ausgeschlossen**, 69,06 s. Keine ausgeführte Prüfung fehlgeschlagen. |
| README-/Konfigurations-/Routenwächter und neue E2E-Prüfungen | 85 bestanden. |
| `python -m scripts.smoke` | **Rauchtest bestanden**, expliziter Fake; kein Nachweis echter Modellqualität. |
| `python -m scripts.konfiguration --init` | In diesem Checkout erfolgreich; Token direkt gespeichert, Diagnose ohne Secret-Werte. `.env` wird nachweislich ignoriert. |
| `git diff --check` | Bestanden. |
| Chromium-Installation/lokaler Browserlauf | Kein abgeschlossener Browsernachweis. Download hier nicht verfügbar; keine Umgehung der Netzwerkgrenze. |
| Echter Open-Meteo-Aufruf, Testort Berlin | Versucht, aber kein verwertbares Tool-Ergebnis wegen abgebrochener Netzwerkfreigabe. **Nicht live verifiziert**; daraus wird keine Wetterantwort abgeleitet. |
| Eigene vollständige GitHub-CI | Noch ausstehend; wird nach dem Sichern des Branches geprüft. |

Die ausgeschlossenen Browser-Test-IDs stammen ausschließlich aus den 110
Playwright-Ausstattungsfehlern der unveränderten Baseline. Produktprüfungen
wurden nicht entfernt oder pauschal auf „skip“ gesetzt. Die vorhandene CI
führt weiterhin **die vollständige Suite** einschließlich Chromium aus.

### End-to-End-Zustände ohne LLM

Alle sechs angefragten Formulierungen wurden sowohl durch `/api/chat` als
auch über den bisherigen UI-Auftragspfad `/api/tasks` geschickt:

| Anfrage | Nachgewiesen |
|---|---|
| „Was steht heute an?“ | Klarer LLM-Blocker statt „keine Termine“; separat echter lokaler ICS-Prüftermin durch das konfigurierte Kalenderwerkzeug. |
| „Wie wird das Wetter?“ | Klarer LLM-Blocker im Gespräch; ohne Ortsangabe expliziter `JARVIS_ORT`-Hinweis am Werkzeug. Vorhandene Wettertests prüfen Mock-/Cachepfade. |
| „Erinnere mich morgen an X.“ | Kein falsches „gespeichert“ im Gespräch. Über das vorhandene Erinnerungsformular/API: morgen anlegen, echten Schleifendurchlauf mit kontrollierter Uhrzeit zweimal prüfen → genau eine Zustellung, Herkunft erhalten, null LLM-Aufrufe. |
| „Suche Datei X.“ | Kein erfundener Treffer im Gespräch. Separat echte lokale Testdatei über konfigurierte Allowlist gefunden; `.env`-Lesen abgelehnt. |
| „Was weißt du über X?“ | Kein erfundenes Wissen. Separat Memory-API → gemeinsames SQLite-Gedächtnis → `recall` findet den tatsächlich geschriebenen Fakt. |
| „Zeig mir die aktuelle Weltlage.“ | Kein Fake-Erfolg; Länderroute meldet fehlendes LLM als 503. Keine erfundenen Nachrichten. |

Diese Nachweise belegen lokale Verarbeitung, gemeinsame Konfiguration und
korrektes Scheitern. Sie belegen **nicht** die freie Sprachinterpretation
eines realen Modells oder externe Datenqualität.

## Environment-Inventur

Alle Settings-Felder und Aliase wurden gegen ihre Verbraucher und die Vorlage
gehalten. Die bestehenden Wächter prüfen unbekannte Vorlagenvariablen und
ungenutzte Settings-Felder weiterhin. Secret-Werte wurden weder inventarisiert
noch in den Bericht übernommen.

| Variablen / Aliase | Verbraucher / Befund |
|---|---|
| `JARVIS_TOKEN` | API-Zugang; neuer sicherer Init-/Diagnosepfad. In diesem Checkout erzeugt; keine Aussage über Noahs Windows-PC. |
| `JARVIS_HOST`, `JARVIS_PORT`, `JARVIS_ERLAUBTE_HOSTS` | Start/TrustedHostMiddleware/Container. Loopback bleibt Vorgabe; Wildcard-/Netzfreigaberisiko bleibt ausdrücklich bestehen. |
| `JARVIS_ORT` | Wetter/Morgenlage; persönlicher Ort nicht geraten, bleibt hier leer. |
| `DATEI_WURZELN`, `FILE_ROOTS`; `DATEI_MAX_KB` | Dateiwerkzeuge; Format/Pfadbestand geprüft, Testfreigaben nur in temporären Testordnern. Produktivfreigabe bleibt leer. |
| `KALENDER_QUELLE`, `CALENDAR_SOURCE` | ICS-Werkzeug; lokale Test-ICS geprüft. Kein privates Kalender-Abo eingerichtet. |
| `LLM_PROVIDER`, `LLM_API_KEY`, `LLM_MODEL` | Providerbau; ohne Auswahl kontrolliert nicht eingerichtet, kein automatischer Fake. |
| `LLM_PRICE_IN_PER_MTOK`, `LLM_PRICE_OUT_PER_MTOK` | Kostenrechnung; fehlende Preise bleiben unbekannt, kein selbst erfundener Preis/Wechselkurs. |
| `LLM_TIMEOUT_SECONDS`, `LLM_MAX_RETRIES`, `LLM_MAX_TOKENS` | LLM-Client; vorhandene Code-Defaults, Budgets nicht erhöht. |
| `SEARCH_API_KEY` | Brave-Websuche/Weltlage; nicht gesetzt, nicht aktiviert. |
| `WIKI_KIWIX_BASIS`, `KIWIX_URL`; `WIKI_ZIM` | Lokale Kiwix-Integration; braucht vorhandenen Dienst/ZIM, nicht automatisch installiert. |
| `WIKI_KONTAKT`, `WIKI_API_TOKEN` | Wikimedia/Wikidata/Ortssuche; Kontakt bzw. optionaler Token nicht erfunden. |
| `WISSEN_CACHE_STUNDEN` | Alle drei Wissenswerkzeuge; vorhandener gemeinsamer TTL-Pfad. |
| `VAULT_PFAD`, `VAULT_PATH` | Gemeinsames Gedächtnis/Vault-Index; kein persönlicher Vault gewählt. |
| `CDSE_CLIENT_ID`, `CDSE_CLIENT_SECRET` | Nur authentifizierter Bildpfad; leere/halb konfigurierte Werte werden getrennt gemeldet. |
| `JARVIS_DB_PATH`, `DB_PATH` | SQLite, Sicherungen, Migrationen; relative Pfade projektbezogen. Tests nutzen eigene Datenbanken. |
| `JARVIS_OUTBOX_PATH`, `OUTBOX_PATH` | Lokale Outbox; `send_email` ist kein echter Mailversand. |
| `MAX_PERMISSION` | API/Runner/Dispatcher; existierende Stufenprüfung und zusätzliche READ-Decke für Zeitpläne unverändert. |
| `BUDGET_MAX_STEPS`, `BUDGET_MAX_DEPTH`, `BUDGET_MAX_TOOL_CALLS`, `BUDGET_MAX_TOKENS`, `BUDGET_MAX_SECONDS`, `BUDGET_MAX_COST_EUR` | Gemeinsames TaskBudget; keine Erhöhungen. |
| `ZEITPLAN_MAX_LAEUFE_24H`, `ZEITPLAN_MAX_TOKEN_24H`, `ZEITPLAN_MAX_ERINNERUNGEN_24H`, `ZEITPLAN_TAKT_S` | Gemeinsame Zeitplansteuerung; separate Erinnerungskontingente, 0 schaltet automatische Zustellung aus. |
| `ASSISTENT_NAME`, `SYSTEM_PROMPT` | Name/Prompts; bestehende Namensvalidierung bleibt. |
| `HISTORY_LIMIT`, `SSE_HEARTBEAT_SECONDS` | Gesprächsfenster/Ereignisstrom; unverändert. |

Zusätzlich geprüft: Test-/Betriebsvariablen `JARVIS_CHROMIUM`,
`PLAYWRIGHT_BROWSERS_PATH`, Plattformzeitzone und Proxy-Umgebung. Sie sind keine
Zugangsdaten für JARVIS und keine automatisch übernommenen Produkt-Settings.

## Behobene und offene Blocker

**Behoben:** sicherer lokaler Token-Init; Tokenausgabe im Startlog;
unbemerkter automatischer Fake-Erfolg; fehlender gemeinsamer Konfigurationsbericht;
Blockade des öffentlichen Katalogs durch die Bild-Credential-Prüfung;
verlorener CDSE-/LLM-Hinweis in der Ortsansicht; DNS-Abhängigkeit einer Offline-Prüfung.

**Weiter offen / benötigte Eingaben:**

- Reales LLM: Anbieter, gültiger Key und dokumentierte Modell-ID; ein
  kostenpflichtiger Aufruf braucht ausdrückliche Freigabe. Hier kein echter
  LLM-Aufruf, keine neue Brücke zur Codex-/Claude-Sitzung.
- CDSE-Bilder: Client-ID und Secret. Öffentliche Metadaten ersetzen kein Bild.
- NDVI: neben Credentials fehlt die Rasterbeschaffung/Decodierung. Ein Key
  allein erfüllt diese Funktion nicht.
- Aktuelle Weltlage: reales LLM, Suchzugang und erreichbare Quellen. Keine
  kostenlose Ersatzquelle oder neue Finanzdatenintegration erfunden.
- Persönlicher Standardort und konkrete erlaubte Ordner. Optional ICS/Vault/ZIM/
  Wikimedia-Kontakt; diese Werte werden vom Besitzer festgelegt.
- FIX-06 §8 MÄRKTE: **ursprüngliches Briefing weiterhin nicht gefunden**.
  Suche im aktuellen Baum, in `git log --all`/Dateihistorie, Issues und PRs
  ergibt die Überschrift und die bestehenden Blockerhinweise, keine Spezifikation.
  PR #11 hat keine Diskussionskommentare; Issue-Suche liefert keine passende
  Spezifikation. Keine Aktien-, Krypto-, Forex- oder Indexfunktion implementiert.

## Risiken und Integrationsbedarf für Claudes nächste Welle

Die folgenden Befunde stehen bereits konkret in `docs/FIX-11.md` oder sind
im aktuellen Code sichtbar. Sie wurden nicht parallel als zweiter großer
Backend-/UI-Umbau begonnen:

1. **FIX-11 §7 — Gesprächspfad:** `index.html` sendet weiter grundsätzlich an
   `/api/tasks`. Der Taskpfad hat nicht den Gesprächsverlauf/Gedächtnisblock
   von `/api/chat`. Das ist die wichtigste noch offene Zusammenführung für
   Rückfragen wie „und morgen?“. Zuständigkeit abstimmen, dann vorhandenen
   spezifizierten Umschalter/Chatpfad integrieren.
2. **FIX-11 §4 — Task-Lebenszyklus:** rohe unerwartete Ausnahmetexte im
   generischen Task-Fangzweig, ungeschützter finaler DB-Schreibpfad und
   Wiederanlauf getippter Tasks. Risiko: sensible Fehlertexte und hängende
   Registry-/Taskzustände. Die kleine Ortskorrektur löst nicht diesen ganzen Block.
3. **FIX-11 §§5–6 — fremde Inhalte/URLs:** durchgängige Datenrahmung und
   Begrenzung von `fetch_url` auf belegte/genannte URLs stehen noch aus.
   Bestehende Rechte-, Host- und Netzprüfungen wurden nicht entfernt.
4. Bestehende SSRF-DNS-TOCTOU-Grenze in `core/tools/search.py`; keine
   behauptete vollständige Isolation des Rechners. Host-Wildcards und
   Nicht-Loopback-Bindung bleiben Betreiberentscheidungen mit Warnung.
5. Kalender-Wiederholungen sind nicht voll aufgelöst; lokale Rechnerzeitzone
   bleibt maßgeblich. Eine leere Trefferliste ist deshalb keine pauschale
   Zusage, dass der ganze Tag frei ist.
6. Sicherungen liegen auf derselben Platte und erfassen weder sämtliche
   Bilder/Outbox noch automatisch den externen Obsidian-Vault. Kein Schutz
   vor Plattenverlust nachgewiesen. Docker-Build und reale Windows-/Audio-/
   Benachrichtigungsbedienung wurden hier nicht ausgeführt.
7. Große Teile von `requirements.txt` sind nur nach unten begrenzt. Die
   erfolgreiche Testumgebung ist keine allgemeine Supply-Chain-Abnahme.

## Empfohlener nächster Schritt

Zuerst den kleinen Integrationsdiff mit Claude abgleichen und die vollständige
CI dieses Branches prüfen. Dann Claudes konkret spezifizierte FIX-11-Welle
§§4–7 integrieren: Diff lesen, Architektur/Sicherheit prüfen, relevante Tests
und vollständige Regression ausführen. Erst danach einen ausdrücklich
freigegebenen realen Modelllauf und manuelle Browser-/Windows-Abnahme durchführen.
Das MÄRKTE-Briefing und fehlende Zugangsdaten blockieren jeweils nur ihre
eigenen Funktionen, nicht die weitere lokale Integrationsarbeit.
