let ctx: AudioContext | null = null;

function getCtx(): AudioContext {
  if (!ctx) ctx = new AudioContext();
  if (ctx.state === 'suspended') void ctx.resume();
  return ctx;
}

/**
 * Open the audio device from inside a real user gesture.
 *
 * WHY the game was silent on iPhone: every sound in here is triggered from the
 * game loop, not from the event handler that caused it. Pressing FIRE only sets
 * `state.fire = true`; the shot — and the first `new AudioContext()` with it —
 * happens on the next animation frame. iOS gives an AudioContext created
 * outside a user gesture the `suspended` state and refuses `resume()` there, so
 * the very first sound the game ever tried to make created a context that could
 * never start, and every later sound inherited it. There is no error for this;
 * it is simply quiet forever.
 *
 * Calling this from the touch/key handlers themselves means the context is
 * already running by the time the loop asks it for a sound.
 */
export function unlockAudio(): void {
  try {
    const ac = getCtx();
    if (ac.state === 'suspended') void ac.resume();
  } catch { /* no WebAudio here; the game stays playable, just silent */ }
}

function playTone(
  freq: number, type: OscillatorType, duration: number,
  gain = 0.3, freqEnd?: number, delay = 0
): void {
  try {
    const ac = getCtx();
    const osc = ac.createOscillator();
    const g = ac.createGain();
    osc.connect(g); g.connect(ac.destination);
    osc.type = type;
    osc.frequency.setValueAtTime(freq, ac.currentTime + delay);
    if (freqEnd !== undefined)
      osc.frequency.linearRampToValueAtTime(freqEnd, ac.currentTime + delay + duration);
    g.gain.setValueAtTime(gain, ac.currentTime + delay);
    g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + delay + duration);
    osc.start(ac.currentTime + delay);
    osc.stop(ac.currentTime + delay + duration);
  } catch { /* ignore */ }
}

function noise(duration: number, gain = 0.2, lowpass = 2000): void {
  try {
    const ac = getCtx();
    const buf = ac.createBuffer(1, ac.sampleRate * duration, ac.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    const src = ac.createBufferSource();
    src.buffer = buf;
    const filter = ac.createBiquadFilter();
    filter.type = 'lowpass'; filter.frequency.value = lowpass;
    const g = ac.createGain();
    g.gain.setValueAtTime(gain, ac.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, ac.currentTime + duration);
    src.connect(filter); filter.connect(g); g.connect(ac.destination);
    src.start(); src.stop(ac.currentTime + duration);
  } catch { /* ignore */ }
}

export const Audio = {
  pistol()    { noise(0.06, 0.4, 3000); playTone(200, 'sawtooth', 0.08, 0.2, 80); },
  shotgun()   { noise(0.18, 0.6, 800);  playTone(120, 'sawtooth', 0.12, 0.3, 60); },
  plasma()    { playTone(800, 'sine', 0.15, 0.3, 200); playTone(600, 'square', 0.1, 0.15); },
  rocket()    { noise(0.3, 0.5, 400);   playTone(80, 'sawtooth', 0.3, 0.4, 40); },
  railgun()   { playTone(1200, 'sine', 0.05, 0.5, 300); playTone(300, 'square', 0.2, 0.3, 200, 0.05); },
  hit()       { noise(0.08, 0.3, 1500); },
  enemyDie()  { noise(0.12, 0.4, 600); playTone(180, 'sawtooth', 0.15, 0.25, 60); },
  pickup()    { playTone(440, 'sine', 0.1, 0.3, 880); },
  key()       { playTone(660, 'sine', 0.05, 0.4, 880); playTone(880, 'sine', 0.1, 0.3, 1100, 0.08); },
  door()      { noise(0.2, 0.2, 300); },
  playerDie() { noise(0.4, 0.5, 400); playTone(100, 'sawtooth', 0.5, 0.4, 40); },
  secret()    { [440,550,660,880].forEach((f,i) => playTone(f,'sine',0.15,0.3,f*1.5,i*0.1)); },
  levelWin()  { [523,659,784,1047].forEach((f,i) => playTone(f,'sine',0.3,0.4,f,i*0.2)); },
};
