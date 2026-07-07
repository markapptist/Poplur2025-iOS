export const SCREEN_W    = 640;
export const SCREEN_H    = 360;
export const MAP_W       = 30;
export const MAP_H       = 30;
export const TEX_SIZE    = 64;
export const MOVE_SPEED  = 3.5;
export const ROT_SPEED   = 2.0;
export const MOUSE_SENS  = 0.0025;
export const PLANE_LEN   = 0.66;   // half-FOV ≈ 33° each side → total ~66°
export const PLAYER_R    = 0.22;
export const INTERACT_D  = 1.4;
export const MAX_DIST    = 18;

// Wall tile types
export const WALL_NONE   = 0;
export const WALL_1      = 1;
export const WALL_2      = 2;
export const WALL_3      = 3;
export const WALL_4      = 4;
export const WALL_5      = 5;
export const WALL_6      = 6;
export const WALL_DOOR   = 7;   // normal door
export const WALL_LOCKED = 8;   // locked door (gold key)
export const WALL_PINK   = 9;   // locked door (pink key)

// Sprite types (for entity list)
export const SPR_SOLDIER = 100;
export const SPR_HEAVY   = 101;
export const SPR_DRONE   = 102;
export const SPR_TURRET  = 103;
export const SPR_BOSS    = 104;
export const SPR_HEALTH  = 200;
export const SPR_ARMOR   = 201;
export const SPR_AMMO    = 202;
export const SPR_KEY_G   = 203;
export const SPR_KEY_P   = 204;
export const SPR_BARREL  = 300;
export const SPR_CRATE   = 301;
export const SPR_SIGN    = 302;
export const SPR_TORCH   = 303;
export const SPR_BANNER  = 304;

// Weapon IDs
export const WPN_PISTOL  = 0;
export const WPN_SHOTGUN = 1;
export const WPN_PLASMA  = 2;
export const WPN_ROCKET  = 3;
export const WPN_RAIL    = 4;

export const WEAPONS = [
  { name: 'PISTOL',  damage: 12, rate: 0.40, spread: 0.02, ammoType: 0, ammoPerShot: 1,  projectiles: 1 },
  { name: 'SHOTGUN', damage: 8,  rate: 0.85, spread: 0.12, ammoType: 1, ammoPerShot: 1,  projectiles: 7 },
  { name: 'PLASMA',  damage: 18, rate: 0.22, spread: 0.01, ammoType: 2, ammoPerShot: 1,  projectiles: 1 },
  { name: 'ROCKET',  damage: 60, rate: 1.10, spread: 0.00, ammoType: 3, ammoPerShot: 1,  projectiles: 1 },
  { name: 'RAILGUN', damage: 80, rate: 1.50, spread: 0.00, ammoType: 4, ammoPerShot: 1,  projectiles: 1 },
] as const;

export const AMMO_TYPES = ['BULLETS', 'SHELLS', 'ENERGY', 'ROCKETS', 'CELLS'];
