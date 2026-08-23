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

import { SPR_SOLDIER, SPR_HEAVY, SPR_DRONE, SPR_TURRET, SPR_BOSS,
         SPR_HEALTH, SPR_ARMOR, SPR_AMMO, SPR_KEY_G, SPR_KEY_P,
         SPR_BARREL, SPR_CRATE, SPR_SIGN, SPR_TORCH, SPR_BANNER } from './constants.ts';

// ── Level 1: The Arcade ──────────────────────────────────────────────────
const MAP_1: number[][] = [
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

const SPAWNS_1: EntitySpawn[] = [
  { type: SPR_SOLDIER, x: 11.5, y: 3.5 },
  { type: SPR_SOLDIER, x: 13.5, y: 7.5 },
  { type: SPR_SOLDIER, x: 5.5,  y: 7.5 },
  { type: SPR_SOLDIER, x: 3.5,  y: 10.5 },
  { type: SPR_DRONE,   x: 9.5,  y: 10.5 },
  { type: SPR_DRONE,   x: 18.5, y: 4.5 },
  { type: SPR_HEAVY,   x: 23.5, y: 7.5 },
  { type: SPR_SOLDIER, x: 20.5, y: 11.5 },
  { type: SPR_SOLDIER, x: 14.5, y: 11.5 },
  { type: SPR_HEAVY,   x: 16.5, y: 16.5 },
  { type: SPR_SOLDIER, x: 8.5,  y: 17.5 },
  { type: SPR_DRONE,   x: 24.5, y: 17.5 },
  { type: SPR_SOLDIER, x: 2.5,  y: 16.5 },
  { type: SPR_SOLDIER, x: 12.5, y: 15.5 },
  { type: SPR_BOSS,    x: 15.5, y: 22.5 },
  // pickups
  { type: SPR_HEALTH, x: 4.5,  y: 1.5 },
  { type: SPR_AMMO,   x: 3.5,  y: 5.5 },
  { type: SPR_HEALTH, x: 14.5, y: 7.5 },
  { type: SPR_ARMOR,  x: 23.5, y: 8.5 },
  { type: SPR_AMMO,   x: 10.5, y: 11.5 },
  { type: SPR_HEALTH, x: 15.5, y: 16.5 },
  { type: SPR_AMMO,   x: 8.5,  y: 15.5 },
  { type: SPR_KEY_G,  x: 24.5, y: 6.5 },
  { type: SPR_HEALTH, x: 22.5, y: 16.5 },
  { type: SPR_AMMO,   x: 27.5, y: 15.5 },
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
  { type: SPR_TORCH,  x: 1.5,  y: 14.5 },
  { type: SPR_TORCH,  x: 28.5, y: 14.5 },
];

// ── Level 2: The Neon Depths ─────────────────────────────────────────────
const MAP_2: number[][] = [
  [2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,3,3,3,3,0,0,5,5,0,0,0,7,0,0,0,0,5,5,0,0,3,3,3,3,0,0,2],
  [2,0,0,3,0,0,3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,3,0,0,3,0,0,2],
  [2,0,0,3,0,0,3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,3,0,0,3,0,0,2],
  [2,0,0,3,3,7,3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,3,7,3,3,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,6,6,6,7,6,6,6,6,7,6,6,6,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,2],
  [2,2,2,2,2,7,2,2,2,6,0,0,0,0,0,0,0,0,0,0,6,2,2,2,2,7,2,2,2,2],
  [2,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,6,6,6,6,8,6,6,8,6,6,6,6,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,5,5,7,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,7,5,5,0,0,2],
  [2,0,0,5,0,0,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,0,0,5,0,0,2],
  [2,0,0,5,0,0,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,0,0,5,0,0,2],
  [2,0,0,5,5,5,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,5,5,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,4,4,4,4,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,4,4,9,4,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2],
  [2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2],
];

const SPAWNS_2: EntitySpawn[] = [
  // enemies — 20 hostiles
  { type: SPR_SOLDIER, x: 4.5,  y: 4.5 },
  { type: SPR_SOLDIER, x: 25.5, y: 4.5 },
  { type: SPR_SOLDIER, x: 4.5,  y: 1.5 },
  { type: SPR_SOLDIER, x: 25.5, y: 1.5 },
  { type: SPR_DRONE,   x: 14.5, y: 2.5 },
  { type: SPR_DRONE,   x: 7.5,  y: 7.5 },
  { type: SPR_DRONE,   x: 22.5, y: 7.5 },
  { type: SPR_HEAVY,   x: 12.5, y: 11.5 },
  { type: SPR_HEAVY,   x: 17.5, y: 11.5 },
  { type: SPR_SOLDIER, x: 10.5, y: 13.5 },
  { type: SPR_SOLDIER, x: 19.5, y: 13.5 },
  { type: SPR_TURRET,  x: 15.5, y: 10.5 },
  { type: SPR_SOLDIER, x: 2.5,  y: 13.5 },
  { type: SPR_SOLDIER, x: 27.5, y: 13.5 },
  { type: SPR_HEAVY,   x: 4.5,  y: 19.5 },
  { type: SPR_HEAVY,   x: 25.5, y: 19.5 },
  { type: SPR_DRONE,   x: 14.5, y: 17.5 },
  { type: SPR_SOLDIER, x: 8.5,  y: 22.5 },
  { type: SPR_SOLDIER, x: 21.5, y: 22.5 },
  { type: SPR_BOSS,    x: 14.5, y: 24.5 },
  // pickups
  { type: SPR_HEALTH, x: 1.5,  y: 7.5 },
  { type: SPR_HEALTH, x: 28.5, y: 7.5 },
  { type: SPR_AMMO,   x: 14.5, y: 7.5 },
  { type: SPR_ARMOR,  x: 4.5,  y: 5.5 },
  { type: SPR_ARMOR,  x: 25.5, y: 5.5 },
  { type: SPR_HEALTH, x: 14.5, y: 14.5 },
  { type: SPR_AMMO,   x: 2.5,  y: 17.5 },
  { type: SPR_AMMO,   x: 27.5, y: 17.5 },
  { type: SPR_KEY_G,  x: 1.5,  y: 28.5 },
  { type: SPR_KEY_P,  x: 28.5, y: 28.5 },
  { type: SPR_HEALTH, x: 14.5, y: 22.5 },
  { type: SPR_AMMO,   x: 14.5, y: 27.5 },
  // props
  { type: SPR_TORCH,  x: 9.5,  y: 9.5 },
  { type: SPR_TORCH,  x: 20.5, y: 9.5 },
  { type: SPR_TORCH,  x: 9.5,  y: 15.5 },
  { type: SPR_TORCH,  x: 20.5, y: 15.5 },
  { type: SPR_BARREL, x: 7.5,  y: 16.5 },
  { type: SPR_BARREL, x: 22.5, y: 16.5 },
  { type: SPR_CRATE,  x: 14.5, y: 12.5 },
  { type: SPR_BANNER, x: 14.5, y: 1.5 },
  { type: SPR_SIGN,   x: 1.5,  y: 16.5 },
  { type: SPR_SIGN,   x: 28.5, y: 16.5 },
];

// ── Level 3: The Signal Tower ────────────────────────────────────────────
const MAP_3: number[][] = [
  [3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],
  [3,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,3],
  [3,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,3],
  [3,0,0,0,0,0,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,7,0,0,0,0,0,3],
  [3,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,3],
  [3,3,3,7,3,3,3,0,0,5,5,5,7,5,5,5,5,7,5,5,5,0,0,3,3,3,7,3,3,3],
  [3,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,6,6,6,6,6,6,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,3,3,3,3,8,3,3,0,0,0,0,6,0,0,0,0,6,0,0,0,0,3,3,8,3,3,3,3,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,6,0,0,0,0,6,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,6,6,9,6,6,6,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,4,4,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,4,4,4,0,0,3],
  [3,0,0,4,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,4,0,0,3],
  [3,0,0,4,0,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,4,0,0,3],
  [3,0,0,4,4,7,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,7,4,4,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,2,2,2,2,2,7,2,2,7,2,2,2,2,2,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,3],
  [3,0,0,0,0,0,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0,0,3],
  [3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3],
];

const SPAWNS_3: EntitySpawn[] = [
  // enemies — 25 hostiles
  { type: SPR_SOLDIER, x: 2.5,  y: 2.5 },
  { type: SPR_SOLDIER, x: 27.5, y: 2.5 },
  { type: SPR_SOLDIER, x: 2.5,  y: 6.5 },
  { type: SPR_SOLDIER, x: 27.5, y: 6.5 },
  { type: SPR_DRONE,   x: 14.5, y: 1.5 },
  { type: SPR_DRONE,   x: 5.5,  y: 9.5 },
  { type: SPR_DRONE,   x: 24.5, y: 9.5 },
  { type: SPR_HEAVY,   x: 10.5, y: 7.5 },
  { type: SPR_HEAVY,   x: 19.5, y: 7.5 },
  { type: SPR_TURRET,  x: 14.5, y: 6.5 },
  { type: SPR_TURRET,  x: 14.5, y: 8.5 },
  { type: SPR_SOLDIER, x: 2.5,  y: 13.5 },
  { type: SPR_SOLDIER, x: 27.5, y: 13.5 },
  { type: SPR_HEAVY,   x: 7.5,  y: 16.5 },
  { type: SPR_HEAVY,   x: 22.5, y: 16.5 },
  { type: SPR_DRONE,   x: 14.5, y: 16.5 },
  { type: SPR_SOLDIER, x: 4.5,  y: 19.5 },
  { type: SPR_SOLDIER, x: 25.5, y: 19.5 },
  { type: SPR_SOLDIER, x: 10.5, y: 22.5 },
  { type: SPR_SOLDIER, x: 19.5, y: 22.5 },
  { type: SPR_HEAVY,   x: 10.5, y: 26.5 },
  { type: SPR_HEAVY,   x: 19.5, y: 26.5 },
  { type: SPR_DRONE,   x: 14.5, y: 23.5 },
  { type: SPR_TURRET,  x: 14.5, y: 27.5 },
  { type: SPR_BOSS,    x: 14.5, y: 13.5 },
  // pickups
  { type: SPR_HEALTH, x: 1.5,  y: 1.5 },
  { type: SPR_HEALTH, x: 28.5, y: 1.5 },
  { type: SPR_AMMO,   x: 7.5,  y: 1.5 },
  { type: SPR_AMMO,   x: 22.5, y: 1.5 },
  { type: SPR_ARMOR,  x: 14.5, y: 4.5 },
  { type: SPR_HEALTH, x: 1.5,  y: 10.5 },
  { type: SPR_HEALTH, x: 28.5, y: 10.5 },
  { type: SPR_AMMO,   x: 5.5,  y: 17.5 },
  { type: SPR_AMMO,   x: 24.5, y: 17.5 },
  { type: SPR_ARMOR,  x: 4.5,  y: 20.5 },
  { type: SPR_ARMOR,  x: 25.5, y: 20.5 },
  { type: SPR_KEY_G,  x: 1.5,  y: 17.5 },
  { type: SPR_KEY_P,  x: 28.5, y: 17.5 },
  { type: SPR_HEALTH, x: 14.5, y: 25.5 },
  { type: SPR_AMMO,   x: 14.5, y: 28.5 },
  // props
  { type: SPR_TORCH,  x: 9.5,  y: 5.5 },
  { type: SPR_TORCH,  x: 20.5, y: 5.5 },
  { type: SPR_TORCH,  x: 8.5,  y: 12.5 },
  { type: SPR_TORCH,  x: 21.5, y: 12.5 },
  { type: SPR_BARREL, x: 3.5,  y: 9.5 },
  { type: SPR_BARREL, x: 26.5, y: 9.5 },
  { type: SPR_BANNER, x: 14.5, y: 11.5 },
  { type: SPR_CRATE,  x: 9.5,  y: 25.5 },
  { type: SPR_CRATE,  x: 20.5, y: 25.5 },
  { type: SPR_SIGN,   x: 1.5,  y: 24.5 },
  { type: SPR_SIGN,   x: 28.5, y: 24.5 },
];

// ── Level data table ─────────────────────────────────────────────────────
export interface LevelData {
  map: number[][];
  spawns: EntitySpawn[];
  playerX: number;
  playerY: number;
  missionName: string;
  missionObjective: string;
}

export const LEVELS: LevelData[] = [
  { map: MAP_1, spawns: SPAWNS_1, playerX: 6.45, playerY: 3.5, missionName: 'MISSION 01', missionObjective: 'CLEAR THE ARCADE' },
  { map: MAP_2, spawns: SPAWNS_2, playerX: 14.5, playerY: 1.5, missionName: 'MISSION 02', missionObjective: 'SURVIVE THE NEON DEPTHS' },
  { map: MAP_3, spawns: SPAWNS_3, playerX: 14.5, playerY: 1.5, missionName: 'MISSION 03', missionObjective: 'DESTROY THE SIGNAL TOWER' },
];

// Backwards-compatible export for code that still references ENTITY_SPAWNS
export const ENTITY_SPAWNS = LEVELS[0].spawns;

export class Level {
  private map: number[][];
  readonly doors = new Map<string, DoorState>();

  constructor(levelIndex = 0) {
    const data = LEVELS[levelIndex] ?? LEVELS[0];
    this.map = data.map.map(row => [...row]);
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
