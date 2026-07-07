import { SCREEN_W, SCREEN_H } from './game/constants.ts';
import { initInput, showMobileControls } from './input.ts';
import { loadAssets } from './assets.ts';
import { Game } from './game/Game.ts';
import { renderLoadingScreen } from './render/Menu.ts';

const canvas = document.getElementById('game-canvas') as HTMLCanvasElement;
canvas.width  = SCREEN_W;
canvas.height = SCREEN_H;

// Scale canvas to fill window, preserving aspect ratio
function resize(): void {
  const winW = window.innerWidth;
  const winH = window.innerHeight;
  const scale = Math.min(winW / SCREEN_W, winH / SCREEN_H);
  canvas.style.width  = `${SCREEN_W * scale}px`;
  canvas.style.height = `${SCREEN_H * scale}px`;
}
resize();
window.addEventListener('resize', resize);

// Show mobile controls on touch devices
if ('ontouchstart' in window) showMobileControls();

const ctx = canvas.getContext('2d')!;
ctx.imageSmoothingEnabled = false;

initInput(canvas);

// Initial loading screen while assets load
renderLoadingScreen(ctx, 0);

const game = new Game(ctx);

loadAssets(pct => {
  game.loadProgress = pct;
  renderLoadingScreen(ctx, pct);
}).then(assets => {
  game.init(assets);
  startLoop();
});

let lastTime = performance.now();
let loopRunning = false;

function tick(now: number): void {
  const dt = Math.min((now - lastTime) / 1000, 0.05);
  lastTime = now;
  ctx.clearRect(0, 0, SCREEN_W, SCREEN_H);
  try {
    game.update(dt);
    game.render();
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.stack ?? e.message : String(e);
    console.error('GAME_LOOP_ERROR', msg);
  }
}

function loop(now: number): void {
  tick(now);
  requestAnimationFrame(loop);
}

function startLoop(): void {
  loopRunning = true;
  lastTime = performance.now();
  requestAnimationFrame(loop);

  // setInterval fallback keeps game alive in backgrounded/throttled tabs
  setInterval(() => {
    if (document.hidden) {
      tick(performance.now());
    }
  }, 100); // 10fps fallback when tab is hidden
}

// Allow keyboard navigation on menu / zoom skip
window.addEventListener('keydown', e => {
  if (e.code === 'Enter' || e.code === 'NumpadEnter') {
    const inputEvt = new KeyboardEvent('keydown', { code: 'KeyE', key: 'e', bubbles: true });
    window.dispatchEvent(inputEvt);
  }
  // Space / Enter skips the zoom animation immediately
  if ((e.code === 'Space' || e.code === 'Enter') && game.state === 'zoom') {
    game.zoomT = 1;
  }
});
