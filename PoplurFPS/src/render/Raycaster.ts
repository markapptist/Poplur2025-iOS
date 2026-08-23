import { SCREEN_W, SCREEN_H, PROJ_H, TEX_SIZE, WALL_DOOR, WALL_LOCKED, WALL_PINK } from '../game/constants.ts';
import type { Level } from '../game/Level.ts';
import type { Player } from '../game/Player.ts';
import type { Assets } from '../assets.ts';

export interface RenderSprite {
  x: number; y: number;
  img: HTMLImageElement | null;
  scale?: number;   // size multiplier (1=default)
  bright?: boolean; // hitflash
  dead?: boolean;
  alpha?: number;
}

export function renderScene(
  ctx: CanvasRenderingContext2D,
  player: Player,
  level: Level,
  assets: Assets,
  sprites: RenderSprite[]
): void {
  const W = SCREEN_W, H = SCREEN_H;
  ctx.imageSmoothingEnabled = false;

  // — Ceiling & floor —
  const ceilGrad = ctx.createLinearGradient(0, 0, 0, H / 2);
  ceilGrad.addColorStop(0, '#1a0832');
  ceilGrad.addColorStop(1, '#3d1260');
  ctx.fillStyle = ceilGrad;
  ctx.fillRect(0, 0, W, H / 2);

  const floorGrad = ctx.createLinearGradient(0, H / 2, 0, H);
  floorGrad.addColorStop(0, '#1a0828');
  floorGrad.addColorStop(1, '#0e0415');
  ctx.fillStyle = floorGrad;
  ctx.fillRect(0, H / 2, W, H / 2);

  ctx.fillStyle = 'rgba(255, 60, 184, 0.12)';
  for (let band = 1; band <= 8; band += 1) {
    const t = band / 8;
    const offset = Math.pow(t, 2.2) * (H / 2);
    ctx.fillRect(0, Math.floor(H / 2 + offset), W, Math.max(1, Math.floor(H / 240)));
  }
  ctx.fillStyle = 'rgba(96, 88, 255, 0.10)';
  for (let band = 1; band <= 5; band += 1) {
    const y = Math.floor((H / 2) * (band / 6));
    ctx.fillRect(0, y, W, Math.max(1, Math.floor(H / 320)));
  }

  // — Walls (DDA raycasting) —
  const zBuffer = new Float64Array(W);
  const posX = player.x, posY = player.y;
  const dirX = player.dirX, dirY = player.dirY;
  const planeX = player.planeX, planeY = player.planeY;

  for (let x = 0; x < W; x++) {
    const cameraX = (2 * x / W) - 1;
    const rayDirX = dirX + planeX * cameraX;
    const rayDirY = dirY + planeY * cameraX;

    let mapX = Math.floor(posX);
    let mapY = Math.floor(posY);

    const deltaDistX = rayDirX === 0 ? 1e30 : Math.abs(1 / rayDirX);
    const deltaDistY = rayDirY === 0 ? 1e30 : Math.abs(1 / rayDirY);

    let stepX: number, stepY: number;
    let sideDistX: number, sideDistY: number;

    if (rayDirX < 0) { stepX = -1; sideDistX = (posX - mapX) * deltaDistX; }
    else             { stepX =  1; sideDistX = (mapX + 1 - posX) * deltaDistX; }
    if (rayDirY < 0) { stepY = -1; sideDistY = (posY - mapY) * deltaDistY; }
    else             { stepY =  1; sideDistY = (mapY + 1 - posY) * deltaDistY; }

    let hit = false, side = 0;
    let perpWallDist = 0;
    let wallType = 0;
    let wallX = 0;
    let isDoor = false;
    let doorOpenAmt = 0;

    while (!hit) {
      if (sideDistX < sideDistY) { sideDistX += deltaDistX; mapX += stepX; side = 0; }
      else                        { sideDistY += deltaDistY; mapY += stepY; side = 1; }

      const tile = level.getCell(mapX, mapY);
      if (tile === 0) continue;

      if (tile === WALL_DOOR || tile === WALL_LOCKED || tile === WALL_PINK) {
        // Midstep door check
        let midDist: number;
        if (side === 0) midDist = sideDistX - deltaDistX * 0.5;
        else            midDist = sideDistY - deltaDistY * 0.5;

        let dwx: number;
        if (side === 0) dwx = posY + midDist * rayDirY;
        else            dwx = posX + midDist * rayDirX;
        dwx -= Math.floor(dwx);

        const door = level.getDoor(mapX, mapY);
        const openAmt = door?.open ?? 0;
        if (dwx < openAmt) continue; // ray passes through open gap

        // Hit door face
        perpWallDist = midDist;
        wallX = dwx;
        wallType = tile;
        isDoor = true;
        doorOpenAmt = openAmt;
        hit = true;
        continue;
      }

      // Normal wall
      if (side === 0) perpWallDist = sideDistX - deltaDistX;
      else            perpWallDist = sideDistY - deltaDistY;

      if (side === 0) wallX = posY + perpWallDist * rayDirY;
      else            wallX = posX + perpWallDist * rayDirX;
      wallX -= Math.floor(wallX);
      if (side === 0 && rayDirX > 0) wallX = 1 - wallX;
      if (side === 1 && rayDirY < 0) wallX = 1 - wallX;

      wallType = tile;
      hit = true;
    }

    zBuffer[x] = perpWallDist;

    if (perpWallDist <= 0) continue;
    const lineH  = Math.abs(PROJ_H / perpWallDist) | 0;
    const drawS  = Math.max(0, (H / 2 - lineH / 2) | 0);
    const drawE  = Math.min(H - 1, (H / 2 + lineH / 2) | 0);
    const drawH  = drawE - drawS;
    if (drawH <= 0) continue;

    // Select texture
    const texImg = getTexture(wallType, isDoor, assets);
    let texX = (wallX * TEX_SIZE) | 0;
    if (isDoor) texX = ((wallX - doorOpenAmt) * TEX_SIZE) | 0;
    texX = Math.max(0, Math.min(TEX_SIZE - 1, texX));

    if (texImg) {
      const th = texImg.naturalHeight || TEX_SIZE;
      ctx.drawImage(texImg, texX, 0, 1, th, x, drawS, 1, drawH);
    } else {
      // Fallback solid color
      ctx.fillStyle = wallColor(wallType);
      ctx.fillRect(x, drawS, 1, drawH);
    }

    // Distance fog + side shadow
    const fog = Math.min(0.82, perpWallDist / 28);
    const sideDark = side === 1 ? 0.18 : 0;
    ctx.fillStyle = `rgba(0,0,0,${Math.min(0.90, fog + sideDark)})`;
    ctx.fillRect(x, drawS, 1, drawH);
  }

  // — Sprites —
  renderSprites(ctx, player, sprites, zBuffer, W, H);
}

function getTexture(wallType: number, isDoor: boolean, assets: Assets): HTMLImageElement | null {
  if (isDoor || wallType === WALL_DOOR)   return assets.tiles[9]  ?? null;
  if (wallType === WALL_LOCKED)           return assets.tiles[10] ?? null;
  if (wallType === WALL_PINK)             return assets.tiles[11] ?? null;
  return assets.tiles[wallType] ?? null;
}

function wallColor(type: number): string {
  const colors = ['#000','#4a1060','#1a3a6a','#6a2040','#2a1a5a','#5a3010','#103a30','#8a2060'];
  return colors[type % colors.length];
}

function renderSprites(
  ctx: CanvasRenderingContext2D,
  player: Player,
  sprites: RenderSprite[],
  zBuffer: Float64Array,
  W: number, H: number
): void {
  // Sort back to front
  const sorted = sprites
    .map(s => ({ s, dist: (s.x - player.x) ** 2 + (s.y - player.y) ** 2 }))
    .sort((a, b) => b.dist - a.dist);

  const invDet = 1 / (player.planeX * player.dirY - player.dirX * player.planeY);

  for (const { s } of sorted) {
    if (!s.img) continue;
    const alpha = s.alpha ?? 1;
    if (alpha <= 0) continue;

    const sprX = s.x - player.x;
    const sprY = s.y - player.y;
    const tx = invDet * (player.dirY * sprX - player.dirX * sprY);
    const ty = invDet * (-player.planeY * sprX + player.planeX * sprY);
    if (ty <= 0.05) continue;

    const scale = s.scale ?? 1;
    const sprH = Math.abs((PROJ_H / ty) * scale) | 0;
    const sprW = sprH; // assume 1:1 ratio; adjust if needed
    const scrX = ((W / 2) * (1 + tx / ty)) | 0;

    const startX = Math.max(0, (scrX - sprW / 2) | 0);
    const endX   = Math.min(W - 1, (scrX + sprW / 2) | 0);
    const startY = Math.max(0, (H / 2 - sprH / 2) | 0);
    const endY   = Math.min(H - 1, (H / 2 + sprH / 2) | 0);

    const iw = s.img.naturalWidth  || 64;
    const ih = s.img.naturalHeight || 64;

    ctx.save();
    if (alpha < 1) ctx.globalAlpha = alpha;

    for (let sx = startX; sx < endX; sx++) {
      if (zBuffer[sx] <= ty) continue; // behind wall
      const texCol = ((sx - (scrX - sprW / 2)) / sprW * iw) | 0;
      ctx.drawImage(s.img, texCol, 0, 1, ih, sx, startY, 1, endY - startY);
    }

    // Hit flash
    if (s.bright && s.bright) {
      ctx.fillStyle = 'rgba(255,80,80,0.55)';
      ctx.fillRect(startX, startY, endX - startX, endY - startY);
    }

    ctx.restore();
  }
}

export function renderWeapon(
  ctx: CanvasRenderingContext2D,
  player: Player,
  weaponImg: HTMLImageElement | null,
  frames = 1
): void {
  if (!weaponImg) return;
  const W = SCREEN_W, H = SCREEN_H;
  const frameCount = Math.max(1, frames);
  const iw = weaponImg.naturalWidth / frameCount;
  const ih = weaponImg.naturalHeight;
  // Size the viewmodel from WIDTH, not buffer height. `H * 0.76` was fine when
  // the buffer was always 640x360, but once the buffer follows a portrait
  // screen H roughly doubles and the gun swallowed half the view. Width is what
  // a held weapon should track — 0.76 * 360 / 640 reproduces the old size
  // exactly at 16:9, so nothing changes on a landscape screen.
  const scale = (W * 0.4275) / ih;
  const dw = iw * scale, dh = ih * scale;

  const bobY = Math.sin(player.bobPhase) * 6;
  const bobX = Math.cos(player.bobPhase * 0.5) * 3;
  const kickY = player.weaponKick * 30;

  const dx = W / 2 - dw / 2 + bobX;
  const dy = H - dh + bobY + kickY + 8;

  ctx.imageSmoothingEnabled = false;
  // The middle Sentinel frame is edge-on and reads as a grey line. The
  // supplied three-quarter frame keeps the actual gun body visible.
  const frame = frameCount > 1 ? Math.min(1, frameCount - 1) : 0;
  ctx.drawImage(weaponImg, frame * iw, 0, iw, ih, dx, dy, dw, dh);
}
