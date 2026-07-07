# Codex Prompt: Build the Poplur Retro FPS Arcade Game

You are building a playable retro 1990s arcade-style first-person shooter using the included Poplur sprite folders.

## Goal
Create a small but polished playable FPS prototype inspired by classic raycast shooters. Use the Poplur branding, pink glitter/neon palette, pixel-art HUD, Poplur enemies, pickups, signs, weapon sprites, and the arcade menu screen assets.

## Recommended stack
Build this as an HTML5 game using TypeScript + Vite + Canvas 2D. Do not require a heavy game engine. Keep the code clean and modular.

## Required folders/assets
Use assets from these folders:
- `01_title_screen/main_menu_screen.png` for the title menu.
- `02_weapons/` for first-person weapon sprites.
- `03_projectiles_effects/` for muzzle flashes, bullets, energy blasts, lasers, explosions, portals.
- `04_player/` for player animation reference sprites.
- `05_enemies/` for enemies: soldier, heavy, drone, turret, boss.
- `06_pickups/` for health, armor, ammo, and keys.
- `07_item_boxes/` for crates/barrels.
- `08_environment_tiles/` for wall, floor, and ceiling textures.
- `09_doors_panels/` for doors and panels.
- `10_decals_signs/` for Poplur signs and level signage.
- `11_hud_ui/` for HUD face, health, armor, ammo, weapon slot, minimap.
- `12_minimap/` for minimap icons/tiles.
- `13_misc/` for Poplur logo, banners, torch, barrel.

## Gameplay requirements
1. Start on the Poplur arcade main menu.
2. Press Enter or click START GAME to begin.
3. Implement WASD movement, mouse/touch aiming, and click/tap shooting.
4. Use a raycasting renderer or pseudo-3D corridor renderer with textured walls/floors.
5. Add enemies that patrol and chase the player when visible.
6. Player has health, armor, ammo, score, keys, secrets, kills, and timer.
7. Pickups must work: health restores, armor adds protection, ammo refills, keys unlock doors.
8. Weapons: pistol, shotgun, plasma, rocket launcher, railgun. Let number keys switch weapons.
9. Add muzzle flash, projectiles, hit effects, explosion effects, enemy death animations.
10. Add a minimap in the top-left or HUD bottom area.
11. Include Poplur neon signs on walls and branded crates/barrels as level props.
12. Include at least one locked door and one boss room.
13. Add simple sound hooks with placeholder audio functions.
14. Make it responsive for desktop and mobile.

## Code architecture
Create:
- `src/main.ts` bootstrapping the game.
- `src/assets.ts` for asset loading.
- `src/input.ts` for keyboard, mouse, and touch input.
- `src/game/Game.ts` for game state and loop.
- `src/game/Player.ts`
- `src/game/Enemy.ts`
- `src/game/Weapons.ts`
- `src/game/Pickups.ts`
- `src/game/Level.ts`
- `src/render/Raycaster.ts`
- `src/render/HUD.ts`
- `src/render/Menu.ts`
- `src/styles.css`

## Visual style
Keep everything pixelated: set `image-rendering: pixelated`, disable canvas smoothing, and use a dark purple/magenta neon palette. Add CRT scanlines and subtle screen vignette as CSS overlay.

## Deliverable
Create a complete running project with `package.json`, `index.html`, and all source files. Include clear run instructions:
`npm install`
`npm run dev`

Do not use copyrighted game names or assets. This must be an original Poplur-branded prototype.
