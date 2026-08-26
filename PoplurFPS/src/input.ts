import { unlockAudio } from './audio.ts';

export interface InputState {
  w: boolean; s: boolean; a: boolean; d: boolean;
  left: boolean; right: boolean;
  fire: boolean; interact: boolean;
  weapon1: boolean; weapon2: boolean; weapon3: boolean; weapon4: boolean; weapon5: boolean;
  mouseDX: number;
  escape: boolean;
  /** Analog stick, -1..1. Keyboard leaves these at 0 and uses the booleans. */
  axisFwd: number;
  axisStrafe: number;
  axisTurn: number;
  weaponNext: boolean;
}

const state: InputState = {
  w: false, s: false, a: false, d: false,
  left: false, right: false,
  fire: false, interact: false,
  weapon1: false, weapon2: false, weapon3: false, weapon4: false, weapon5: false,
  mouseDX: 0,
  escape: false,
  axisFwd: 0,
  axisStrafe: 0,
  axisTurn: 0,
  weaponNext: false,
};

let locked = false;
let externalInteractCommands = 0;
let externalPauseCommands = 0;
let externalWeaponCommands = 0;
let externalFireReleaseTimer: number | null = null;

const KEY_MAP: Record<string, keyof InputState> = {
  KeyW: 'w', ArrowUp: 'w',
  KeyS: 's', ArrowDown: 's',
  KeyA: 'a',
  KeyD: 'd',
  ArrowLeft: 'left',
  ArrowRight: 'right',
  Space: 'fire',
  KeyE: 'interact', KeyF: 'interact',
  Digit1: 'weapon1', Digit2: 'weapon2', Digit3: 'weapon3',
  Digit4: 'weapon4', Digit5: 'weapon5',
  Escape: 'escape',
};

export function initInput(canvas: HTMLCanvasElement): void {
  // Poplur wraps the FPS in a supplied 3D controller. Messages are used rather
  // than synthetic KeyboardEvents so analog sticks stay analog and WebKit does
  // not discard events created in the parent WebView.
  window.addEventListener('message', event => {
    if (window.parent !== window && event.source !== window.parent) return;
    const message = event.data as {
      type?: string;
      control?: string;
      x?: number;
      y?: number;
      pressed?: boolean;
    } | null;
    if (!message || message.type !== 'poplur-fps-control') return;
    unlockAudio();
    const clampAxis = (value: unknown) => Math.max(-1, Math.min(1, typeof value === 'number' ? value : 0));
    switch (message.control) {
      case 'move':
        state.axisStrafe = clampAxis(message.x);
        state.axisFwd = clampAxis(message.y);
        break;
      case 'look':
        state.axisTurn = clampAxis(message.x);
        break;
      case 'fire':
        if (externalFireReleaseTimer !== null) window.clearTimeout(externalFireReleaseTimer);
        externalFireReleaseTimer = null;
        if (message.pressed === true) {
          state.fire = true;
        } else {
          // Match the built-in arcade button: even the quickest controller tap
          // must survive long enough for at least one game frame to consume it.
          externalFireReleaseTimer = window.setTimeout(() => {
            state.fire = false;
            externalFireReleaseTimer = null;
          }, 80);
        }
        break;
      case 'interact':
        if (message.pressed === true) queueInteractCommand();
        break;
      case 'pause':
        if (message.pressed === true) externalPauseCommands = boundedQueue(externalPauseCommands);
        break;
      case 'weaponNext':
        if (message.pressed === true) externalWeaponCommands = boundedQueue(externalWeaponCommands);
        break;
    }
  });

  const releaseAllControls = () => {
    if (externalFireReleaseTimer !== null) window.clearTimeout(externalFireReleaseTimer);
    externalFireReleaseTimer = null;
    state.w = state.s = state.a = state.d = false;
    state.left = state.right = false;
    state.weapon1 = state.weapon2 = state.weapon3 = state.weapon4 = state.weapon5 = false;
    state.axisFwd = 0;
    state.axisStrafe = 0;
    state.axisTurn = 0;
    state.mouseDX = 0;
    state.fire = false;
    state.interact = false;
    state.escape = false;
    state.weaponNext = false;
    externalInteractCommands = 0;
    externalPauseCommands = 0;
    externalWeaponCommands = 0;
  };
  window.addEventListener('blur', releaseAllControls);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) releaseAllControls();
  });

  window.addEventListener('keydown', e => {
    unlockAudio();
    const k = KEY_MAP[e.code];
    if (k) (state as unknown as Record<string, boolean>)[k] = true;
  });
  window.addEventListener('keyup', e => {
    const k = KEY_MAP[e.code];
    if (k) (state as unknown as Record<string, boolean>)[k] = false;
  });

  canvas.addEventListener('click', () => {
    if (!locked) {
      canvas.requestPointerLock();
      // The cabinet is itself the start control. Keep the pulse alive long
      // enough for the menu state to consume it before pointer lock settles.
      state.interact = true;
      window.setTimeout(() => { state.interact = false; }, 80);
    }
  });

  document.addEventListener('pointerlockchange', () => {
    locked = document.pointerLockElement === canvas;
    if (!locked) state.fire = false;
  });

  document.addEventListener('mousemove', e => {
    if (locked) state.mouseDX += e.movementX;
  });

  canvas.addEventListener('mousedown', e => {
    if (locked && e.button === 0) state.fire = true;
  });
  document.addEventListener('mouseup', e => {
    if (e.button === 0) state.fire = false;
  });

  // ── touch controls ────────────────────────────────────────────────────────
  // Left stick moves, right side of the screen looks. That split is what makes
  // a shooter playable with thumbs, and its absence is what made this one feel
  // wrong: the stick used to be a four-way DIGITAL pad (full speed or nothing,
  // with a dead wedge on every diagonal), and its X axis TURNED the player
  // rather than strafing — so aiming and walking fought over the same thumb and
  // there was no way to look around at all.
  const joystick = document.getElementById('joystick-zone');
  const thumb = document.getElementById('joystick-thumb');
  if (joystick && thumb) {
    let activePointer: number | null = null;
    const updateJoystick = (e: PointerEvent) => {
      if (e.pointerId !== activePointer) return;
      const rect = joystick.getBoundingClientRect();
      const dx = e.clientX - (rect.left + rect.width / 2);
      const dy = e.clientY - (rect.top + rect.height / 2);
      const max = rect.width * 0.34;
      const length = Math.hypot(dx, dy);
      const scale = length > max ? max / length : 1;
      const cx = dx * scale;
      const cy = dy * scale;
      (thumb as HTMLElement).style.transform = `translate(${cx}px,${cy}px)`;

      // Analog, with a small dead zone so resting the thumb does not creep.
      const DEAD = 0.16;
      const norm = (v: number) => {
        const n = Math.max(-1, Math.min(1, v / max));
        if (Math.abs(n) < DEAD) return 0;
        // Rescale past the dead zone so control starts at zero, not at 0.16.
        return (n - Math.sign(n) * DEAD) / (1 - DEAD);
      };
      state.axisFwd = -norm(cy);
      state.axisStrafe = norm(cx);
      e.preventDefault();
    };
    const releaseJoystick = (e: PointerEvent) => {
      if (e.pointerId !== activePointer) return;
      activePointer = null;
      state.axisFwd = 0;
      state.axisStrafe = 0;
      state.w = state.s = state.left = state.right = false;
      (thumb as HTMLElement).style.transform = '';
    };
    joystick.addEventListener('pointerdown', e => {
      unlockAudio();
      activePointer = e.pointerId;
      joystick.setPointerCapture(e.pointerId);
      updateJoystick(e);
    });
    joystick.addEventListener('pointermove', updateJoystick);
    joystick.addEventListener('pointerup', releaseJoystick);
    joystick.addEventListener('pointercancel', releaseJoystick);
  }

  // Drag anywhere on the view to look. Feeds the same mouseDX the mouse path
  // uses, so turning behaves identically however you are playing.
  {
    let lookPointer: number | null = null;
    let lastLookX = 0;
    const TOUCH_LOOK_SENS = 2.1; // a thumb swipe covers far less than a mouse
    canvas.addEventListener('pointerdown', e => {
      unlockAudio();
      if (e.pointerType === 'mouse') return; // mouse keeps pointer lock
      lookPointer = e.pointerId;
      lastLookX = e.clientX;
    });
    canvas.addEventListener('pointermove', e => {
      if (e.pointerId !== lookPointer) return;
      state.mouseDX += (e.clientX - lastLookX) * TOUCH_LOOK_SENS;
      lastLookX = e.clientX;
      e.preventDefault();
    });
    const endLook = (e: PointerEvent) => { if (e.pointerId === lookPointer) lookPointer = null; };
    canvas.addEventListener('pointerup', endLook);
    canvas.addEventListener('pointercancel', endLook);
  }

  bindArcadeButton('fire-btn', 'fire');
  bindArcadeButton('interact-btn', 'interact');
}

function bindArcadeButton(id: string, key: 'fire' | 'interact'): void {
  const button = document.getElementById(id);
  if (!button) return;
  let releaseTimer: number | null = null;
  const release = () => {
    if (releaseTimer) window.clearTimeout(releaseTimer);
    // Keep a quick tap alive long enough for at least one game frame.
    releaseTimer = window.setTimeout(() => {
      state[key] = false;
      releaseTimer = null;
    }, 80);
  };
  button.addEventListener('pointerdown', e => {
    unlockAudio();
    if (releaseTimer) window.clearTimeout(releaseTimer);
    releaseTimer = null;
    button.setPointerCapture(e.pointerId);
    state[key] = true;
    e.preventDefault();
  });
  button.addEventListener('pointerup', release);
  button.addEventListener('pointercancel', release);
  button.addEventListener('lostpointercapture', release);
}

export function getInput(): InputState { return state; }

export function consumeMouseDX(): number {
  const v = state.mouseDX;
  state.mouseDX = 0;
  return v;
}

/** Button commands are queued until a game frame consumes them. A WebView can
    briefly suspend requestAnimationFrame while compositing or screenshotting;
    a conventional 100ms key pulse can begin and end entirely inside that gap. */
export function consumeInteractCommand(): boolean {
  if (externalInteractCommands <= 0) return false;
  externalInteractCommands--;
  return true;
}

/** Queue one edge-triggered ACT command without synthesizing a held key. */
export function queueInteractCommand(): void {
  externalInteractCommands = boundedQueue(externalInteractCommands);
}

export function consumePauseCommand(): boolean {
  if (externalPauseCommands <= 0) return false;
  externalPauseCommands--;
  return true;
}

export function consumeWeaponNextCommand(): boolean {
  if (externalWeaponCommands <= 0) return false;
  externalWeaponCommands--;
  return true;
}

export function isPointerLocked(): boolean { return locked; }

export function showMobileControls(visible = true): void {
  const mc = document.getElementById('mobile-controls');
  if (mc) mc.style.display = visible ? 'flex' : 'none';
}

function boundedQueue(current: number): number {
  // A controller or hostile message sender cannot create minutes of phantom
  // actions; four edges cover every legitimate frame-throttling burst.
  return Math.min(4, current + 1);
}
