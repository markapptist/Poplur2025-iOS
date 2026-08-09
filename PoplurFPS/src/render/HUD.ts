import { SCREEN_W, SCREEN_H, WEAPONS, AMMO_TYPES } from '../game/constants.ts';
import type { Player } from '../game/Player.ts';
import type { Assets } from '../assets.ts';
import type { Level } from '../game/Level.ts';
import { MAP_W, MAP_H } from '../game/constants.ts';

const PINK = '#ff4db8';
const GOLD = '#ffd700';
const GREEN = '#00ff88';
const RED   = '#ff3333';

interface HUDStatus {
  objective: string;
  remainingEnemies: number;
  totalEnemies: number;
  hitMarker: number;
  eliminationBanner: number;
  missionBanner: number;
  emptyWeaponBanner: number;
  externalController: boolean;
  bossHealth: { current: number; max: number } | null;
}

function px(n: number, base = SCREEN_W): number { return (n / 640) * base; }

export function renderHUD(
  ctx: CanvasRenderingContext2D,
  player: Player,
  assets: Assets,
  level: Level,
  score: number,
  kills: number,
  gametime: number,
  status: HUDStatus
): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.save();

  // — Bottom bar background —
  const barH = 56;
  // In Poplur the supplied 3D controller and GameCube are real controls over
  // the lower viewport. Lift the game HUD to the edge of that hardware so
  // health, armor, ammo, and keys remain readable instead of sitting behind it.
  const portrait = H > W * 1.25;
  const barY = status.externalController
    ? Math.round(H * (portrait ? 0.52 : 0.12))
    : H - barH;
  ctx.fillStyle = 'rgba(10,0,20,0.88)';
  ctx.fillRect(0, barY, W, barH);
  ctx.strokeStyle = PINK;
  ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(0, barY); ctx.lineTo(W, barY); ctx.stroke();

  const wDef = WEAPONS[player.weapon];
  const ammoLeft = player.ammo[wDef.ammoType];
  const compactHardwareHud = status.externalController && W < 520;

  if (compactHardwareHud) {
    const healthColor = player.health > 50 ? GREEN : player.health > 25 ? '#ffaa00' : RED;
    const cellW = Math.max(72, Math.floor(W * 0.28));
    const ammoX = cellW * 2;

    if (assets.hud.health) ctx.drawImage(assets.hud.health, 8, barY + 7, 16, 16);
    ctx.font = 'bold 16px monospace';
    ctx.fillStyle = healthColor;
    ctx.fillText(String(player.health), 28, barY + 21);
    ctx.fillStyle = '#111';
    ctx.fillRect(8, barY + 31, cellW - 16, 6);
    ctx.fillStyle = healthColor;
    ctx.fillRect(8, barY + 31, (cellW - 16) * (player.health / player.maxHealth), 6);
    ctx.font = 'bold 8px monospace';
    ctx.fillText('HEALTH', 8, barY + 49);

    if (assets.hud.armor) ctx.drawImage(assets.hud.armor, cellW, barY + 7, 16, 16);
    ctx.font = 'bold 16px monospace';
    ctx.fillStyle = '#88aaff';
    ctx.fillText(String(player.armor), cellW + 20, barY + 21);
    ctx.fillStyle = '#111';
    ctx.fillRect(cellW, barY + 31, cellW - 16, 6);
    ctx.fillStyle = '#4488ff';
    ctx.fillRect(cellW, barY + 31, (cellW - 16) * (player.armor / player.maxArmor), 6);
    ctx.font = 'bold 8px monospace';
    ctx.fillText('ARMOR', cellW, barY + 49);

    if (assets.hud.ammo) ctx.drawImage(assets.hud.ammo, ammoX, barY + 7, 16, 16);
    ctx.font = 'bold 16px monospace';
    ctx.fillStyle = ammoLeft > 10 ? GOLD : RED;
    ctx.fillText(String(ammoLeft), ammoX + 20, barY + 21);
    ctx.font = 'bold 9px monospace';
    ctx.fillStyle = GOLD;
    ctx.fillText(wDef.name, ammoX, barY + 37);
    ctx.font = 'bold 8px monospace';
    ctx.fillStyle = 'rgba(255,255,255,.66)';
    ctx.fillText(`WEAPON ${player.weapon + 1}/5`, ammoX, barY + 49);

    let keyX = W - 22;
    if (player.hasKey['gold']) {
      if (assets.pickups.key_g) ctx.drawImage(assets.pickups.key_g, keyX, barY + 31, 16, 16);
      keyX -= 18;
    }
    if (player.hasKey['pink'] && assets.pickups.key_p) {
      ctx.drawImage(assets.pickups.key_p, keyX, barY + 31, 16, 16);
    }
  } else {
    const face = assets.hud.face;
    const faceSize = 46;
    if (face) ctx.drawImage(face, W / 2 - faceSize / 2, barY + (barH - faceSize) / 2, faceSize, faceSize);

    const hlth = assets.hud.health;
    if (hlth) ctx.drawImage(hlth, 8, barY + 6, 18, 18);
    ctx.font = 'bold 22px monospace';
    ctx.fillStyle = player.health > 50 ? GREEN : player.health > 25 ? '#ffaa00' : RED;
    ctx.fillText(String(player.health), 30, barY + 22);
    const hbW = 70, hbH = 6;
    ctx.fillStyle = '#111';
    ctx.fillRect(8, barY + 28, hbW, hbH);
    ctx.fillStyle = player.health > 50 ? GREEN : player.health > 25 ? '#ffaa00' : RED;
    ctx.fillRect(8, barY + 28, hbW * (player.health / player.maxHealth), hbH);

    const armorIco = assets.hud.armor;
    const ax = 90;
    if (armorIco) ctx.drawImage(armorIco, ax, barY + 6, 18, 18);
    ctx.font = 'bold 22px monospace';
    ctx.fillStyle = '#88aaff';
    ctx.fillText(String(player.armor), ax + 22, barY + 22);
    ctx.fillStyle = '#111';
    ctx.fillRect(ax, barY + 28, 70, hbH);
    ctx.fillStyle = '#4488ff';
    ctx.fillRect(ax, barY + 28, 70 * (player.armor / player.maxArmor), hbH);

    const ammoIco = assets.hud.ammo;
    const wx = 175;
    if (ammoIco) ctx.drawImage(ammoIco, wx, barY + 6, 18, 18);
    ctx.font = 'bold 14px monospace';
    ctx.fillStyle = GOLD;
    ctx.fillText(wDef.name, wx, barY + 42);
    ctx.font = 'bold 22px monospace';
    ctx.fillStyle = ammoLeft > 10 ? GOLD : RED;
    ctx.fillText(`${ammoLeft}`, wx + 22, barY + 22);

    const slotX0 = W - 5 * 38 - 8;
    for (let i = 0; i < 5; i++) {
      const sx = slotX0 + i * 38;
      const sy = barY + 4;
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
      const ammo = player.ammo[WEAPONS[i].ammoType];
      ctx.fillStyle = ammo > 0 ? GREEN : RED;
      ctx.fillRect(sx + 26, sy + 3, 5, 5);
    }

    let keyX = W - 5 * 38 - 8 - 28;
    if (player.hasKey['gold']) {
      if (assets.pickups.key_g) ctx.drawImage(assets.pickups.key_g, keyX, barY + 6, 22, 22);
      keyX -= 26;
    }
    if (player.hasKey['pink'] && assets.pickups.key_p) {
      ctx.drawImage(assets.pickups.key_p, keyX, barY + 6, 22, 22);
    }
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
  const killText = `HOSTILES: ${status.remainingEnemies}`;
  ctx.fillText(killText, W - ctx.measureText(killText).width - 8, 15);

  ctx.font = 'bold 9px monospace';
  ctx.fillStyle = 'rgba(255,255,255,0.78)';
  ctx.fillText(`MISSION 01  //  ${status.objective}`, 8, 34);

  if (status.bossHealth) {
    const bossW = Math.min(220, W * 0.48);
    const bossX = W / 2 - bossW / 2;
    const bossY = 46;
    ctx.fillStyle = 'rgba(8,0,18,.82)';
    ctx.fillRect(bossX - 5, bossY - 14, bossW + 10, 27);
    ctx.font = 'bold 9px monospace';
    ctx.fillStyle = '#ffd76c';
    ctx.textAlign = 'center';
    ctx.fillText('ARCADE OVERLORD', W / 2, bossY - 3);
    ctx.fillStyle = '#240515';
    ctx.fillRect(bossX, bossY + 2, bossW, 7);
    ctx.fillStyle = '#ff2d86';
    ctx.fillRect(bossX, bossY + 2, bossW * Math.max(0, status.bossHealth.current / status.bossHealth.max), 7);
    ctx.textAlign = 'left';
  }

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
    ctx.fillRect(0, 0, W, barY);
  }

  // — Crosshair —
  const cx2 = W / 2, cy2 = H / 2;
  ctx.strokeStyle = status.hitMarker > 0 ? `rgba(255,65,130,${Math.min(1, status.hitMarker + .2)})` : 'rgba(255,255,255,0.7)';
  ctx.lineWidth = status.hitMarker > 0 ? 2 : 1;
  const csz = status.hitMarker > 0 ? 12 : 8;
  ctx.beginPath();
  ctx.moveTo(cx2 - csz, cy2); ctx.lineTo(cx2 + csz, cy2);
  ctx.moveTo(cx2, cy2 - csz); ctx.lineTo(cx2, cy2 + csz);
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,100,200,0.8)';
  ctx.fillRect(cx2 - 1, cy2 - 1, 2, 2);

  if (status.eliminationBanner > 0) {
    ctx.globalAlpha = Math.min(1, status.eliminationBanner * 2);
    ctx.font = 'bold 12px monospace';
    ctx.textAlign = 'center';
    ctx.fillStyle = GOLD;
    ctx.fillText(`TARGET CLEARED  //  ${kills}/${status.totalEnemies}`, W / 2, cy2 + 42);
    ctx.textAlign = 'left';
    ctx.globalAlpha = 1;
  }

  if (status.emptyWeaponBanner > 0) {
    ctx.globalAlpha = Math.min(1, status.emptyWeaponBanner * 2);
    ctx.font = 'bold 11px monospace';
    ctx.textAlign = 'center';
    ctx.fillStyle = RED;
    ctx.fillText('NO AMMO  //  CHANGE WEAPON', W / 2, cy2 + 62);
    ctx.textAlign = 'left';
    ctx.globalAlpha = 1;
  }

  if (status.missionBanner > 0) {
    const alpha = Math.min(1, status.missionBanner, (3.6 - status.missionBanner) * 2.5);
    const panelW = Math.min(W - 24, 300);
    const panelY = H * 0.2;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = 'rgba(8,0,18,.82)';
    ctx.fillRect(W / 2 - panelW / 2, panelY, panelW, 48);
    ctx.strokeStyle = PINK;
    ctx.strokeRect(W / 2 - panelW / 2, panelY, panelW, 48);
    ctx.textAlign = 'center';
    ctx.font = 'bold 11px monospace';
    ctx.fillStyle = PINK;
    ctx.fillText('MISSION 01', W / 2, panelY + 17);
    ctx.font = 'bold 12px monospace';
    ctx.fillStyle = '#fff';
    ctx.fillText('CLEAR THE ARCADE', W / 2, panelY + 36);
    ctx.textAlign = 'left';
    ctx.globalAlpha = 1;
  }

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
  ctx.fillText('PRESS START TO RESTART', W / 2, H / 2 + 30);
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
  ctx.fillText('PRESS PAUSE TO RESUME', W / 2, H / 2 + 40);
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
  ctx.fillText('PRESS START TO CONTINUE', W / 2, H / 2 + 80);
  ctx.textAlign = 'left';
}
