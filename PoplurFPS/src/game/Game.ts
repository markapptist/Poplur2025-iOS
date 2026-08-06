import { SCREEN_W, SCREEN_H, WEAPONS, SPR_BOSS } from './constants.ts';
import { Level, ENTITY_SPAWNS } from './Level.ts';
import { Player } from './Player.ts';
import { Enemy } from './Enemy.ts';
import { Pickup, isEnemy, isPickup, isProp, spriteAssetKey } from './Pickups.ts';
import { renderScene, renderWeapon, type RenderSprite } from '../render/Raycaster.ts';
import { renderHUD, renderDeathScreen, renderPauseScreen, renderWinScreen } from '../render/HUD.ts';
import { renderMenuCabinet, renderLoadingScreen, type MenuSelection } from '../render/Menu.ts';
import { getInput } from '../input.ts';
import { Audio } from '../audio.ts';
import type { Assets } from '../assets.ts';

export type GameState = 'loading' | 'menu' | 'zoom' | 'playing' | 'paused' | 'dead' | 'win';

const WEAPON_KEYS = ['pistol', 'shotgun', 'plasma', 'rocket', 'railgun'] as const;

export class Game {
  state: GameState = 'loading';
  level = new Level();
  player = new Player();
  enemies: Enemy[] = [];
  pickups: Pickup[] = [];
  props:   Pickup[] = [];

  score = 0;
  kills = 0;
  gameTime = 0;

  selectedMenu: MenuSelection = 0;
  menuTick = 0;
  zoomT = 0;

  loadProgress = 0;
  assets: Assets | null = null;

  private menuUpPressed   = false;
  private menuDownPressed = false;
  private menuFirePressed = false;
  private escPressed      = false;
  private enterPressed    = false;

  private muzzleFlash = 0;
  private torchPhase  = 0;

  constructor(public ctx: CanvasRenderingContext2D) {}

  init(assets: Assets): void {
    this.assets = assets;
    this.spawnEntities();
    this.state = 'menu';
  }

  private spawnEntities(): void {
    this.enemies = [];
    this.pickups = [];
    this.props   = [];

    for (const spawn of ENTITY_SPAWNS) {
      if (isEnemy(spawn.type)) {
        this.enemies.push(new Enemy(spawn.type, spawn.x, spawn.y));
      } else if (isPickup(spawn.type)) {
        this.pickups.push(new Pickup(spawn.type, spawn.x, spawn.y));
      } else if (isProp(spawn.type)) {
        this.props.push(new Pickup(spawn.type, spawn.x, spawn.y));
      }
    }
  }

  private resetGame(): void {
    this.level = new Level();
    this.player = new Player();
    this.score = 0; this.kills = 0; this.gameTime = 0;
    this.spawnEntities();
  }

  update(dt: number): void {
    const input = getInput();

    const escNow   = input.escape;
    const enterNow = input.weapon1 ? false : false; // capture enter separately

    switch (this.state) {
      case 'loading':
        break;

      case 'menu': {
        this.menuTick += dt;
        const up   = input.w || input.left;
        const down = input.s || input.right;
        const fire = input.fire || input.interact;

        if (up  && !this.menuUpPressed)   { this.selectedMenu = 0; }
        if (down && !this.menuDownPressed) { this.selectedMenu = 1; }
        if (fire && !this.menuFirePressed) { this.state = 'zoom'; this.zoomT = 0; }

        // Also accept keyboard Enter / Space
        if (input.interact && !this.menuFirePressed) { this.state = 'zoom'; this.zoomT = 0; }

        this.menuUpPressed   = up;
        this.menuDownPressed = down;
        this.menuFirePressed = fire || input.interact;
        break;
      }

      case 'zoom':
        this.zoomT += dt * 0.85;
        if (this.zoomT >= 1) {
          this.zoomT = 1;
          this.state = 'playing';
          this.resetGame();
        }
        break;

      case 'playing': {
        this.gameTime += dt;
        this.muzzleFlash = Math.max(0, this.muzzleFlash - dt * 12);
        this.torchPhase += dt * 3;

        // Pause
        if (input.escape && !this.escPressed) {
          this.state = 'paused';
          this.escPressed = true;
          break;
        }
        this.escPressed = input.escape;

        // Player update
        this.player.update(dt, input, this.level);
        this.level.update(dt);

        // Shoot
        if (input.fire && this.player.canFire()) {
          this.doShoot();
        }

        // Enemy updates
        for (const e of this.enemies) {
          if (e.dead) continue;
          e.update(dt, this.player, this.level, () => {
            this.player.takeDamage(e.def.damage);
            if (this.player.dead) Audio.playerDie();
            else Audio.hit();
          });
        }

        // Pickup collection
        for (const p of this.pickups) {
          if (p.collected) continue;
          const wasCollected = p.tryCollect(this.player);
          if (wasCollected) {
            if (p.type >= 203) { Audio.key(); this.score += 500; }
            else { Audio.pickup(); this.score += 50; }
          }
        }

        // Check death
        if (this.player.dead) {
          this.state = 'dead';
        }

        // Check win (boss dead)
        const boss = this.enemies.find(e => e.type === SPR_BOSS);
        if (boss?.dead && boss.deathTimer > 1.5) {
          Audio.levelWin();
          this.state = 'win';
        }

        break;
      }

      case 'paused':
        if (input.escape && !this.escPressed) {
          this.state = 'playing';
        }
        this.escPressed = input.escape;
        break;

      case 'dead':
        if (this.player.deadTimer > 2.0 && input.interact) {
          this.state = 'playing';
          this.player.dead = false;
          this.player.health = 50;
          this.player.deadTimer = 0;
          this.player.flashAlpha = 0;
        }
        break;

      case 'win':
        if (input.interact) {
          this.state = 'menu';
          this.zoomT = 0;
        }
        break;
    }
  }

  private doShoot(): void {
    const w = WEAPONS[this.player.weapon];
    this.player.consumeAmmo();
    this.muzzleFlash = 1;

    // Play audio
    const audioFns = [Audio.pistol, Audio.shotgun, Audio.plasma, Audio.rocket, Audio.railgun];
    audioFns[this.player.weapon]?.();

    // Raycast for each projectile
    for (let p = 0; p < w.projectiles; p++) {
      const spread = (Math.random() - 0.5) * w.spread * 2;
      const angle = spread;
      const cos = Math.cos(angle), sin = Math.sin(angle);
      const rdx = this.player.dirX * cos - this.player.dirY * sin;
      const rdy = this.player.dirX * sin + this.player.dirY * cos;

      let closestDist = Infinity;
      let hitEnemy: Enemy | null = null;

      for (const e of this.enemies) {
        if (e.dead) continue;
        // Check if enemy is in roughly the ray direction
        const ex = e.x - this.player.x, ey = e.y - this.player.y;
        const dot = ex * rdx + ey * rdy;
        if (dot <= 0) continue;
        const dist = Math.sqrt(ex * ex + ey * ey);
        // Perpendicular distance from ray
        const perp = Math.abs(ex * rdy - ey * rdx);
        if (perp > 0.5) continue; // miss
        // Wall check
        let wallHit = false;
        const steps = Math.ceil(dist * 3);
        for (let i = 1; i < steps; i++) {
          const t = i / steps;
          if (this.level.isSolid(this.player.x + rdx * dist * t, this.player.y + rdy * dist * t)) {
            wallHit = true; break;
          }
        }
        if (!wallHit && dist < closestDist) {
          closestDist = dist; hitEnemy = e;
        }
      }

      if (hitEnemy) {
        const totalDmg = w.damage + (Math.random() * w.damage * 0.4 - w.damage * 0.2) | 0;
        hitEnemy.hit(totalDmg);
        Audio.hit();
        if (hitEnemy.dead) {
          Audio.enemyDie();
          this.kills++;
          this.score += hitEnemy.def.score;
          this.player.score = this.score;
        }
      }
    }
  }

  render(): void {
    if (!this.assets) return;
    const ctx = this.ctx;
    ctx.imageSmoothingEnabled = false;

    switch (this.state) {
      case 'loading':
        renderLoadingScreen(ctx, this.loadProgress);
        break;

      case 'menu':
        renderMenuCabinet(ctx, this.assets, this.selectedMenu, this.menuTick, 0);
        break;

      case 'zoom':
        renderMenuCabinet(ctx, this.assets, this.selectedMenu, this.menuTick, this.zoomT);
        break;

      case 'playing':
      case 'paused':
      case 'dead':
      case 'win': {
        // Build sprite list
        const renderSprites: RenderSprite[] = [];

        for (const e of this.enemies) {
          if (e.dead && e.deathTimer > 2.5) continue;
          const img = this.assets.enemies[enemyKey(e.type)] ?? null;
          renderSprites.push({
            x: e.x, y: e.y, img,
            scale: e.type === SPR_BOSS ? 1.5 : 1,
            bright: e.hitFlash > 0,
            alpha: e.dead ? Math.max(0, 1 - (e.deathTimer - 0.5) / 2) : 1,
          });
        }

        for (const p of this.pickups) {
          if (p.collected) continue;
          const img = this.assets.pickups[spriteAssetKey(p.type)] ?? null;
          renderSprites.push({ x: p.x, y: p.y, img, scale: 0.65 });
        }

        for (const p of this.props) {
          const img = this.assets.props[spriteAssetKey(p.type)] ?? null;
          const torchScale = 0.5 + Math.sin(this.torchPhase) * 0.04;
          renderSprites.push({
            x: p.x, y: p.y, img,
            scale: spriteAssetKey(p.type) === 'torch' ? torchScale : 0.75,
          });
        }

        renderScene(ctx, this.player, this.level, this.assets, renderSprites);

        // Muzzle flash
        if (this.muzzleFlash > 0) {
          ctx.fillStyle = `rgba(255,200,80,${this.muzzleFlash * 0.18})`;
          ctx.fillRect(0, 0, SCREEN_W, SCREEN_H);
        }

        // Weapon
        const wKey = WEAPON_KEYS[this.player.weapon];
        renderWeapon(ctx, this.player, this.assets.weapons[wKey] ?? null, this.player.weapon === 0 ? 9 : 1);

        // HUD
        renderHUD(ctx, this.player, this.assets, this.level, this.score, this.kills, this.gameTime);

        if (this.state === 'paused') renderPauseScreen(ctx);
        if (this.state === 'dead')   renderDeathScreen(ctx, Math.min(1, this.player.deadTimer / 1.5));
        if (this.state === 'win')    renderWinScreen(ctx, this.score, this.kills);
        break;
      }
    }
  }
}

function enemyKey(type: number): string {
  const m: Record<number, string> = { 100:'soldier', 101:'heavy', 102:'drone', 103:'turret', 104:'boss' };
  return m[type] ?? 'soldier';
}
