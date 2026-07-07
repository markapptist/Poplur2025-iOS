export interface InputState {
  w: boolean; s: boolean; a: boolean; d: boolean;
  left: boolean; right: boolean;
  fire: boolean; interact: boolean;
  weapon1: boolean; weapon2: boolean; weapon3: boolean; weapon4: boolean; weapon5: boolean;
  mouseDX: number;
  escape: boolean;
}

const state: InputState = {
  w: false, s: false, a: false, d: false,
  left: false, right: false,
  fire: false, interact: false,
  weapon1: false, weapon2: false, weapon3: false, weapon4: false, weapon5: false,
  mouseDX: 0,
  escape: false,
};

let locked = false;

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
  window.addEventListener('keydown', e => {
    const k = KEY_MAP[e.code];
    if (k) (state as unknown as Record<string, boolean>)[k] = true;
  });
  window.addEventListener('keyup', e => {
    const k = KEY_MAP[e.code];
    if (k) (state as unknown as Record<string, boolean>)[k] = false;
  });

  canvas.addEventListener('click', () => {
    if (!locked) canvas.requestPointerLock();
  });

  document.addEventListener('pointerlockchange', () => {
    locked = document.pointerLockElement === canvas;
  });

  document.addEventListener('mousemove', e => {
    if (locked) state.mouseDX += e.movementX;
  });

  canvas.addEventListener('mousedown', e => {
    if (locked && e.button === 0) state.fire = true;
  });
  canvas.addEventListener('mouseup', e => {
    if (e.button === 0) state.fire = false;
  });

  // Touch joystick
  const joystick = document.getElementById('joystick-zone');
  const thumb = document.getElementById('joystick-thumb');
  if (joystick && thumb) {
    let startX = 0, startY = 0, active = false;
    joystick.addEventListener('touchstart', e => {
      active = true;
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      e.preventDefault();
    }, { passive: false });
    joystick.addEventListener('touchmove', e => {
      if (!active) return;
      const dx = e.touches[0].clientX - startX;
      const dy = e.touches[0].clientY - startY;
      const max = 36;
      const cx = Math.max(-max, Math.min(max, dx));
      const cy = Math.max(-max, Math.min(max, dy));
      (thumb as HTMLElement).style.transform = `translate(${cx}px,${cy}px)`;
      state.w = cy < -10;
      state.s = cy > 10;
      state.a = cx < -10;
      state.d = cx > 10;
      e.preventDefault();
    }, { passive: false });
    joystick.addEventListener('touchend', () => {
      active = false;
      state.w = state.s = state.a = state.d = false;
      (thumb as HTMLElement).style.transform = '';
    });
  }

  const fireBtn = document.getElementById('fire-btn');
  if (fireBtn) {
    fireBtn.addEventListener('touchstart', e => { state.fire = true; e.preventDefault(); }, { passive: false });
    fireBtn.addEventListener('touchend', () => { state.fire = false; });
  }
  const interactBtn = document.getElementById('interact-btn');
  if (interactBtn) {
    interactBtn.addEventListener('touchstart', e => { state.interact = true; e.preventDefault(); }, { passive: false });
    interactBtn.addEventListener('touchend', () => { state.interact = false; });
  }
}

export function getInput(): InputState { return state; }

export function consumeMouseDX(): number {
  const v = state.mouseDX;
  state.mouseDX = 0;
  return v;
}

export function isPointerLocked(): boolean { return locked; }

export function showMobileControls(): void {
  const mc = document.getElementById('mobile-controls');
  if (mc) mc.style.display = 'flex';
}
