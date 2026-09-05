# PHASE 9 — Voice

> Auftrag für Phase 9. Wird von `/phase 9` geladen.
> Regeln und Stack: `CLAUDE.md`. Datentypen: `docs/contracts.md`.
> Diese Phase erst starten, wenn Phase 8 in `STATUS.md` auf FERTIG steht.

**Auftrag:**
Starte mit der **kostenlosen** Variante: Web Speech API im Browser (`SpeechRecognition` für STT, `speechSynthesis` für TTS). Kein Key, keine Kosten, läuft in Chrome.

- `VoiceProvider`-Abstraktion, damit später ein besserer Anbieter dahinter kann.
- Push-to-Talk zuerst. **Wake Word erst danach** — Dauerhorchen ist ein eigenes, deutlich größeres Problem.
- Unterbrechbarkeit: laufende Sprachausgabe stoppt, wenn der Nutzer erneut die Taste drückt.
- Sprachumschaltung DE/EN.

**Definition of Done:**
1. Taste halten, sprechen, loslassen → Transkript erscheint im Chat und der Task startet.
2. Die Antwort wird vorgelesen und lässt sich abbrechen.
3. Die Antwort ist im Sprachmodus **kürzer** als im Textmodus — ein vorgelesener 500-Wörter-Absatz ist unbrauchbar. Der Systemprompt muss das erzwingen.
4. Deutsch und Englisch funktionieren beide.

**Verboten in dieser Phase:** Wake Word, Streaming-STT, Echtzeit-Unterbrechung mitten im Satz.
