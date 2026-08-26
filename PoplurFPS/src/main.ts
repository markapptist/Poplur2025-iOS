import { SCREEN_W, SCREEN_H, setScreenSize } from './game/constants.ts';
import { initInput, queueInteractCommand, showMobileControls } from './input.ts';
import { loadAssets } from './assets.ts';
import { Game, parseFpsDirectorSession } from './game/Game.ts';
import { renderLoadingScreen } from './render/Menu.ts';

const canvas = document.getElementById('game-canvas') as HTMLCanvasElement;
const externalController = new URLSearchParams(window.location.search).get('externalController') === '1';

function notifyParent(message: Record<string, unknown>): void {
  if (window.parent !== window) window.parent.postMessage(message, '*');
}

// TRUE fullscreen: the buffer is cut to the viewport's shape, so there is
// nothing left over to letterbox. The old version aspect-fitted a fixed 16:9
// buffer, which on a portrait phone meant black bands over roughly a third of
// the screen. Because the projection now scales from width (PROJ_H), the taller
// buffer shows more of the room instead of a stretched copy of the same view.
function resize(): void {
  const winW = Math.max(1, window.innerWidth);
  const winH = Math.max(1, window.innerHeight);
  setScreenSize(winW, winH);
  canvas.width = SCREEN_W;
  canvas.height = SCREEN_H;
  // The buffer matches the viewport aspect, so filling it cannot distort.
  canvas.style.width = `${winW}px`;
  canvas.style.height = `${winH}px`;
  // Nearest-neighbour has to be re-set: resizing a canvas resets its 2D state.
  const c = canvas.getContext('2d');
  if (c) c.imageSmoothingEnabled = false;
  // Controls now sit against the real screen edge rather than a letterbox band.
  const portraitHomeChrome = winH > winW * 1.25 ? Math.max(176, winH * 0.095) : 18;
  document.documentElement.style.setProperty('--game-control-bottom', `${portraitHomeChrome}px`);
}
resize();
window.addEventListener('resize', resize);
window.addEventListener('orientationchange', resize);

const ctx = canvas.getContext('2d')!;
ctx.imageSmoothingEnabled = false;

initInput(canvas);

// Initial loading screen while assets load
renderLoadingScreen(ctx, 0);

const game = new Game(ctx, externalController);

// The host may supply one already-generated mission. This listener performs no
// network or model work: it validates the small shared contract, then queues the
// local director balance for the next run so live combat remains authoritative.
window.addEventListener('message', event => {
  const expectedSource = window.parent === window ? window : window.parent;
  if (event.source !== expectedSource || !event.data || typeof event.data !== 'object') return;
  const message = event.data as Record<string, unknown>;
  if (message.type !== 'poplur-fps-director') return;
  // Prefer the documented envelope, while accepting the same plain fields at
  // the top level for older native shells that cannot wrap the payload.
  const session = parseFpsDirectorSession('session' in message ? message.session : message);
  if (!session) {
    notifyParent({ type: 'poplur-fps-director-rejected' });
    return;
  }
  if (!game.applyDirector(session)) {
    notifyParent({ type: 'poplur-fps-director-rejected' });
    return;
  }
  notifyParent({
    type: 'poplur-fps-director-applied',
    title: session.title,
    difficulty: session.difficulty,
    applies: 'next-run',
  });
});

loadAssets(pct => {
  game.loadProgress = pct;
  renderLoadingScreen(ctx, pct);
}).then(assets => {
  game.init(assets);
  notifyParent({ type: 'poplur-fps-ready' });
  notifyParent({ type: 'poplur-fps-state', state: game.state });
  startLoop();
});

let lastTime = performance.now();
let loopRunning = false;
let reportedState = game.state;

function tick(now: number): void {
  const dt = Math.min((now - lastTime) / 1000, 0.05);
  lastTime = now;
  ctx.clearRect(0, 0, SCREEN_W, SCREEN_H);
  try {
    game.update(dt);
    game.render();
    showMobileControls(game.state === 'playing' && !externalController);
    if (reportedState !== game.state) {
      reportedState = game.state;
      notifyParent({ type: 'poplur-fps-state', state: game.state });
    }
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
    if (!e.repeat) queueInteractCommand();
  }
  // Space / Enter skips the zoom animation immediately
  if ((e.code === 'Space' || e.code === 'Enter') && game.state === 'zoom') {
    game.zoomT = 1;
  }
});
