import { SCREEN_W, SCREEN_H, WEAPONS, SPR_BOSS } from './constants.ts';
import { Level, LEVELS } from './Level.ts';
import { Player } from './Player.ts';
import { Enemy, type EnemyTuning } from './Enemy.ts';
import { Pickup, isEnemy, isPickup, isProp, spriteAssetKey } from './Pickups.ts';
import { renderScene, renderWeapon, type RenderSprite } from '../render/Raycaster.ts';
import { renderHUD, renderDeathScreen, renderPauseScreen, renderWinScreen } from '../render/HUD.ts';
import { renderMenuCabinet, renderLoadingScreen, type MenuSelection } from '../render/Menu.ts';
import { consumeInteractCommand, consumePauseCommand, getInput } from '../input.ts';
import { Audio } from '../audio.ts';
import type { Assets } from '../assets.ts';

export type GameState = 'loading' | 'menu' | 'zoom' | 'playing' | 'paused' | 'dead' | 'win' | 'levelclear';

export type DirectorDifficulty = 'easy' | 'medium' | 'hard';

/**
 * The only director-authored values the local game accepts. They remain flavor
 * and bounded balance inputs; physics, hit resolution, rewards and saves stay
 * owned by reviewed game code.
 */
export interface FpsDirectorSession {
  title: string;
  theme: string;
  accentColor: string;
  difficulty: DirectorDifficulty;
  tempo: number;
  powerUps: [string, string];
  rival: string;
  specialMechanic: string;
  source: 'ai' | 'offline';
}

const DIRECTOR_BALANCE: Record<DirectorDifficulty, EnemyTuning> = {
  easy:   { hpMultiplier: 0.82, damageMultiplier: 0.75, fireRateMultiplier: 1.18, scoreMultiplier: 0.9 },
  medium: { hpMultiplier: 1,    damageMultiplier: 1,    fireRateMultiplier: 1,    scoreMultiplier: 1 },
  hard:   { hpMultiplier: 1.22, damageMultiplier: 1.2,  fireRateMultiplier: 0.84, scoreMultiplier: 1.3 },
};

const PROGRESS_KEY = 'poplur.fps.progress.v1';
const MAX_STORED_SCORE = 999_999_999;

export function parseFpsDirectorSession(raw: unknown): FpsDirectorSession | null {
  if (!raw || typeof raw !== 'object') return null;
  const value = raw as Record<string, unknown>;
  if (value.gameId !== undefined && value.gameId !== 'fps') return null;
  if (value.version !== undefined && value.version !== 1) return null;

  const title = directorText(value.title, 40);
  const theme = directorText(value.theme, 70);
  const rival = directorText(value.rival, 40);
  const specialMechanic = directorText(value.specialMechanic, 110);
  if (!title || !theme || !rival || !specialMechanic) return null;
  if (typeof value.accentColor !== 'string' || !/^#[0-9a-f]{6}$/i.test(value.accentColor)) return null;
  if (value.difficulty !== 'easy' && value.difficulty !== 'medium' && value.difficulty !== 'hard') return null;
  if (typeof value.tempo !== 'number' || !Number.isFinite(value.tempo) || value.tempo < 0.8 || value.tempo > 1.2) return null;
  if (!Array.isArray(value.powerUps) || value.powerUps.length !== 2) return null;
  const firstPowerUp = directorText(value.powerUps[0], 28);
  const secondPowerUp = directorText(value.powerUps[1], 28);
  if (!firstPowerUp || !secondPowerUp) return null;
  if (value.source !== 'ai' && value.source !== 'offline') return null;

  return {
    title,
    theme,
    accentColor: value.accentColor.toLowerCase(),
    difficulty: value.difficulty,
    tempo: value.tempo,
    powerUps: [firstPowerUp, secondPowerUp],
    rival,
    specialMechanic,
    source: value.source,
  };
}

const WEAPON_KEYS = ['pistol', 'shotgun', 'plasma', 'rocket', 'railgun'] as const;

export class Game {
  state: GameState = 'loading';
  level = new Level(0);
  player = new Player();
  enemies: Enemy[] = [];
  pickups: Pickup[] = [];
  props:   Pickup[] = [];

  score = 0;
  kills = 0;
  levelKills = 0;
  gameTime = 0;
  currentLevel = 0;
  bestScore = 0;
  wins = 0;

  selectedMenu: MenuSelection = 0;
  menuTick = 0;
  zoomT = 0;

  loadProgress = 0;
  assets: Assets | null = null;

  private menuFirePressed = false;
  private escPressed      = false;

  private muzzleFlash = 0;
  private torchPhase  = 0;
  private hitMarker = 0;
  private eliminationBanner = 0;
  private missionBanner = 0;
  private emptyWeaponBanner = 0;
  private levelClearTimer = 0;
  private totalEnemies: number;
  private pendingDirector: FpsDirectorSession | null = null;
  private activeDirector: FpsDirectorSession | null = null;
  private runFinalized = false;
  private restartArmed = false;

  constructor(public ctx: CanvasRenderingContext2D, private externalController = false) {
    this.totalEnemies = LEVELS[0].spawns.filter(spawn => isEnemy(spawn.type)).length;
    const progress = loadProgress();
    this.bestScore = progress.bestScore;
    this.wins = progress.wins;
  }

  init(assets: Assets): void {
    this.assets = assets;
    this.spawnEntities();
    this.state = 'menu';
  }

  /** Queue a validated session for the next run. Live combat is never retuned. */
  applyDirector(session: FpsDirectorSession): boolean {
    const validated = parseFpsDirectorSession(session);
    if (!validated) return false;
    this.pendingDirector = {
      ...validated,
      powerUps: [validated.powerUps[0], validated.powerUps[1]],
    };
    return true;
  }

  private spawnEntities(): void {
    this.enemies = [];
    this.pickups = [];
    this.props   = [];

    const data = LEVELS[this.currentLevel] ?? LEVELS[0];
    const tuning = this.enemyTuning();
    for (const spawn of data.spawns) {
      if (isEnemy(spawn.type)) {
        this.enemies.push(new Enemy(spawn.type, spawn.x, spawn.y, tuning));
      } else if (isPickup(spawn.type)) {
        this.pickups.push(new Pickup(spawn.type, spawn.x, spawn.y));
      } else if (isProp(spawn.type)) {
        this.props.push(new Pickup(spawn.type, spawn.x, spawn.y));
      }
    }

    this.totalEnemies = this.enemies.length;
  }

  private resetGame(): void {
    this.activeDirector = this.pendingDirector;
    this.currentLevel = 0;
    this.level = new Level(0);
    this.player = new Player();
    this.score = 0; this.kills = 0; this.levelKills = 0; this.gameTime = 0;
    this.runFinalized = false;
    this.restartArmed = false;
    this.hitMarker = 0;
    this.eliminationBanner = 0;
    this.missionBanner = 3.6;
    this.emptyWeaponBanner = 0;
    this.levelClearTimer = 0;
    this.spawnEntities();
  }

  private advanceLevel(): void {
    this.currentLevel++;
    const data = LEVELS[this.currentLevel];
    this.level = new Level(this.currentLevel);
    this.player.x = data.playerX;
    this.player.y = data.playerY;
    this.player.dirX = 0; this.player.dirY = 1;
    this.player.planeX = 0.66; this.player.planeY = 0;
    this.player.hasKey = {};
    this.levelKills = 0;
    this.hitMarker = 0;
    this.eliminationBanner = 0;
    this.missionBanner = 3.6;
    this.emptyWeaponBanner = 0;
    this.levelClearTimer = 0;
    this.spawnEntities();
  }

  update(dt: number): void {
    const rawInput = getInput();
    const input = consumeInteractCommand() ? { ...rawInput, interact: true } : rawInput;
    const pauseCommand = consumePauseCommand();

    switch (this.state) {
      case 'loading':
        break;

      case 'menu': {
        this.menuTick += dt;
        const fire = input.fire || input.interact;

        if (fire && !this.menuFirePressed) { this.state = 'zoom'; this.zoomT = 0; }
        this.menuFirePressed = fire;
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
        this.hitMarker = Math.max(0, this.hitMarker - dt * 7);
        this.eliminationBanner = Math.max(0, this.eliminationBanner - dt);
        this.missionBanner = Math.max(0, this.missionBanner - dt);
        this.emptyWeaponBanner = Math.max(0, this.emptyWeaponBanner - dt);

        // Pause
        if (pauseCommand || (input.escape && !this.escPressed)) {
          this.state = 'paused';
          this.escPressed = input.escape;
          break;
        }
        this.escPressed = input.escape;

        // Player update
        this.player.update(dt, input, this.level);
        this.level.update(dt);

        // Shoot
        if (input.fire && this.player.canFire()) {
          this.doShoot();
        } else if (input.fire && this.player.ammo[WEAPONS[this.player.weapon].ammoType] <= 0) {
          this.emptyWeaponBanner = 0.9;
        }

        // Enemy updates
        for (const e of this.enemies) {
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
          this.finishRun(false);
          this.restartArmed = false;
          this.state = 'dead';
        }

        // Check level clear (boss dead). A simultaneous player death remains a
        // loss rather than being overwritten later in the same frame.
        if (!this.player.dead) {
          const boss = this.enemies.find(e => e.type === SPR_BOSS);
          if (boss?.dead && boss.deathTimer > 1.5) {
            if (this.currentLevel >= LEVELS.length - 1) {
              Audio.levelWin();
              this.finishRun(true);
              this.state = 'win';
            } else {
              Audio.levelWin();
              this.state = 'levelclear';
              this.levelClearTimer = 0;
            }
          }
        }

        break;
      }

      case 'paused':
        if (pauseCommand || (input.escape && !this.escPressed)) {
          this.state = 'playing';
        }
        this.escPressed = input.escape;
        break;

      case 'dead':
        // Player.update owns the death animation timer. It must keep advancing
        // after the state transition even though movement/combat are stopped.
        this.player.update(dt, input, this.level);
        if (!input.interact) this.restartArmed = true;
        if (this.player.deadTimer > 2.0 && this.restartArmed && input.interact) {
          this.state = 'playing';
          this.resetGame();
        }
        break;

      case 'levelclear':
        this.levelClearTimer += dt;
        if (this.levelClearTimer > 3.0 || input.interact) {
          this.advanceLevel();
          this.state = 'playing';
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

    const audioFns = [Audio.pistol, Audio.shotgun, Audio.plasma, Audio.rocket, Audio.railgun];
    audioFns[this.player.weapon]?.();

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
        const ex = e.x - this.player.x, ey = e.y - this.player.y;
        const dot = ex * rdx + ey * rdy;
        if (dot <= 0) continue;
        const dist = Math.sqrt(ex * ex + ey * ey);
        const perp = Math.abs(ex * rdy - ey * rdx);
        if (perp > 0.5) continue;
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
        this.hitMarker = 1;
        Audio.hit();
        if (hitEnemy.dead) {
          Audio.enemyDie();
          this.kills++;
          this.levelKills++;
          this.score += hitEnemy.def.score;
          this.player.score = this.score;
          this.eliminationBanner = 1.15;
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
      case 'win':
      case 'levelclear': {
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
        const boss = this.enemies.find(enemy => enemy.type === SPR_BOSS);
        const levelData = LEVELS[this.currentLevel] ?? LEVELS[0];
        renderHUD(ctx, this.player, this.assets, this.level, this.score, this.levelKills, this.gameTime, {
          missionName: levelData.missionName,
          missionObjective: levelData.missionObjective,
          objective: this.objectiveText(),
          remainingEnemies: this.enemies.filter(enemy => !enemy.dead).length,
          totalEnemies: this.totalEnemies,
          hitMarker: this.hitMarker,
          eliminationBanner: this.eliminationBanner,
          missionBanner: this.missionBanner,
          emptyWeaponBanner: this.emptyWeaponBanner,
          externalController: this.externalController,
          director: this.activeDirector,
          bossHealth: boss && !boss.dead && Math.hypot(boss.x - this.player.x, boss.y - this.player.y) < 12
            ? { current: boss.hp, max: boss.maxHp }
            : null,
        });

        if (this.state === 'paused') renderPauseScreen(ctx);
        if (this.state === 'dead')   renderDeathScreen(ctx, Math.min(1, this.player.deadTimer / 1.5), this.bestScore);
        if (this.state === 'levelclear') this.renderLevelClear(ctx);
        if (this.state === 'win')    renderWinScreen(ctx, this.score, this.kills, this.bestScore, this.wins);
        break;
      }
    }
  }

  private renderLevelClear(ctx: CanvasRenderingContext2D): void {
    const W = SCREEN_W, H = SCREEN_H;
    const alpha = Math.min(1, this.levelClearTimer / 0.5);
    ctx.fillStyle = `rgba(0,0,0,${alpha * 0.65})`;
    ctx.fillRect(0, 0, W, H);

    ctx.save();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    ctx.font = 'bold 28px monospace';
    ctx.fillStyle = `rgba(255,100,200,${alpha})`;
    ctx.fillText(LEVELS[this.currentLevel].missionName, W / 2, H / 2 - 30);

    ctx.font = 'bold 16px monospace';
    ctx.fillStyle = `rgba(255,255,255,${alpha * 0.9})`;
    ctx.fillText('LEVEL CLEAR', W / 2, H / 2 + 10);

    const nextAlpha = this.levelClearTimer > 1.5 ? Math.min(1, (this.levelClearTimer - 1.5) / 0.5) : 0;
    if (nextAlpha > 0) {
      ctx.font = '14px monospace';
      ctx.fillStyle = `rgba(255,255,255,${nextAlpha * 0.7})`;
      ctx.fillText('TAP TO CONTINUE', W / 2, H / 2 + 50);
    }

    ctx.restore();
  }

  private objectiveText(): string {
    const data = LEVELS[this.currentLevel];
    const boss = this.enemies.find(enemy => enemy.type === SPR_BOSS);

    if (!this.player.hasKey['gold'] && this.pickups.some(p => p.type === 203 && !p.collected)) {
      return 'FIND THE GOLD KEY';
    }
    if (!this.player.hasKey['pink'] && this.pickups.some(p => p.type === 204 && !p.collected)) {
      return 'FIND THE PINK KEY';
    }
    if (boss && !boss.dead) return `DEFEAT THE BOSS`;
    return data.missionObjective;
  }

  private enemyTuning(): EnemyTuning {
    if (!this.activeDirector) return DIRECTOR_BALANCE.medium;
    const base = DIRECTOR_BALANCE[this.activeDirector.difficulty];
    const tempo = this.activeDirector.tempo;
    return {
      hpMultiplier: base.hpMultiplier,
      damageMultiplier: base.damageMultiplier,
      // fireRate is an interval: higher tempo means a shorter interval.
      fireRateMultiplier: base.fireRateMultiplier / tempo,
      scoreMultiplier: base.scoreMultiplier * tempo,
    };
  }

  private finishRun(won: boolean): void {
    if (this.runFinalized) return;
    this.runFinalized = true;
    this.bestScore = Math.max(this.bestScore, Math.min(MAX_STORED_SCORE, Math.max(0, Math.round(this.score))));
    if (won) this.wins = Math.min(MAX_STORED_SCORE, this.wins + 1);
    saveProgress(this.bestScore, this.wins);
  }
}

function enemyKey(type: number): string {
  const m: Record<number, string> = { 100:'soldier', 101:'heavy', 102:'drone', 103:'turret', 104:'boss' };
  return m[type] ?? 'soldier';
}

function directorText(value: unknown, maxLength: number): string | null {
  if (typeof value !== 'string') return null;
  const clean = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
  return clean ? clean.slice(0, maxLength) : null;
}

function loadProgress(): { bestScore: number; wins: number } {
  try {
    const raw = JSON.parse(window.localStorage.getItem(PROGRESS_KEY) ?? 'null') as unknown;
    if (!raw || typeof raw !== 'object') return { bestScore: 0, wins: 0 };
    const value = raw as Record<string, unknown>;
    return {
      bestScore: storedCount(value.bestScore),
      wins: storedCount(value.wins),
    };
  } catch {
    return { bestScore: 0, wins: 0 };
  }
}

function saveProgress(bestScore: number, wins: number): void {
  try {
    window.localStorage.setItem(PROGRESS_KEY, JSON.stringify({ bestScore, wins }));
  } catch {
    // Private browsing and locked-down WebViews can disable storage. Gameplay
    // remains fully local and usable; only cross-run records are unavailable.
  }
}

function storedCount(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return Math.min(MAX_STORED_SCORE, Math.max(0, Math.floor(value)));
}
