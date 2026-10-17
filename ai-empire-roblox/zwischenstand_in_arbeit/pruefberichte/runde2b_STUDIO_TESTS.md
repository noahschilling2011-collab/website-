# Round 2b - what only Roblox Studio can confirm / Was nur Roblox Studio bestätigen kann

Place: `out/verify2b/AIEmpire_r2b.rbxlx`. The headless mock has already tested the logic, money, cleanup and
geometry clearances (see `agents/verify2b/FIXES.md`). It cannot test anything below.
Start a **local server with 2 players** (Test → Clients and Servers → 2) unless a line says otherwise.

## English

**1. TextGenerator (phone AI chat)**
- [ ] Phone → chat with one of your own released models. You get a real TextGenerator reply in under 5 s, in the model's style. The "Demo reply (offline)" label shows only when the API is disabled.
- [ ] Spam about 20 messages from both players. Replies slow down or show the honest offline text, and the server log shows no errors (limit is ~100 requests per minute per server).

**2. Real physics / characters**
- [ ] Founder car ride HQ → City Airport. You are held under the car while it drives, then released at the kerb **standing**, not falling, stuck or flung. The same goes for the drop-offs at the limousine stand, the Helix tower and the Meridian Grand.
- [ ] Jet: you board at the airstair and land at the Port Meridian arrival spot. Two founders landing together get different spots and don't overlap.
- [ ] Walking companions (rep + engineer) follow you through doors and up stairs. They don't float or sink and don't walk through walls (ground ray at 2 Hz). They fade out at gate A1.
- [ ] Company cars and the limousine never hit kerbs, Founder Square props, ambient cars or walkers (CityLife has no leader logic for company cars yet, see drivers.md #7).

**3. Camera feel**
- [ ] The ride camera (car / "View" back seat / limo) is smooth, with no jitter at 60 FPS. When the ride ends, control comes back to the player camera.
- [ ] Jet cabin window-seat camera and shuttle "Window seat": no clipping through the hull, and the toasts and phone stay visible (jet DisplayOrder 14; shuttle: guests_jet.md #5 still open).
- [ ] Meeting room: the client team sits on the right chairs (two seat sets when both founders visit Helix), and the camera can see them.

**4. Mobile / touch (Device emulator: iPhone 14 landscape 844x390, plus one Android tablet)**
- [ ] The itinerary banner (Go / Not this time / Cancel trip / Fly home now / Call car now) folds by default. Every button is ≥ 44 pt and reacts on the first tap.
- [ ] The drivers' ride panel (Get in / Let me out / View) does not cover the HUD company card (itinerary.md #5 open), and the banner slides below it.
- [ ] The phone call sheet of the assistant opens over the HUD. Accept and decline work by tap. The calendar shows the trip items (pinned group still open, itinerary.md #9).
- [ ] The jet ride GUI on a phone: the window oval, flight info at the bottom and phone button all show, with no overlap.

**5. Performance on a real device**
- [ ] Mid-range phone, both founders travelling. While cars, limousines, the jet, the shuttle, terminal passengers (≤ 40) and hotel guests (≤ 12) are on screen, the client holds ≥ 30 FPS with memory < 1.2 GB.
- [ ] Server (Developer Console → Server Jobs): ItineraryService, DriverService and JetService each stay < 1 ms per heartbeat with 2 founders. Network receive stays < 50 KB/s per client during a trip.
- [ ] Imported ExecutiveLimo mesh (if added under ReplicatedStorage/Assets/Vehicles): it looks right, doors open on the kerb side, the interior is hidden beyond 150 studs, and there are no frame drops.

## Deutsch

**1. TextGenerator (KI-Chat im Handy)**
- [ ] Handy → Chat mit einem eigenen veröffentlichten Modell. Eine echte TextGenerator-Antwort kommt in unter 5 s, im Stil des Modells. Der Hinweis „Demo reply (offline)“ erscheint nur, wenn die API aus ist.
- [ ] Mit beiden Spielern etwa 20 Nachrichten schnell hintereinander senden. Die Antworten werden langsamer oder zeigen den ehrlichen Offline-Text, und im Server-Log stehen keine Fehler (Limit ca. 100 Anfragen pro Minute und Server).

**2. Echte Physik / Figuren**
- [ ] Fahrt mit dem Firmenwagen HQ → City Airport. Während der Fahrt wird man unter dem Auto festgehalten und danach am Bordstein **stehend** abgesetzt, ohne zu fallen, festzustecken oder weggeschleudert zu werden. Dasselbe gilt am Limousinenstand, am Helix-Turm und am Meridian Grand.
- [ ] Jet: Einsteigen an der Fluggasttreppe, Landung am Ankunftspunkt in Port Meridian. Landen beide Gründer gleichzeitig, bekommen sie verschiedene Plätze und überlappen sich nicht.
- [ ] Die mitlaufenden Kollegen (Rep + Engineer) folgen durch Türen und Treppen. Sie schweben und versinken nicht und laufen nicht durch Wände (Bodenstrahl mit 2 Hz). An Gate A1 blenden sie aus.
- [ ] Firmenwagen und Limousine streifen keine Bordsteine, keine Deko am Founder Square, keine Autos und keine Fußgänger der Stadt (CityLife kennt die Firmenwagen noch nicht als Vordermann, siehe drivers.md #7).

**3. Kameragefühl**
- [ ] Die Fahrkamera (Auto / Rückbank „View“ / Limousine) läuft weich, ohne Ruckeln bei 60 FPS. Nach der Fahrt hat man die normale Spielerkamera wieder.
- [ ] Fensterplatz-Kamera im Jet und „Window seat“ im Shuttle: Die Kamera schneidet nicht durch den Rumpf, und Toasts und Handy bleiben sichtbar (Jet DisplayOrder 14; Shuttle: guests_jet.md #5 noch offen).
- [ ] Besprechungsraum: Das Kundenteam sitzt auf den richtigen Stühlen (zwei Sitzgruppen, wenn beide Gründer bei Helix sind), und die Kamera sieht es.

**4. Mobil / Touch (Geräte-Emulator: iPhone 14 quer 844x390, dazu ein Android-Tablet)**
- [ ] Das Reise-Banner (Go / Not this time / Cancel trip / Fly home now / Call car now) ist anfangs eingeklappt. Jeder Knopf ist ≥ 44 pt groß und reagiert schon beim ersten Tippen.
- [ ] Das Fahrt-Panel der Fahrer (Get in / Let me out / View) verdeckt nicht die Firmenkarte im HUD (itinerary.md #5 offen), und das Banner rutscht darunter.
- [ ] Der Anruf der Assistentin öffnet sich über dem HUD. Annehmen und Ablehnen gehen per Tippen. Der Kalender zeigt die Reisepunkte (feste Gruppe noch offen, itinerary.md #9).
- [ ] Jet-Fahrt-GUI auf dem Handy: Fensteroval, Fluginfo unten und Handy-Knopf sind alle sichtbar und überlappen sich nicht.

**5. Leistung auf echten Geräten**
- [ ] Mittelklasse-Handy, beide Gründer auf Reise. Mit Autos, Limousinen, Jet, Shuttle, Passagieren im Terminal (≤ 40) und Hotelgästen (≤ 12) im Bild hält der Client ≥ 30 FPS bei Speicher < 1,2 GB.
- [ ] Server (Developer Console → Server Jobs): ItineraryService, DriverService und JetService bleiben mit 2 Gründern jeweils < 1 ms pro Heartbeat. Der Netzwerk-Empfang bleibt während einer Reise < 50 KB/s pro Client.
- [ ] Importiertes ExecutiveLimo-Mesh (falls unter ReplicatedStorage/Assets/Vehicles vorhanden): Es sieht richtig aus, die Türen öffnen zur Bordsteinseite, der Innenraum ist ab 150 Studs ausgeblendet, und es gibt keine Ruckler.
