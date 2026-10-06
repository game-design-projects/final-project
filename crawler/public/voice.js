// Hold to talk: the browser's built-in speech recognition (Web Speech API) turns what you say into the words
// you'd otherwise type to a monster. Chrome, Edge and Safari have it; elsewhere the game just keeps the text box.
// No DOM access at import time, so the logic can be tested in Node.

// How long a key must be held before it means "listen" rather than a tap
export const HOLD_MS = 280;

// The browser's recognizer class, or null if it has none
export function recognizer(win = globalThis) {
  return win.SpeechRecognition ?? win.webkitSpeechRecognition ?? null;
}

// One listening session at a time: start() resolves with the words heard (possibly "") once you stop,
// or null if it was cancelled or speech isn't supported. onText gets the words so far as they come in.
export class Listener {
  constructor({ Recognition = recognizer(), lang = globalThis.navigator?.language || "en-US", onText = () => {}, onError = () => {} } = {}) {
    this.Recognition = Recognition;
    this.lang = lang;
    this.onText = onText;
    this.onError = onError;
    this.rec = null;
  }

  get supported() {
    return !!this.Recognition;
  }

  get listening() {
    return !!this.rec;
  }

  start() {
    if (!this.Recognition) return Promise.resolve(null);
    this.cancel();
    const rec = (this.rec = new this.Recognition());
    rec.lang = this.lang;
    rec.continuous = true; // keep listening for as long as the key is held
    rec.interimResults = true; // show the words while you're still speaking
    let text = "";
    let cancelled = false;
    rec.cancelled = () => (cancelled = true);
    const done = new Promise((resolve) => {
      rec.onresult = (ev) => {
        // The browser reports the whole session so far: finished phrases, then the one still in progress
        text = Array.from(ev.results, (r) => r[0].transcript).join("").replace(/\s+/g, " ").trim();
        this.onText(text);
      };
      rec.onerror = (ev) => {
        console.debug("voice: error", ev.error);
        if (ev.error !== "no-speech" && ev.error !== "aborted") this.onError(ev.error);
      };
      rec.onend = () => {
        if (this.rec === rec) this.rec = null;
        console.debug(`voice: heard "${text}"${cancelled ? " (cancelled)" : ""}`);
        resolve(cancelled ? null : text);
      };
    });
    try {
      rec.start();
      console.debug("voice: listening", this.lang);
    } catch (err) {
      // e.g. start() while a previous session is still shutting down
      console.warn("voice:", err);
      this.rec = null;
      return Promise.resolve(null);
    }
    return done;
  }

  // Let go: the browser finishes the last phrase, then start()'s promise resolves with everything
  stop() {
    this.rec?.stop();
  }

  cancel() {
    if (!this.rec) return;
    this.rec.cancelled();
    this.rec.abort();
    this.rec = null;
  }
}

// What holding Space does, from the game's state (pure, so it can be tested):
//   "listen": the talk box is open and empty, so speak into it
//   "talk":   in a fight with nothing else waiting, open TALK (T) and listen
//   "ally":   exploring with a monster ally, open TALK TO ALLY (E) and listen once its box opens
//   null:     Space is just a key here (a menu, a question, "any key", the monsters' turn, a box with text in it)
export function spaceHold({ inputOpen = false, inputEmpty = true, numeric = false, waiting = false, combat = false, allies = 0 } = {}) {
  if (inputOpen) return inputEmpty && !numeric ? "listen" : null;
  if (waiting) return null;
  if (combat) return "talk";
  if (allies > 0) return "ally";
  return null;
}
