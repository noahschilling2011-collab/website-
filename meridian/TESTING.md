# Meridian selbst testen

Kein Docker, keine Datenbank nötig. Du brauchst nur **Node.js 20+** und **npm**.
Alle neuen Funktionen (Konto, 2FA, Assistent, Live-Teilen, Design) laufen In-Memory.

## 1. Code holen

```bash
git clone <REPO-URL>
cd website-
git checkout claude/ai-maps-navigation-system-1uiml9
cd meridian
```

> Falls du das Repo schon lokal hast: `git fetch && git checkout claude/ai-maps-navigation-system-1uiml9 && git pull`

## 2. Starten (ein Befehl)

```bash
npm install        # einmalig
npm run dev        # startet Gateway (:8090) + Web-App (:5173) zusammen
```

Dann im Browser öffnen: **http://localhost:5173**

`npm run dev` setzt automatisch öffentliche Dev-Datenquellen, damit **Suche und
Routing sofort mit echten Daten** funktionieren (Photon + Valhalla, Fair-Use, nur
zum Testen). Ohne Internet fällt alles auf Demo-Daten zurück — die App startet
trotzdem.

## 3. Was du ausprobieren kannst

### Karte & Navigation
- [ ] **Suche**: oben „Start" und „Ziel" eingeben (z. B. *Berlin* → *München*)
- [ ] Alternativ **📍** klicken und Punkt direkt auf der Karte wählen
- [ ] Verkehrsmittel (Auto/Rad/Fuß/ÖPNV) + Präferenz (Schnellste/Angenehmste/Eco/Landschaft)
- [ ] **Route berechnen** → Empfehlung, ETA, Wegbeschreibung, Wetter
- [ ] Oben rechts: **Satellit**, **3D** (Neigung + Gebäude), **Street View** (Klick auf Karte)*
- [ ] **🎨 Design**: Vorlagen (Nacht/Retro/…) oder eigene Regler — Karte ändert sich live

### KI-Assistent (unten links 🎙)
Tippen oder per Mikrofon sprechen (Chrome/Edge):
- [ ] „Bring mich **ohne Autobahn** nach Köln" → plant Route, meidet Autobahn
- [ ] „Finde den **günstigsten Supermarkt auf dem Weg**"
- [ ] „Zeig mir die **Satellitenansicht in 3D**" → schaltet die Ansicht um
- [ ] „Plane einen **Tagesausflug**" (erst Start + Ziel setzen)

### Konto & Sicherheit (oben „Anmelden")
- [ ] **Registrieren** mit E-Mail + Passwort (min. 8 Zeichen)
- [ ] Tab **Sicherheit** → **2FA einrichten**: Secret in eine Authenticator-App
      (z. B. Google Authenticator) eintragen, 6-stelligen Code bestätigen → Backup-Codes
- [ ] Tab **Geräte**: angemeldete Sitzungen sehen / beenden
- [ ] Tab **Datenschutz**: Berechtigungen schalten, **Daten exportieren**, Konto löschen
- [ ] Abmelden und wieder anmelden — mit aktiver 2FA wird der Code verlangt

### Freunde & Live-Standort (oben rechts 👥 Teilen)
- [ ] **Live-Standort teilen** einschalten → du bekommst einen **Link** (kopieren)
- [ ] Link in einem zweiten Browser/Tab öffnen → dein Standort ist dort sichtbar
- [ ] Freund per E-Mail einladen (zweites Konto anlegen zum Ausprobieren)

\* Street View braucht einen kostenlosen **Mapillary-Token** (sonst Hinweis statt Bild):
in `apps/web/.env` `VITE_MAPILLARY_TOKEN=…` setzen — Token unter
mapillary.com/dashboard/developers. Karte/3D/Satellit funktionieren ohne Token.

## 4. Tests & Checks (optional)

```bash
npm test           # 25 Backend-Tests (Krypto, Login-Sperre, 2FA, Refresh, Live-Sharing …)
npm run typecheck  # Gateway-Typen
```

## 5. Häufige Fragen

- **Suche findet nur wenige Orte?** Dann ist keine Internet-Verbindung zum Dev-Geocoder
  da → Demo-Fallback. Mit Internet liefert Photon echte weltweite Treffer.
- **Port belegt?** `PORT=8091 npm run dev` (Web-Proxy zeigt auf 8090 — bei Änderung
  auch `apps/web/vite.config.ts` anpassen).
- **Mikrofon geht nicht?** Web Speech API gibt es in Chrome/Edge; in Firefox tippen.
- **Eigene Karten-/Routing-Server** statt öffentlicher Dev-Instanzen: Werte in
  `services/gateway/.env` setzen (siehe `.env.example` und `docs/DATA_SOURCES.md`).
