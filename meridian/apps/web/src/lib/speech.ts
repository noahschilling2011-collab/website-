// Dünne Wrapper um die Web Speech API (Spracherkennung + Sprachausgabe).
// Beide sind optional — fehlt die API, bleibt der Text-Modus nutzbar.

interface SpeechRecognitionLike {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  onresult: (e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void;
  onerror: (e: unknown) => void;
  onend: () => void;
  start: () => void;
  stop: () => void;
}

type RecognitionCtor = new () => SpeechRecognitionLike;

function getRecognitionCtor(): RecognitionCtor | null {
  const w = window as unknown as { SpeechRecognition?: RecognitionCtor; webkitSpeechRecognition?: RecognitionCtor };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export const sttSupported = (): boolean => getRecognitionCtor() !== null;
export const ttsSupported = (): boolean => typeof window !== 'undefined' && 'speechSynthesis' in window;

// Einmalige Diktat-Aufnahme; Promise löst mit erkanntem Text.
export function listenOnce(lang = 'de-DE'): { promise: Promise<string>; cancel: () => void } {
  const Ctor = getRecognitionCtor();
  if (!Ctor) return { promise: Promise.reject(new Error('Spracherkennung nicht unterstützt')), cancel: () => {} };
  const rec = new Ctor();
  rec.lang = lang;
  rec.interimResults = false;
  rec.continuous = false;
  let done = false;
  const promise = new Promise<string>((resolve, reject) => {
    rec.onresult = (e) => {
      done = true;
      resolve(e.results[0][0].transcript);
    };
    rec.onerror = (e) => reject(e);
    rec.onend = () => {
      if (!done) reject(new Error('Keine Sprache erkannt'));
    };
    rec.start();
  });
  return { promise, cancel: () => rec.stop() };
}

export function speak(text: string, lang = 'de-DE'): void {
  if (!ttsSupported()) return;
  const u = new SpeechSynthesisUtterance(text);
  u.lang = lang;
  u.rate = 1.02;
  const voice = window.speechSynthesis.getVoices().find((v) => v.lang.startsWith('de'));
  if (voice) u.voice = voice;
  window.speechSynthesis.cancel();
  window.speechSynthesis.speak(u);
}
