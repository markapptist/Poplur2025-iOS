import { MAP_W, MAP_H, WALL_DOOR, WALL_LOCKED, WALL_PINK } from './constants.ts';

export interface DoorState {
  open: number;     // 0 = closed, 1 = fully open
  opening: boolean;
  locked: boolean;
  keyType: 'gold' | 'pink' | null;
}

export interface EntitySpawn {
  type: number;
  x: number;
  y: number;
}

// 0=floor 1-6=wall 7=door 8=locked(gold) 9=locked(pink)
const RAW_MAP: number[][] = [
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,7,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,7,1,1,1,1,1,1,1,1,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,1,0,0,0,3,3,3,3,3,3,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,7,0,0,0,3,0,0,0,0,3,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,1,0,0,0,3,0,0,0,0,3,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,2,2,2,7,1,0,0,0,3,3,7,3,3,3,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,8,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0,1],
  [1,0,0,0,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
  [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
];

import { SPR_SOLDIER, SPR_HEAVY, SPR_DRONE, SPR_BOSS,
         SPR_HEALTH, SPR_ARMOR, SPR_AMMO, SPR_KEY_G,
         SPR_BARREL, SPR_CRATE, SPR_SIGN, SPR_TORCH, SPR_BANNER } from './constants.ts';

export const ENTITY_SPAWNS: EntitySpawn[] = [
  // enemies
  { type: SPR_SOLDIER, x: 11.5, y: 3.5 },
  { type: SPR_SOLDIER, x: 13.5, y: 7.5 },
  { type: SPR_HEAVY,   x: 23.5, y: 7.5 },
  { type: SPR_DRONE,   x: 9.5,  y: 10.5 },
  { type: SPR_SOLDIER, x: 20.5, y: 11.5 },
  { type: SPR_HEAVY,   x: 16.5, y: 16.5 },
  { type: SPR_SOLDIER, x: 8.5,  y: 17.5 },
  { type: SPR_BOSS,    x: 15.5, y: 22.5 },
  // pickups
  { type: SPR_HEALTH, x: 4.5,  y: 1.5 },
  { type: SPR_AMMO,   x: 3.5,  y: 5.5 },
  { type: SPR_HEALTH, x: 14.5, y: 7.5 },
  { type: SPR_ARMOR,  x: 23.5, y: 8.5 },
  { type: SPR_AMMO,   x: 10.5, y: 11.5 },
  { type: SPR_HEALTH, x: 15.5, y: 16.5 },
  { type: SPR_AMMO,   x: 8.5,  y: 15.5 },
  { type: SPR_KEY_G,  x: 24.5, y: 6.5 },   // gold key — unlocks row-13 locked door
  // props
  { type: SPR_BARREL, x: 1.5,  y: 1.5 },
  { type: SPR_BARREL, x: 7.5,  y: 1.5 },
  { type: SPR_TORCH,  x: 8.5,  y: 6.5 },
  { type: SPR_CRATE,  x: 10.5, y: 7.5 },
  { type: SPR_SIGN,   x: 2.5,  y: 10.5 },
  { type: SPR_TORCH,  x: 16.5, y: 13.5 },
  { type: SPR_BANNER, x: 15.5, y: 20.5 },
  { type: SPR_BARREL, x: 5.5,  y: 20.5 },
  { type: SPR_BARREL, x: 24.5, y: 20.5 },
  { type: SPR_CRATE,  x: 7.5,  y: 22.5 },
];

export class Level {
  private map: number[][];
  readonly doors = new Map<string, DoorState>();

  constructor() {
    this.map = RAW_MAP.map(row => [...row]);
    // Register all door cells
    for (let y = 0; y < MAP_H; y++) {
      for (let x = 0; x < MAP_W; x++) {
        const t = this.map[y][x];
        if (t === WALL_DOOR || t === WALL_LOCKED || t === WALL_PINK) {
          this.doors.set(`${x},${y}`, {
            open: 0,
            opening: false,
            locked: t !== WALL_DOOR,
            keyType: t === WALL_LOCKED ? 'gold' : t === WALL_PINK ? 'pink' : null,
          });
        }
      }
    }
  }

  getCell(x: number, y: number): number {
    const ix = Math.floor(x), iy = Math.floor(y);
    if (ix < 0 || iy < 0 || ix >= MAP_W || iy >= MAP_H) return 1;
    return this.map[iy][ix];
  }

  getDoor(x: number, y: number): DoorState | undefined {
    return this.doors.get(`${Math.floor(x)},${Math.floor(y)}`);
  }

  isSolid(x: number, y: number): boolean {
    const t = this.getCell(x, y);
    if (t === 0) return false;
    if (t === WALL_DOOR || t === WALL_LOCKED || t === WALL_PINK) {
      const d = this.getDoor(x, y);
      return !d || d.open < 0.85;
    }
    return true;
  }

  tryOpenDoor(x: number, y: number, hasGold: boolean, hasPink: boolean): boolean {
    const key = `${Math.floor(x)},${Math.floor(y)}`;
    const d = this.doors.get(key);
    if (!d) return false;
    if (d.locked) {
      if (d.keyType === 'gold' && !hasGold) return false;
      if (d.keyType === 'pink' && !hasPink) return false;
    }
    d.opening = true;
    return true;
  }

  update(dt: number): void {
    for (const d of this.doors.values()) {
      if (d.opening && d.open < 1) {
        d.open = Math.min(1, d.open + dt * 1.4);
      }
    }
  }
}
