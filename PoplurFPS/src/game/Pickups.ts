import { SPR_HEALTH, SPR_ARMOR, SPR_AMMO, SPR_KEY_G, SPR_KEY_P,
         SPR_BARREL, SPR_CRATE, SPR_SIGN, SPR_TORCH, SPR_BANNER } from './constants.ts';
import type { Player } from './Player.ts';

export class Pickup {
  x: number; y: number;
  type: number;
  collected = false;
  bobPhase = Math.random() * Math.PI * 2;

  constructor(type: number, x: number, y: number) {
    this.type = type;
    this.x = x;
    this.y = y;
  }

  tryCollect(player: Player): boolean {
    if (this.collected) return false;
    const dx = this.x - player.x, dy = this.y - player.y;
    if (dx * dx + dy * dy > 0.6 * 0.6) return false;

    switch (this.type) {
      case SPR_HEALTH:
        if (player.health >= player.maxHealth) return false;
        player.health = Math.min(player.maxHealth, player.health + 25);
        break;
      case SPR_ARMOR:
        if (player.armor >= player.maxArmor) return false;
        player.armor = Math.min(player.maxArmor, player.armor + 50);
        break;
      case SPR_AMMO:
        player.ammo[0] = Math.min(300, player.ammo[0] + 50);
        player.ammo[1] = Math.min(50,  player.ammo[1] + 10);
        player.ammo[2] = Math.min(150, player.ammo[2] + 30);
        player.ammo[3] = Math.min(20,  player.ammo[3] + 3);
        player.ammo[4] = Math.min(30,  player.ammo[4] + 5);
        break;
      case SPR_KEY_G:
        player.hasKey['gold'] = true;
        break;
      case SPR_KEY_P:
        player.hasKey['pink'] = true;
        break;
      default:
        return false; // props don't collect
    }
    this.collected = true;
    return true;
  }
}

export function isEnemy(type: number): boolean {
  return type >= 100 && type < 200;
}

export function isPickup(type: number): boolean {
  return type >= 200 && type < 300;
}

export function isProp(type: number): boolean {
  return type >= 300;
}

export function spriteAssetKey(type: number): string {
  const map: Record<number, string> = {
    [SPR_HEALTH]: 'health',
    [SPR_ARMOR]:  'armor',
    [SPR_AMMO]:   'ammo',
    [SPR_KEY_G]:  'key_g',
    [SPR_KEY_P]:  'key_p',
    [SPR_BARREL]: 'barrel',
    [SPR_CRATE]:  'crate',
    [SPR_SIGN]:   'sign',
    [SPR_TORCH]:  'torch',
    [SPR_BANNER]: 'banner',
  };
  return map[type] ?? 'barrel';
}
