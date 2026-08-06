// The render buffer follows the DEVICE aspect instead of a fixed 640x360.
//
// A 16:9 buffer aspect-fitted into a portrait phone is why the game sat in a
// letterbox with a third of the screen black above and below it. Stretching
// that buffer to fill the screen is not the fix (it distorts the raycast), and
// neither is cropping it (the HUD is drawn INSIDE the canvas, so SCORE and
// KILLS would be the first things cut off). The buffer itself has to be the
// right shape, and the projection has to be tied to WIDTH so that a taller
// screen shows MORE of the world rather than a vertically stretched copy of
// the same view — see PROJ_H below.
//
// `let` + a setter: these are read inside functions only, never captured at
// module scope, so every consumer picks the new values up live.
export let SCREEN_W = 640;
export let SCREEN_H = 360;

/**
 * Vertical projection scale, in pixels at unit distance.
 *
 * Wall height used to be `SCREEN_H / dist`, which welds the world's vertical
 * scale to the buffer height — make the buffer taller and everything simply
 * stretches. Deriving it from WIDTH keeps the world's proportions fixed no
 * matter the buffer shape, so extra vertical pixels become extra visible
 * world. The 0.5625 reproduces the original look exactly at 640x360
 * (640 * 0.5625 = 360), so nothing changes on a 16:9 screen.
 */
export let PROJ_H = 360;

/** Pixel budget: keep the fill cost of the original 640x360 buffer. */
const PIXEL_BUDGET = 640 * 360;

/** Size the render buffer for a viewport, preserving world proportions. */
export function setScreenSize(viewW: number, viewH: number): void {
  const aspect = Math.max(0.3, Math.min(3, viewW / Math.max(1, viewH)));
  // w * h = BUDGET and w / h = aspect  =>  w = sqrt(BUDGET * aspect)
  const w = Math.max(240, Math.round(Math.sqrt(PIXEL_BUDGET * aspect)));
  const h = Math.max(160, Math.round(w / aspect));
  SCREEN_W = w;
  SCREEN_H = h;
  // Vertical scale is a COMPROMISE, deliberately.
  //
  // Pure `w * 0.5625` is the geometrically honest answer — world proportions
  // identical at any buffer shape — but on a 0.46-aspect phone it puts a wall
  // at one unit across barely a quarter of the screen, so most of the view is
  // empty ceiling and floor and the level reads as far away. Pure `h` is the
  // old behaviour and stretches everything vertically.
  //
  // Taking the larger of the two keeps 16:9 EXACTLY as it was (640 wide gives
  // 360, which is the height, so nothing changes on a landscape screen) while
  // giving a portrait screen a wall that fills about 72% of the height. There
  // is mild vertical compression on very tall screens; it reads as a normal
  // shooter, which the honest version did not.
  PROJ_H = Math.max(w * 0.5625, h * 0.72);
}
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
  { name: 'SENTINEL', damage: 12, rate: 0.40, spread: 0.02, ammoType: 0, ammoPerShot: 1,  projectiles: 1 },
  { name: 'SHOTGUN', damage: 8,  rate: 0.85, spread: 0.12, ammoType: 1, ammoPerShot: 1,  projectiles: 7 },
  { name: 'PLASMA',  damage: 18, rate: 0.22, spread: 0.01, ammoType: 2, ammoPerShot: 1,  projectiles: 1 },
  { name: 'ROCKET',  damage: 60, rate: 1.10, spread: 0.00, ammoType: 3, ammoPerShot: 1,  projectiles: 1 },
  { name: 'RAILGUN', damage: 80, rate: 1.50, spread: 0.00, ammoType: 4, ammoPerShot: 1,  projectiles: 1 },
] as const;

export const AMMO_TYPES = ['BULLETS', 'SHELLS', 'ENERGY', 'ROCKETS', 'CELLS'];
