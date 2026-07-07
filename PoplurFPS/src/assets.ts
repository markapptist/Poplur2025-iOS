export interface Assets {
  tiles: (HTMLImageElement | null)[];       // [0]=unused, [1..6]=tile_01..06, [7]=door, [8]=locked door, [9]=pink door
  weapons: Record<string, HTMLImageElement | null>;
  enemies: Record<string, HTMLImageElement | null>;
  pickups: Record<string, HTMLImageElement | null>;
  props:   Record<string, HTMLImageElement | null>;
  hud:     Record<string, HTMLImageElement | null>;
  menu:    Record<string, HTMLImageElement | null>;
  misc:    Record<string, HTMLImageElement | null>;
}

function loadImg(src: string): Promise<HTMLImageElement | null> {
  return new Promise(resolve => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = src;
  });
}

function load(src: string): Promise<HTMLImageElement | null> {
  return loadImg(`/sprites/${src}`);
}

export async function loadAssets(
  onProgress?: (pct: number) => void
): Promise<Assets> {
  const tasks: Array<[string, Promise<HTMLImageElement | null>]> = [
    // environment tiles (1-10)
    ['t1',  load('08_environment_tiles/tile_01.png')],
    ['t2',  load('08_environment_tiles/tile_02.png')],
    ['t3',  load('08_environment_tiles/tile_03.png')],
    ['t4',  load('08_environment_tiles/tile_04.png')],
    ['t5',  load('08_environment_tiles/tile_05.png')],
    ['t6',  load('08_environment_tiles/tile_06.png')],
    ['t7',  load('08_environment_tiles/tile_07.png')],
    ['t8',  load('08_environment_tiles/tile_08.png')],
    // doors
    ['door_normal', load('09_doors_panels/door_panel_01.png')],
    ['door_locked', load('09_doors_panels/door_panel_02.png')],
    ['door_pink',   load('09_doors_panels/door_panel_03.png')],
    // weapons
    ['pistol',   load('02_weapons/pistol.png')],
    ['shotgun',  load('02_weapons/shotgun.png')],
    ['plasma',   load('02_weapons/plasma.png')],
    ['rocket',   load('02_weapons/rocket_launcher.png')],
    ['railgun',  load('02_weapons/railgun.png')],
    // enemies
    ['soldier', load('05_enemies/enemy_soldier_sheet.png')],
    ['heavy',   load('05_enemies/enemy_heavy_sheet.png')],
    ['drone',   load('05_enemies/enemy_drone_sheet.png')],
    ['turret',  load('05_enemies/enemy_turret_sheet.png')],
    ['boss',    load('05_enemies/enemy_boss_sheet.png')],
    // pickups
    ['health',  load('06_pickups/pickup_health.png')],
    ['armor',   load('06_pickups/pickup_armor.png')],
    ['ammo',    load('06_pickups/pickup_ammo.png')],
    ['key_g',   load('06_pickups/key_gold.png')],
    ['key_p',   load('06_pickups/key_pink.png')],
    // props
    ['barrel',  load('07_item_boxes/barrel_pink.png')],
    ['crate',   load('07_item_boxes/crate_pink.png')],
    ['sign',    load('10_decals_signs/poplur_stay_connected_sign.png')],
    ['torch',   load('13_misc/torch.png')],
    ['banner',  load('13_misc/poplur_banner.png')],
    // HUD
    ['hud_face',   load('11_hud_ui/hud_face.png')],
    ['hud_health', load('11_hud_ui/hud_health.png')],
    ['hud_armor',  load('11_hud_ui/hud_armor.png')],
    ['hud_ammo',   load('11_hud_ui/hud_ammo.png')],
    ['hud_slot',   load('11_hud_ui/hud_weapon_slot.png')],
    // menu
    ['main_menu', load('01_title_screen/main_menu_screen.png')],
    // misc
    ['logo', load('13_misc/pixel_p_logo.png')],
    ['levelup_sign', load('10_decals_signs/level_up_sign.png')],
  ];

  const total = tasks.length;
  let done = 0;
  const results = await Promise.all(
    tasks.map(([, p]) => p.then(r => { done++; onProgress?.(done / total); return r; }))
  );

  const get = (name: string) => results[tasks.findIndex(([n]) => n === name)] ?? null;

  return {
    tiles: [
      null,
      get('t1'), get('t2'), get('t3'), get('t4'),
      get('t5'), get('t6'), get('t7'), get('t8'),
      get('door_normal'), get('door_locked'), get('door_pink'),
    ],
    weapons: {
      pistol: get('pistol'), shotgun: get('shotgun'),
      plasma: get('plasma'), rocket: get('rocket'), railgun: get('railgun'),
    },
    enemies: {
      soldier: get('soldier'), heavy: get('heavy'),
      drone: get('drone'), turret: get('turret'), boss: get('boss'),
    },
    pickups: {
      health: get('health'), armor: get('armor'),
      ammo: get('ammo'), key_g: get('key_g'), key_p: get('key_p'),
    },
    props: {
      barrel: get('barrel'), crate: get('crate'),
      sign: get('sign'), torch: get('torch'), banner: get('banner'),
    },
    hud: {
      face: get('hud_face'), health: get('hud_health'),
      armor: get('hud_armor'), ammo: get('hud_ammo'), slot: get('hud_slot'),
    },
    menu: { main_menu: get('main_menu') },
    misc: { logo: get('logo'), levelup_sign: get('levelup_sign') },
  };
}
