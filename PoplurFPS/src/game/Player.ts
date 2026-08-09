import { MOVE_SPEED, ROT_SPEED, MOUSE_SENS, PLANE_LEN, PLAYER_R, INTERACT_D, WEAPONS } from './constants.ts';
import type { Level } from './Level.ts';
import type { InputState } from '../input.ts';
import { consumeMouseDX } from '../input.ts';

export class Player {
  // Begin at the first arcade door rather than at the back of an empty hall.
  // The opening frame now gives the player a clear objective and a useful ACT
  // button immediately, especially on a tall phone screen.
  x = 6.45; y = 3.5;
  dirX = 1; dirY = 0;
  planeX = 0; planeY = PLANE_LEN;

  health = 100; maxHealth = 100;
  armor  = 0;   maxArmor  = 100;
  ammo   = [100, 20, 50, 5, 10];  // bullets, shells, energy, rockets, cells
  weapon = 0;   // current weapon index (0-4)
  hasKey: Record<string, boolean> = {};

  score = 0;
  kills = 0;

  bobPhase   = 0;
  bobActive  = false;
  flashAlpha = 0;   // red damage flash
  weaponKick = 0;   // recoil animation (0-1)

  fireCooldown = 0;
  interactCooldown = 0;

  dead = false;
  deadTimer = 0;

  private tryMove(level: Level, nx: number, ny: number): void {
    if (!level.isSolid(nx, this.y)) this.x = nx;
    if (!level.isSolid(this.x, ny)) this.y = ny;
  }

  update(dt: number, input: InputState, level: Level): void {
    if (this.dead) {
      this.deadTimer += dt;
      return;
    }

    // Rotation — keyboard
    if (input.left || input.right) {
      const turn = (input.right ? 1 : -1) * ROT_SPEED * dt;
      this.rotate(turn);
    }

    // Rotation — mouse
    const mdx = consumeMouseDX();
    if (mdx !== 0) this.rotate(mdx * MOUSE_SENS);

    // Movement.
    //
    // Keyboard keys are full-deflection axes; the touch stick supplies real
    // analog values. Resolving both into one pair of axes means a thumb half
    // way out walks at half speed and a diagonal is a genuine diagonal, rather
    // than the four-way on/off pad this used to be — and it keeps one movement
    // path for every input device instead of two that can drift apart.
    const keyFwd = (input.w ? 1 : 0) + (input.s ? -1 : 0);
    const keyStrafe = (input.d ? 1 : 0) + (input.a ? -1 : 0);
    let axFwd = input.axisFwd !== 0 ? input.axisFwd : keyFwd;
    let axStrafe = input.axisStrafe !== 0 ? input.axisStrafe : keyStrafe;

    // Pushing the stick corner-to-corner must not be faster than straight on.
    const mag = Math.hypot(axFwd, axStrafe);
    if (mag > 1) { axFwd /= mag; axStrafe /= mag; }

    const speed = MOVE_SPEED * dt;
    const strafeSpeed = speed * 0.8;
    let moving = false;

    if (axFwd !== 0) {
      this.tryMove(level, this.x + this.dirX * speed * axFwd, this.y + this.dirY * speed * axFwd);
      moving = true;
    }
    if (axStrafe !== 0) {
      // +strafe is to the player's right.
      this.tryMove(level,
        this.x - this.dirY * strafeSpeed * axStrafe,
        this.y + this.dirX * strafeSpeed * axStrafe);
      moving = true;
    }

    // Weapon bob
    this.bobActive = moving;
    if (moving) this.bobPhase += dt * 6;
    else this.bobPhase *= 0.85;

    // Cooldowns
    this.fireCooldown       = Math.max(0, this.fireCooldown - dt);
    this.interactCooldown   = Math.max(0, this.interactCooldown - dt);
    this.flashAlpha         = Math.max(0, this.flashAlpha - dt * 3);
    this.weaponKick         = Math.max(0, this.weaponKick - dt * 8);

    // Weapon switch
    if (input.weapon1) this.weapon = 0;
    if (input.weapon2) this.weapon = 1;
    if (input.weapon3) this.weapon = 2;
    if (input.weapon4) this.weapon = 3;
    if (input.weapon5) this.weapon = 4;

    // Interact
    if (input.interact && this.interactCooldown <= 0) {
      this.interactCooldown = 0.4;
      // Scan forward for a door
      for (let step = 0.5; step <= INTERACT_D; step += 0.5) {
        const cx = this.x + this.dirX * step;
        const cy = this.y + this.dirY * step;
        const cell = level.getCell(cx, cy);
        if (cell === 7 || cell === 8 || cell === 9) {
          level.tryOpenDoor(cx, cy, !!this.hasKey['gold'], !!this.hasKey['pink']);
          break;
        }
      }
    }
  }

  rotate(angle: number): void {
    const cos = Math.cos(angle), sin = Math.sin(angle);
    const ox = this.dirX, oy = this.dirY;
    this.dirX   = ox * cos - oy * sin;
    this.dirY   = ox * sin + oy * cos;
    const px = this.planeX, py = this.planeY;
    this.planeX = px * cos - py * sin;
    this.planeY = px * sin + py * cos;
  }

  takeDamage(dmg: number): void {
    if (this.dead) return;
    // Armor absorbs 33%
    const armorAbsorb = Math.min(this.armor, Math.floor(dmg * 0.33));
    this.armor -= armorAbsorb;
    this.health -= (dmg - armorAbsorb);
    this.flashAlpha = Math.min(1, this.flashAlpha + 0.4);
    if (this.health <= 0) {
      this.health = 0;
      this.dead = true;
    }
  }

  canFire(): boolean {
    const w = WEAPONS[this.weapon];
    return this.fireCooldown <= 0 && this.ammo[w.ammoType] >= w.ammoPerShot;
  }

  consumeAmmo(): void {
    const w = WEAPONS[this.weapon];
    this.ammo[w.ammoType] = Math.max(0, this.ammo[w.ammoType] - w.ammoPerShot);
    this.fireCooldown = w.rate;
    this.weaponKick = 1;
  }
}
