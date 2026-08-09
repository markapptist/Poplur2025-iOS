import { SCREEN_W, SCREEN_H, WEAPONS, AMMO_TYPES } from '../game/constants.ts';
import type { Player } from '../game/Player.ts';
import type { Assets } from '../assets.ts';
import type { Level } from '../game/Level.ts';
import { MAP_W, MAP_H } from '../game/constants.ts';

const PINK = '#ff4db8';
const GOLD = '#ffd700';
const GREEN = '#00ff88';
const RED   = '#ff3333';

function px(n: number, base = SCREEN_W): number { return (n / 640) * base; }

export function renderHUD(
  ctx: CanvasRenderingContext2D,
  player: Player,
  assets: Assets,
  level: Level,
  score: number,
  kills: number,
  gametime: number
): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.save();

  // — Bottom bar background —
  const barH = 56;
  ctx.fillStyle = 'rgba(10,0,20,0.88)';
  ctx.fillRect(0, H - barH, W, barH);
  ctx.strokeStyle = PINK;
  ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(0, H - barH); ctx.lineTo(W, H - barH); ctx.stroke();

  // HUD face
  const face = assets.hud.face;
  const faceSize = 46;
  const facePad = 6;
  if (face) {
    ctx.drawImage(face, W / 2 - faceSize / 2, H - faceSize - facePad + 2, faceSize, faceSize);
  }

  // — HEALTH —
  const hlth = assets.hud.health;
  if (hlth) ctx.drawImage(hlth, 8, H - barH + 6, 18, 18);
  ctx.font = 'bold 22px monospace';
  ctx.fillStyle = player.health > 50 ? GREEN : player.health > 25 ? '#ffaa00' : RED;
  ctx.fillText(String(player.health), 30, H - barH + 22);

  // Health bar
  const hbW = 70, hbH = 6;
  ctx.fillStyle = '#111';
  ctx.fillRect(8, H - barH + 28, hbW, hbH);
  ctx.fillStyle = player.health > 50 ? GREEN : player.health > 25 ? '#ffaa00' : RED;
  ctx.fillRect(8, H - barH + 28, hbW * (player.health / player.maxHealth), hbH);

  // — ARMOR —
  const armorIco = assets.hud.armor;
  const ax = 90;
  if (armorIco) ctx.drawImage(armorIco, ax, H - barH + 6, 18, 18);
  ctx.font = 'bold 22px monospace';
  ctx.fillStyle = '#88aaff';
  ctx.fillText(String(player.armor), ax + 22, H - barH + 22);
  ctx.fillStyle = '#111';
  ctx.fillRect(ax, H - barH + 28, 70, hbH);
  ctx.fillStyle = '#4488ff';
  ctx.fillRect(ax, H - barH + 28, 70 * (player.armor / player.maxArmor), hbH);

  // — WEAPON + AMMO —
  const wDef = WEAPONS[player.weapon];
  const ammoIco = assets.hud.ammo;
  const wx = 175;
  if (ammoIco) ctx.drawImage(ammoIco, wx, H - barH + 6, 18, 18);
  ctx.font = 'bold 14px monospace';
  ctx.fillStyle = GOLD;
  ctx.fillText(wDef.name, wx, H - barH + 42);
  ctx.font = 'bold 22px monospace';
  const ammoLeft = player.ammo[wDef.ammoType];
  ctx.fillStyle = ammoLeft > 10 ? GOLD : RED;
  ctx.fillText(`${ammoLeft}`, wx + 22, H - barH + 22);

  // — Weapon slot icons —
  const slotX0 = W - 5 * 38 - 8;
  for (let i = 0; i < 5; i++) {
    const sx = slotX0 + i * 38;
    const sy = H - 52;
    ctx.fillStyle = i === player.weapon ? 'rgba(180,0,90,0.7)' : 'rgba(20,0,40,0.6)';
    ctx.strokeStyle = i === player.weapon ? PINK : '#550033';
    ctx.lineWidth = 1;
    ctx.fillRect(sx, sy, 34, 30);
    ctx.strokeRect(sx, sy, 34, 30);
    ctx.font = 'bold 10px monospace';
    ctx.fillStyle = i === player.weapon ? GOLD : '#888';
    ctx.fillText(`${i + 1}`, sx + 3, sy + 12);
    ctx.font = '8px monospace';
    ctx.fillStyle = '#aaa';
    ctx.fillText(WEAPONS[i].name.slice(0, 4), sx + 2, sy + 24);
    // ammo dot
    const a = player.ammo[WEAPONS[i].ammoType];
    ctx.fillStyle = a > 0 ? GREEN : RED;
    ctx.fillRect(sx + 26, sy + 3, 5, 5);
  }

  // — Keys display —
  ctx.font = '12px monospace';
  let kx = W - 5 * 38 - 8 - 28;
  if (player.hasKey['gold']) {
    const kg = assets.pickups.key_g;
    if (kg) ctx.drawImage(kg, kx, H - 50, 22, 22);
    kx -= 26;
  }
  if (player.hasKey['pink']) {
    const kp = assets.pickups.key_p;
    if (kp) ctx.drawImage(kp, kx, H - 50, 22, 22);
  }

  // — Top HUD: score / kills / time —
  ctx.fillStyle = 'rgba(10,0,20,0.7)';
  ctx.fillRect(0, 0, W, 22);
  ctx.font = 'bold 13px monospace';

  ctx.fillStyle = GOLD;
  ctx.fillText(`SCORE: ${String(score).padStart(7, '0')}`, 8, 15);

  ctx.fillStyle = PINK;
  const mm = Math.floor(gametime / 60).toString().padStart(2, '0');
  const ss = Math.floor(gametime % 60).toString().padStart(2, '0');
  ctx.fillText(`${mm}:${ss}`, W / 2 - 20, 15);

  ctx.fillStyle = '#aaffdd';
  ctx.fillText(`KILLS: ${kills}`, W - 90, 15);

  ctx.font = 'bold 9px monospace';
  ctx.fillStyle = 'rgba(255,255,255,0.78)';
  ctx.fillText('MISSION 01  //  CLEAR THE ARCADE', 8, 34);

  const ahead = level.getCell(player.x + player.dirX * 1.15, player.y + player.dirY * 1.15);
  if (ahead === 7 || ahead === 8 || ahead === 9) {
    const prompt = ahead === 7 ? 'ACT  OPEN DOOR' : 'ACT  KEY REQUIRED';
    ctx.font = 'bold 12px monospace';
    const promptWidth = ctx.measureText(prompt).width + 20;
    ctx.fillStyle = 'rgba(10,0,20,0.82)';
    ctx.fillRect(W / 2 - promptWidth / 2, H * 0.62, promptWidth, 24);
    ctx.strokeStyle = PINK;
    ctx.strokeRect(W / 2 - promptWidth / 2, H * 0.62, promptWidth, 24);
    ctx.fillStyle = '#fff';
    ctx.fillText(prompt, W / 2 - promptWidth / 2 + 10, H * 0.62 + 16);
  }

  // — Minimap —
  renderMinimap(ctx, player, level, W, H);

  // — Damage flash —
  if (player.flashAlpha > 0) {
    ctx.fillStyle = `rgba(200,0,0,${player.flashAlpha * 0.35})`;
    ctx.fillRect(0, 0, W, H - barH);
  }

  // — Crosshair —
  const cx2 = W / 2, cy2 = H / 2;
  ctx.strokeStyle = 'rgba(255,255,255,0.7)';
  ctx.lineWidth = 1;
  const csz = 8;
  ctx.beginPath();
  ctx.moveTo(cx2 - csz, cy2); ctx.lineTo(cx2 + csz, cy2);
  ctx.moveTo(cx2, cy2 - csz); ctx.lineTo(cx2, cy2 + csz);
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,100,200,0.8)';
  ctx.fillRect(cx2 - 1, cy2 - 1, 2, 2);

  ctx.restore();
}

function renderMinimap(
  ctx: CanvasRenderingContext2D,
  player: Player,
  level: Level,
  W: number,
  H: number
): void {
  const mapSize = 80, tSize = 3;
  const mX = W - mapSize - 6, mY = 26;
  const visRadius = 13; // tiles visible around player
  const pMapX = Math.floor(player.x);
  const pMapY = Math.floor(player.y);

  ctx.fillStyle = 'rgba(10,0,20,0.75)';
  ctx.fillRect(mX, mY, mapSize, mapSize);
  ctx.strokeStyle = PINK; ctx.lineWidth = 1;
  ctx.strokeRect(mX, mY, mapSize, mapSize);

  const tilesVisible = Math.floor(mapSize / tSize);
  const startTX = pMapX - Math.floor(tilesVisible / 2);
  const startTY = pMapY - Math.floor(tilesVisible / 2);

  for (let ty = 0; ty < tilesVisible; ty++) {
    for (let tx = 0; tx < tilesVisible; tx++) {
      const mx = startTX + tx, my = startTY + ty;
      const t = level.getCell(mx, my);
      if (t === 0) continue;
      const door = level.getDoor(mx, my);
      if ((door?.open ?? 0) >= 0.5) {
        ctx.fillStyle = '#334';
      } else if (t === 7) {
        ctx.fillStyle = '#aa6600';
      } else if (t === 8 || t === 9) {
        ctx.fillStyle = '#ff4400';
      } else {
        ctx.fillStyle = `hsl(${t * 40 + 240},40%,35%)`;
      }
      ctx.fillRect(mX + tx * tSize, mY + ty * tSize, tSize - 1, tSize - 1);
    }
  }

  // Player dot
  const pdx = (pMapX - startTX) * tSize + (player.x - pMapX) * tSize;
  const pdy = (pMapY - startTY) * tSize + (player.y - pMapY) * tSize;
  ctx.fillStyle = PINK;
  ctx.fillRect(mX + pdx - 2, mY + pdy - 2, 4, 4);
  // direction arrow
  ctx.strokeStyle = GOLD; ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(mX + pdx, mY + pdy);
  ctx.lineTo(mX + pdx + player.dirX * 5, mY + pdy + player.dirY * 5);
  ctx.stroke();
}

export function renderDeathScreen(ctx: CanvasRenderingContext2D, alpha: number): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.fillStyle = `rgba(150,0,0,${alpha * 0.65})`;
  ctx.fillRect(0, 0, W, H);
  if (alpha < 0.7) return;
  ctx.font = 'bold 52px monospace';
  ctx.fillStyle = RED;
  ctx.textAlign = 'center';
  ctx.fillText('YOU DIED', W / 2, H / 2 - 20);
  ctx.font = 'bold 20px monospace';
  ctx.fillStyle = '#fff';
  ctx.fillText('PRESS ENTER TO RESPAWN', W / 2, H / 2 + 30);
  ctx.textAlign = 'left';
}

export function renderPauseScreen(ctx: CanvasRenderingContext2D): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.fillStyle = 'rgba(0,0,0,0.6)';
  ctx.fillRect(0, 0, W, H);
  ctx.font = 'bold 42px monospace';
  ctx.fillStyle = PINK;
  ctx.textAlign = 'center';
  ctx.fillText('PAUSED', W / 2, H / 2);
  ctx.font = '18px monospace';
  ctx.fillStyle = '#fff';
  ctx.fillText('ESC to resume', W / 2, H / 2 + 40);
  ctx.textAlign = 'left';
}

export function renderWinScreen(ctx: CanvasRenderingContext2D, score: number, kills: number): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.fillStyle = 'rgba(0,0,0,0.75)';
  ctx.fillRect(0, 0, W, H);
  ctx.font = 'bold 46px monospace';
  ctx.fillStyle = GOLD;
  ctx.textAlign = 'center';
  ctx.fillText('LEVEL COMPLETE!', W / 2, H / 2 - 50);
  ctx.font = '22px monospace';
  ctx.fillStyle = PINK;
  ctx.fillText(`SCORE: ${score}`, W / 2, H / 2);
  ctx.fillText(`KILLS: ${kills}`, W / 2, H / 2 + 36);
  ctx.font = '16px monospace';
  ctx.fillStyle = '#fff';
  ctx.fillText('PRESS ENTER TO CONTINUE', W / 2, H / 2 + 80);
  ctx.textAlign = 'left';
}
