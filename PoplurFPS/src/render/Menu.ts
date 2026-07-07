import { SCREEN_W, SCREEN_H } from '../game/constants.ts';
import type { Assets } from '../assets.ts';

export type MenuSelection = 0 | 1;  // 0=1 Player, 1=2 Player (demo)

interface CabinetLayout {
  cx: number; cy: number;  // cabinet center on screen
  cw: number; ch: number;  // cabinet width/height
  screenX: number; screenY: number; screenW: number; screenH: number; // game screen rect
}

let glitterCanvas: HTMLCanvasElement | null = null;

function makeGlitter(w: number, h: number): HTMLCanvasElement {
  const oc = document.createElement('canvas');
  oc.width = w; oc.height = h;
  const oc2 = oc.getContext('2d')!;
  // Pink gradient base
  const g = oc2.createLinearGradient(0, 0, w, h);
  g.addColorStop(0,   '#c01260');
  g.addColorStop(0.3, '#e01878');
  g.addColorStop(0.6, '#d01468');
  g.addColorStop(1,   '#b00e58');
  oc2.fillStyle = g;
  oc2.fillRect(0, 0, w, h);
  // Sparkle dots
  const rng = (n: number) => Math.random() * n;
  for (let i = 0; i < 1800; i++) {
    const x = rng(w), y = rng(h);
    const r = rng(1.5) + 0.3;
    const bright = Math.random();
    oc2.beginPath();
    oc2.arc(x, y, r, 0, Math.PI * 2);
    oc2.fillStyle = bright > 0.8 ? `rgba(255,255,255,${rng(0.9) + 0.1})`
                  : bright > 0.5 ? `rgba(255,200,220,${rng(0.7) + 0.1})`
                  : `rgba(255,150,200,${rng(0.5) + 0.1})`;
    oc2.fill();
  }
  return oc;
}

function cabinetLayout(scale: number, offsetX: number, offsetY: number): CabinetLayout {
  const cw = 340 * scale, ch = 460 * scale;
  const cx = SCREEN_W / 2 + offsetX, cy = SCREEN_H / 2 + offsetY;
  const screenW = 238 * scale, screenH = 170 * scale;
  const screenX = cx - screenW / 2;
  const screenY = cy - 38 * scale;
  return { cx, cy, cw, ch, screenX, screenY, screenW, screenH };
}

export function renderMenuCabinet(
  ctx: CanvasRenderingContext2D,
  assets: Assets,
  selectedOption: MenuSelection,
  tickTime: number,
  t: number   // zoom progress 0=full cabinet 1=just screen
): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.save();

  // Zoom interpolation — scale/translate to zoom into screen area
  const layout0 = cabinetLayout(0.55, 0, 0);   // initial position

  if (t > 0) {
    const scaleTarget = W / layout0.screenW;
    const txTarget = W / 2 - (layout0.screenX + layout0.screenW / 2) * scaleTarget;
    const tyTarget = H / 2 - (layout0.screenY + layout0.screenH / 2) * scaleTarget;
    const ease = t < 1 ? t * t * (3 - 2 * t) : 1; // smoothstep
    const sc = 1 + (scaleTarget - 1) * ease;
    const tx = txTarget * ease;
    const ty = tyTarget * ease;
    ctx.setTransform(sc, 0, 0, sc, tx, ty);
  }

  const L = cabinetLayout(0.55, 0, 0);

  // — Arcade room dark background —
  const bgGrad = ctx.createRadialGradient(W/2, H/2, 0, W/2, H/2, W * 0.7);
  bgGrad.addColorStop(0, '#1a0028');
  bgGrad.addColorStop(1, '#050008');
  ctx.fillStyle = bgGrad;
  ctx.fillRect(0, 0, W, H);

  // Distant arcade machines (simple silhouettes)
  ctx.fillStyle = '#14001e';
  for (const [bx, bw, bh] of [[30, 60, 120], [580, 55, 100], [510, 45, 90]] as [number,number,number][]) {
    ctx.fillRect(bx, H - bh, bw, bh);
    ctx.fillStyle = '#220033'; ctx.fillRect(bx + 5, H - bh - 20, bw - 10, 20); ctx.fillStyle = '#14001e';
  }
  // Floor glow
  const floorGlow = ctx.createLinearGradient(0, H - 60, 0, H);
  floorGlow.addColorStop(0, 'rgba(200,0,100,0.12)');
  floorGlow.addColorStop(1, 'rgba(200,0,100,0)');
  ctx.fillStyle = floorGlow;
  ctx.fillRect(0, H - 60, W, 60);

  const { cx, cy, cw, ch, screenX, screenY, screenW, screenH } = L;
  const cabTop = cy - ch / 2;
  const cabBot = cy + ch / 2;
  const cabL   = cx - cw / 2;
  const cabR   = cx + cw / 2;

  // Cabinet drop shadow
  ctx.fillStyle = 'rgba(0,0,0,0.7)';
  ctx.beginPath();
  ctx.ellipse(cx, cabBot + 8, cw * 0.45, 12, 0, 0, Math.PI * 2);
  ctx.fill();

  // — Cabinet body (glitter) —
  if (!glitterCanvas || glitterCanvas.width !== Math.ceil(cw)) {
    glitterCanvas = makeGlitter(Math.ceil(cw) + 40, Math.ceil(ch) + 40);
  }
  ctx.save();
  // Clip to cabinet shape (rounded rect)
  roundRect(ctx, cabL, cabTop + 30, cw, ch - 30, 10);
  ctx.clip();
  ctx.drawImage(glitterCanvas, cabL - 5, cabTop + 25);
  ctx.restore();

  // Cabinet outline
  ctx.strokeStyle = '#c8960a';
  ctx.lineWidth = 3;
  roundRect(ctx, cabL, cabTop + 30, cw, ch - 30, 10);
  ctx.stroke();

  // — Marquee (top) —
  const marqH = 52;
  const marqY = cabTop + 28;
  ctx.fillStyle = '#1a0030';
  roundRect(ctx, cabL, marqY, cw, marqH, 10);
  ctx.fill();
  ctx.strokeStyle = '#ffd700';
  ctx.lineWidth = 2;
  roundRect(ctx, cabL, marqY, cw, marqH, 10);
  ctx.stroke();

  // Marquee glow
  const marqGlow = ctx.createLinearGradient(cabL, marqY, cabR, marqY + marqH);
  marqGlow.addColorStop(0,   'rgba(255,80,180,0.3)');
  marqGlow.addColorStop(0.5, 'rgba(255,180,100,0.4)');
  marqGlow.addColorStop(1,   'rgba(255,80,180,0.3)');
  ctx.fillStyle = marqGlow;
  roundRect(ctx, cabL, marqY, cw, marqH, 10);
  ctx.fill();

  // P logos on marquee
  const logo = assets.misc.logo;
  const logoSz = 34;
  if (logo) {
    ctx.drawImage(logo, cabL + 8, marqY + 9, logoSz, logoSz);
    ctx.drawImage(logo, cabR - 8 - logoSz, marqY + 9, logoSz, logoSz);
  }

  // POPLUR text
  ctx.font = `bold ${(cw * 0.145) | 0}px monospace`;
  ctx.textAlign = 'center';
  ctx.fillStyle = '#ffd700';
  ctx.shadowColor = '#ff88aa';
  ctx.shadowBlur = 8;
  ctx.fillText('poplur', cx, marqY + 34);
  ctx.shadowBlur = 0;
  ctx.textAlign = 'left';

  // — Screen bezel —
  const bezelPad = 12;
  ctx.fillStyle = '#0a0012';
  roundRect(ctx,
    screenX - bezelPad, screenY - bezelPad,
    screenW + bezelPad * 2, screenH + bezelPad * 2, 8
  );
  ctx.fill();
  ctx.strokeStyle = '#333';
  ctx.lineWidth = 1;
  roundRect(ctx,
    screenX - bezelPad, screenY - bezelPad,
    screenW + bezelPad * 2, screenH + bezelPad * 2, 8
  );
  ctx.stroke();

  // — Game screen content —
  ctx.save();
  ctx.beginPath();
  ctx.rect(screenX, screenY, screenW, screenH);
  ctx.clip();

  const menuImg = assets.menu.main_menu;
  if (menuImg) {
    // The pre-rendered menu art already contains HI-SCORE / START GAME /
    // 1-2 PLAYER / CREDIT baked in, so draw ONLY the image — no code-drawn
    // text overlay (that produced a doubled/ghosted look).
    ctx.drawImage(menuImg, screenX, screenY, screenW, screenH);

    // Blink the "insert coin" prompt strip for arcade liveliness.
    const blink = Math.floor(tickTime * 2) % 2 === 0;
    if (blink) {
      ctx.fillStyle = 'rgba(255,215,0,0.10)';
      ctx.fillRect(screenX, screenY + screenH * 0.60, screenW, screenH * 0.16);
    }
  } else {
    // Fallback drawn menu (only when the pre-rendered menu art is unavailable)
    const sbg = ctx.createLinearGradient(screenX, screenY, screenX, screenY + screenH);
    sbg.addColorStop(0, '#080020');
    sbg.addColorStop(1, '#180040');
    ctx.fillStyle = sbg;
    ctx.fillRect(screenX, screenY, screenW, screenH);

    const blink = Math.floor(tickTime * 2) % 2 === 0;
    const fz = (screenH * 0.105) | 0;
    ctx.font = `bold ${fz}px monospace`;
    ctx.textAlign = 'center';

    const menuItems = ['1 PLAYER', '2 PLAYER'];
    for (let i = 0; i < menuItems.length; i++) {
      const itemY = screenY + screenH * (0.67 + i * 0.155);
      const sel = i === selectedOption;
      ctx.fillStyle = sel ? (blink ? '#ffd700' : '#ffaa00') : '#ff8cc8';
      ctx.shadowColor = sel ? '#ffd700' : '#ff4db8';
      ctx.shadowBlur = sel ? 6 : 0;
      ctx.fillText(`${sel ? '▶ ' : '  '}${menuItems[i]}`, cx, itemY);
      ctx.shadowBlur = 0;
    }

    const hf = (screenH * 0.08) | 0;
    ctx.font = `bold ${hf}px monospace`;
    ctx.fillStyle = '#ffd700';
    ctx.fillText('HI-SCORE', cx, screenY + screenH * 0.12);
    ctx.fillText('0012571', cx, screenY + screenH * 0.21);
    ctx.fillText('CREDIT 012', cx, screenY + screenH * 0.93);

    ctx.textAlign = 'left';
  }

  ctx.restore();

  // Screen glow / scanline tint
  const screenGlow = ctx.createRadialGradient(
    screenX + screenW / 2, screenY + screenH / 2, screenW * 0.1,
    screenX + screenW / 2, screenY + screenH / 2, screenW * 0.75
  );
  screenGlow.addColorStop(0, 'rgba(180,80,255,0.0)');
  screenGlow.addColorStop(1, 'rgba(100,0,180,0.25)');
  ctx.fillStyle = screenGlow;
  ctx.fillRect(screenX, screenY, screenW, screenH);

  // — Controls bar —
  const ctrlY = screenY + screenH + bezelPad + 10;
  const ctrlH = 50;
  ctx.fillStyle = '#0d0020';
  ctx.fillRect(cabL + 2, ctrlY, cw - 4, ctrlH);
  ctx.strokeStyle = '#c8960a'; ctx.lineWidth = 1.5;
  ctx.strokeRect(cabL + 2, ctrlY, cw - 4, ctrlH);

  // Joystick
  const jx = cabL + 30, jy = ctrlY + ctrlH / 2;
  ctx.fillStyle = '#111';
  ctx.beginPath(); ctx.arc(jx, jy, 14, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#333';
  ctx.beginPath(); ctx.arc(jx, jy, 10, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#1a1a1a';
  ctx.fillRect(jx - 3, jy - 18, 6, 20);
  ctx.beginPath(); ctx.arc(jx, jy - 18, 6, 0, Math.PI * 2);
  ctx.fillStyle = '#555'; ctx.fill();

  // Buttons
  const btnCols = ['#d4a000', '#e01888', '#00a830', '#1060c8', '#e01888'];
  const btnLabels = ['START', 'SEL', '', '', ''];
  for (let i = 0; i < 5; i++) {
    const bx = cabL + 75 + i * 44;
    const by = ctrlY + ctrlH / 2;
    ctx.beginPath(); ctx.arc(bx, by, 14, 0, Math.PI * 2);
    ctx.fillStyle = btnCols[i]; ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.3)'; ctx.lineWidth = 1;
    ctx.stroke();
    ctx.beginPath(); ctx.arc(bx - 3, by - 3, 5, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.25)'; ctx.fill();
    if (btnLabels[i]) {
      ctx.font = '6px monospace'; ctx.fillStyle = '#fff';
      ctx.textAlign = 'center';
      ctx.fillText(btnLabels[i], bx, by + 23);
      ctx.textAlign = 'left';
    }
  }

  // Poplur wordmark at bottom
  ctx.font = `bold ${(cw * 0.07) | 0}px monospace`;
  ctx.fillStyle = '#ff4db8';
  ctx.textAlign = 'center';
  ctx.fillText('𝕡poplur', cx, cabBot - 10);
  ctx.textAlign = 'left';

  ctx.restore();
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.lineTo(x + w, y + h - r);
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  ctx.lineTo(x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

export function renderLoadingScreen(ctx: CanvasRenderingContext2D, progress: number): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.fillStyle = '#0a0018';
  ctx.fillRect(0, 0, W, H);

  ctx.font = 'bold 28px monospace';
  ctx.fillStyle = '#ff4db8';
  ctx.textAlign = 'center';
  ctx.fillText('POPLUR FPS', W / 2, H / 2 - 40);
  ctx.font = '14px monospace';
  ctx.fillStyle = '#aaa';
  ctx.fillText('LOADING ASSETS...', W / 2, H / 2);

  // Progress bar
  const bw = 200, bh = 8;
  ctx.fillStyle = '#1a0030';
  ctx.fillRect(W / 2 - bw / 2, H / 2 + 20, bw, bh);
  ctx.fillStyle = '#ff4db8';
  ctx.fillRect(W / 2 - bw / 2, H / 2 + 20, bw * progress, bh);

  ctx.textAlign = 'left';
}
