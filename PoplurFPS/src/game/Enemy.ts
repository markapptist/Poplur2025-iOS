import { SPR_SOLDIER, SPR_HEAVY, SPR_DRONE, SPR_TURRET, SPR_BOSS } from './constants.ts';
import type { Level } from './Level.ts';
import type { Player } from './Player.ts';

interface EnemyDef {
  hp: number;
  speed: number;
  damage: number;
  fireRate: number;
  score: number;
  sightRange: number;
}

const DEFS: Record<number, EnemyDef> = {
  [SPR_SOLDIER]: { hp: 40,  speed: 2.0, damage: 8,  fireRate: 1.5, score: 100, sightRange: 12 },
  [SPR_HEAVY]:   { hp: 100, speed: 1.0, damage: 15, fireRate: 2.0, score: 300, sightRange: 10 },
  [SPR_DRONE]:   { hp: 25,  speed: 3.0, damage: 5,  fireRate: 0.8, score: 150, sightRange: 14 },
  [SPR_TURRET]:  { hp: 60,  speed: 0.0, damage: 12, fireRate: 1.2, score: 200, sightRange: 12 },
  [SPR_BOSS]:    { hp: 600, speed: 1.2, damage: 25, fireRate: 0.7, score: 2000, sightRange: 20 },
};

export type EnemyState = 'idle' | 'patrol' | 'chase' | 'attack' | 'dead';

export class Enemy {
  x: number; y: number;
  type: number;
  angle = 0;

  hp: number;
  maxHp: number;
  def: EnemyDef;

  state: EnemyState = 'idle';
  fireCooldown = 0;
  idleTimer = 0;
  patrolAngle = 0;
  patrolTimer = 0;

  // For animation
  animFrame = 0;
  animTimer = 0;
  deathTimer = 0;
  hitFlash = 0;

  dead = false;

  constructor(type: number, x: number, y: number) {
    this.type = type;
    this.x = x;
    this.y = y;
    this.def = DEFS[type] ?? DEFS[SPR_SOLDIER];
    this.hp = this.def.hp;
    this.maxHp = this.def.hp;
    this.patrolAngle = Math.random() * Math.PI * 2;
  }

  private hasLineOfSight(player: Player, level: Level): boolean {
    const dx = player.x - this.x;
    const dy = player.y - this.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > this.def.sightRange) return false;
    const steps = Math.ceil(dist * 4);
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      const cx = this.x + dx * t;
      const cy = this.y + dy * t;
      if (level.isSolid(cx, cy)) return false;
    }
    return true;
  }

  update(dt: number, player: Player, level: Level, onDamage: () => void): void {
    if (this.dead) {
      this.deathTimer += dt;
      return;
    }

    this.fireCooldown   = Math.max(0, this.fireCooldown - dt);
    this.hitFlash       = Math.max(0, this.hitFlash - dt * 4);
    this.animTimer     += dt;
    if (this.animTimer > 0.18) { this.animFrame = (this.animFrame + 1) % 4; this.animTimer = 0; }

    const canSee = this.hasLineOfSight(player, level);

    switch (this.state) {
      case 'idle':
        this.idleTimer += dt;
        if (canSee) { this.state = 'chase'; break; }
        if (this.idleTimer > 2.0) { this.state = 'patrol'; this.patrolTimer = 3 + Math.random() * 3; }
        break;

      case 'patrol':
        if (canSee) { this.state = 'chase'; break; }
        this.patrolTimer -= dt;
        if (this.patrolTimer <= 0) { this.state = 'idle'; this.idleTimer = 0; break; }
        // Move in patrol direction
        if (this.def.speed > 0) {
          const nx = this.x + Math.cos(this.patrolAngle) * this.def.speed * dt;
          const ny = this.y + Math.sin(this.patrolAngle) * this.def.speed * dt;
          if (!level.isSolid(nx, ny)) { this.x = nx; this.y = ny; }
          else { this.patrolAngle += Math.PI * (0.5 + Math.random() * 0.5); }
        }
        break;

      case 'chase':
        if (!canSee) { this.state = 'patrol'; this.patrolTimer = 4; break; }
        const dx = player.x - this.x;
        const dy = player.y - this.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        this.angle = Math.atan2(dy, dx);

        const attackDist = this.type === SPR_BOSS ? 4 : 2.5;
        if (dist < attackDist) {
          this.state = 'attack';
        } else if (this.def.speed > 0) {
          const speed = this.def.speed * dt;
          const nx = this.x + (dx / dist) * speed;
          const ny = this.y + (dy / dist) * speed;
          if (!level.isSolid(nx, this.y)) this.x = nx;
          if (!level.isSolid(this.x, ny)) this.y = ny;
        }
        break;

      case 'attack':
        if (!canSee) { this.state = 'chase'; break; }
        const dx2 = player.x - this.x, dy2 = player.y - this.y;
        const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2);
        this.angle = Math.atan2(dy2, dx2);
        const attackDist2 = this.type === SPR_BOSS ? 5 : 3;
        if (dist2 > attackDist2 + 1) { this.state = 'chase'; break; }

        if (this.fireCooldown <= 0) {
          this.fireCooldown = this.def.fireRate;
          onDamage();
        }
        break;
    }
  }

  hit(dmg: number): void {
    if (this.dead) return;
    this.hp -= dmg;
    this.hitFlash = 1;
    if (this.state === 'idle' || this.state === 'patrol') this.state = 'chase';
    if (this.hp <= 0) {
      this.hp = 0;
      this.dead = true;
      this.state = 'dead';
    }
  }

  distTo(px: number, py: number): number {
    const dx = this.x - px, dy = this.y - py;
    return dx * dx + dy * dy;
  }
}
