const IOS = 'assets/';
const CLAY = '../';

const ios = (set, file) => `${IOS}${set}.imageset/${file}`;
const clay = file => `${CLAY}${file}`;
const svgIcon = svg => `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;

const A = {
  logo: ios('logo_rubber', 'logo_rubber.png'),
  logoClay: ios('logo_clay', 'logo_clay.png'),
  cube: clay('clay_cube.png'),
  pin: clay('clay_pin.png'),
  up: ios('feed_channel_up_unpressed', 'up_unpressed.png'),
  ch: ios('feed_channel_ch_unpressed', 'ch_unpressed.png'),
  down: ios('feed_channel_down_unpressed', 'down_unpressed.png'),
  statsSphere: ios('stats_sphere', 'stats_sphere.png'),
  statsPosts: ios('stats_ic_posts', 'stats_ic_posts.png'),
  statsGoal: ios('stats_ic_goal', 'stats_ic_goal.png'),
  statsOrbit: ios('stats_tr_orbit', 'stats_tr_orbit.png'),
  storeHero: ios('store_hero', 'store_hero.png'),
  storeBag: ios('store_ic_bag', 'store_ic_bag.png'),
  storeFilter: ios('store_ic_filter', 'store_ic_filter.png'),
  storeCard: ios('store_p_card', 'store_p_card.png'),
  storeCube: ios('store_p_cube', 'store_p_cube.png'),
  store5: ios('store_p_5km', 'store_p_5km.png'),
  store25: ios('store_p_25km', 'store_p_25km.png'),
  createCredits: ios('create_ic_credits', 'create_ic_credits.png'),
  createP: ios('create_ic_p', 'create_ic_p.png'),
};

const H = {
  tvGuide: ios('HoldMenu_TVGuide', 'HoldMenu_TVGuide.png'),
  news: ios('HoldMenu_News', 'HoldMenu_News.png'),
  music: ios('HoldMenu_Music', 'music.png'),
  chat: ios('HoldMenu_Chat', 'chat_messages.png'),
  like: svgIcon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><radialGradient id="g" cx="34%" cy="25%" r="75%"><stop offset="0" stop-color="#ff9fcd"/><stop offset=".55" stop-color="#f72686"/><stop offset="1" stop-color="#9a0e4f"/></radialGradient></defs><rect width="96" height="96" rx="24" fill="#11050d"/><path d="M48 75C30 60 18 49 18 35c0-10 7-17 17-17 6 0 11 3 13 8 2-5 7-8 13-8 10 0 17 7 17 17 0 14-12 25-30 40z" fill="url(#g)" stroke="#ffb5d6" stroke-width="3"/></svg>'),
  cc: svgIcon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><rect width="96" height="96" rx="24" fill="#08080a"/><rect x="14" y="24" width="68" height="48" rx="12" fill="#15191f" stroke="#4dff40" stroke-width="4"/><text x="48" y="57" text-anchor="middle" font-family="Arial Black,Arial" font-size="25" fill="#4dff40">CC</text></svg>'),
  cameraRoll: ios('HoldMenu_CameraRoll', 'HoldMenu_CameraRoll.png'),
  create: ios('HoldMenu_Create', 'HoldMenu_Create.png'),
  home: ios('HoldMenu_Home', 'home_star.png'),
  store: ios('HoldMenu_Store', 'shop.png'),
  games: svgIcon('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><defs><linearGradient id="g" x1="13" y1="15" x2="82" y2="82"><stop offset="0" stop-color="#ff5caf"/><stop offset=".48" stop-color="#7c3aed"/><stop offset="1" stop-color="#37e6ff"/></linearGradient></defs><rect width="96" height="96" rx="24" fill="#08040e"/><path d="M29 39h38c10 0 17 8 17 18v7c0 7-5 12-11 12-5 0-8-3-12-8H35c-4 5-7 8-12 8-6 0-11-5-11-12v-7c0-10 7-18 17-18z" fill="url(#g)" stroke="#ffd5ee" stroke-width="3"/><path d="M28 52v14M21 59h14" stroke="#110513" stroke-width="5" stroke-linecap="round"/><circle cx="61" cy="56" r="4" fill="#fff"/><circle cx="72" cy="64" r="4" fill="#fff"/><path d="M41 39l4-11h6l4 11" fill="none" stroke="#ffd5ee" stroke-width="3" stroke-linecap="round"/></svg>'),
  locate: ios('HoldMenu_Search', 'HoldMenu_Search.png'),
  post: ios('HoldMenu_Create', 'HoldMenu_Create.png'),
  tour: ios('HoldMenu_Tour', 'HoldMenu_Tour.png'),
  settings: ios('HoldMenu_Settings', 'settings.png'),
  stats: ios('HoldMenu_Stats', 'HoldMenu_Stats.png'),
  notifications: ios('HoldMenu_Notifications', 'notifications.png'),
  phone: ios('HoldMenu_Phone', 'smartphone.png'),
};

const createIcon = name => ios(`create_ic_${name}`, `create_ic_${name}.png`);
const channelIcon = name => ios(name, `${name}.png`);

const phoneColorways = [
  ['Silver', 'poplur_bling_phone_01_silver_diamond', 'poplur_bling_phone_01_silver_diamond.png', 'poplur_phone_bootup_silver_diamond', 'poplur_silver_diamond_boot_spritesheet_4x4.png'],
  ['Gold', 'poplur_bling_phone_02_champagne_gold', 'poplur_bling_phone_02_champagne_gold.png', 'poplur_phone_bootup_champagne_gold', 'poplur_champagne_gold_boot_spritesheet_4x4.png'],
  ['Rose', 'poplur_bling_phone_03_rose_gold_pink', 'poplur_bling_phone_03_rose_gold_pink.png', 'poplur_phone_bootup_rose_gold_pink', 'poplur_rose_gold_pink_boot_spritesheet_4x4.png'],
  ['Ruby', 'poplur_bling_phone_04_ruby_red', 'poplur_bling_phone_04_ruby_red.png', 'poplur_phone_bootup_ruby_red', 'poplur_ruby_red_boot_spritesheet_4x4.png'],
  ['Blue', 'poplur_bling_phone_05_sapphire_blue', 'poplur_bling_phone_05_sapphire_blue.png', 'poplur_phone_bootup_sapphire_blue', 'poplur_sapphire_blue_boot_spritesheet_4x4.png'],
  ['Green', 'poplur_bling_phone_06_emerald_green', 'poplur_bling_phone_06_emerald_green.png', 'poplur_phone_bootup_emerald_green', 'poplur_emerald_green_boot_spritesheet_4x4.png'],
  ['Purple', 'poplur_bling_phone_07_amethyst_purple', 'poplur_bling_phone_07_amethyst_purple.png', 'poplur_phone_bootup_amethyst_purple', 'poplur_amethyst_purple_boot_spritesheet_4x4.png'],
  ['Onyx', 'poplur_bling_phone_08_jet_black_onyx', 'poplur_bling_phone_08_jet_black_onyx.png', 'poplur_phone_bootup_jet_black_onyx', 'poplur_jet_black_onyx_boot_spritesheet_4x4.png'],
  ['Aqua', 'poplur_bling_phone_09_icy_aqua_turquoise', 'poplur_bling_phone_09_icy_aqua_turquoise.png', 'poplur_phone_bootup_icy_aqua_turquoise', 'poplur_icy_aqua_turquoise_boot_spritesheet_4x4.png'],
  ['Holo', 'poplur_bling_phone_10_holographic_iridescent', 'poplur_bling_phone_10_holographic_iridescent.png', 'poplur_phone_bootup_holographic_iridescent', 'poplur_holographic_iridescent_boot_spritesheet_4x4.png'],
].map(([title, restSet, restFile, bootSet, bootFile]) => ({
  title,
  rest: ios(restSet, restFile),
  boot: ios(bootSet, bootFile),
}));

const phoneMenus = {
  main: {
    title: 'Poplur',
    items: [
      { title: 'Calls', detail: 'place and manage calls', glyph: '01', destination: 'calls' },
      { title: 'Contacts', detail: 'people on Poplur', glyph: '02', destination: 'contacts' },
      { title: 'Texts', detail: 'inbox and drafts', glyph: '03', destination: 'texts' },
      { title: 'Games', detail: 'classic extras', glyph: '04', destination: 'games' },
      { title: 'Settings', detail: 'tones and profile', glyph: '05', destination: 'settings' },
      { title: 'Exit', detail: 'close phone', glyph: '06', action: 'exit' },
    ],
  },
  calls: {
    title: 'Calls',
    items: [
      { title: 'Call Poplur Phone', detail: 'start Poplur call', glyph: '>', action: 'call' },
      { title: 'Recent calls', detail: 'no missed calls', glyph: 'R', action: 'noop' },
      { title: 'Dial number', detail: 'keypad entry', glyph: '#', action: 'dial' },
    ],
  },
  contacts: {
    title: 'Contacts',
    items: [
      { title: 'Poplur Phone', detail: 'Poplur contact', glyph: 'A', action: 'call' },
      { title: 'Poplur Support', detail: 'online', glyph: 'B', action: 'noop' },
      { title: 'Add contact', detail: 'coming soon', glyph: '+', action: 'noop' },
    ],
  },
  texts: {
    title: 'Texts',
    items: [
      { title: 'Inbox', detail: '3 unread messages', glyph: 'I', action: 'noop' },
      { title: 'Write message', detail: 'compose SMS', glyph: 'W', action: 'noop' },
      { title: 'Drafts', detail: '0 saved', glyph: 'D', action: 'noop' },
    ],
  },
  games: {
    title: 'Games',
    items: [
      { title: 'Snake', detail: 'press 5 to play', glyph: 'S', action: 'snake' },
      { title: 'Memory', detail: 'locked', glyph: 'M', action: 'noop' },
      { title: 'Bounce', detail: 'locked', glyph: 'B', action: 'noop' },
    ],
  },
  settings: {
    title: 'Settings',
    items: [
      { title: 'Ring tone', detail: 'classic pop', glyph: 'T', action: 'noop' },
      { title: 'Screen glow', detail: 'green', glyph: 'G', action: 'noop' },
      { title: 'About', detail: 'Poplur phone', glyph: '?', action: 'noop' },
    ],
  },
};

const channels = [
  { id: 'food', number: 101, name: 'Food', emoji: '🍔', flag: '🇨🇦', icon: channelIcon('poplur_channel_101_food'), user: 'vi.xi.mmvi', coords: '43.6480, -79.3810', program: 'late-night poutine run downtown', theme: ['#3a1206', '#c2410c', '#f59e0b'] },
  { id: 'games', number: 102, name: 'Games', emoji: '🎮', flag: '🇨🇦', icon: createIcon('game'), user: 'arcade.nearby', coords: '43.6532, -79.3832', program: 'user-created games entering your radius', theme: ['#120716', '#b51d70', '#37e6ff'] },
  { id: 'beauty', number: 103, name: 'Beauty', emoji: '💄', flag: '🇺🇸', icon: channelIcon('poplur_channel_103_beauty'), user: 'leurdavoir', coords: '34.0522, -118.2437', program: 'soft glam in 60 seconds', theme: ['#2a0620', '#be185d', '#f472b6'] },
  { id: 'sports', number: 104, name: 'Sports', emoji: '⚽', flag: '🇬🇧', icon: channelIcon('poplur_channel_104_sports'), user: 'pitchside', coords: '51.5560, -0.2796', program: 'stoppage-time winner, crowd goes wild', theme: ['#052012', '#15803d', '#4ade80'] },
  { id: 'music', number: 107, name: 'Music', emoji: '🎵', flag: '🇺🇸', icon: channelIcon('poplur_channel_107_music'), user: 'basement.set', coords: '40.7128, -74.0060', program: 'live from the warehouse', theme: ['#12061f', '#7c3aed', '#c084fc'] },
  { id: 'news', number: 109, name: 'News', emoji: '📰', flag: '🇨🇦', icon: channelIcon('poplur_channel_109_news'), user: 'localwire', coords: '43.6426, -79.3871', program: 'Harbourfront rally is live', theme: ['#0b1220', '#334155', '#94a3b8'] },
  { id: 'cartoon', number: 113, name: 'Cartoon', emoji: '🎨', flag: '🇰🇷', icon: channelIcon('poplur_channel_113_cartoon'), user: 'doodlecast', coords: '37.5665, 126.9780', program: 'animating a clay short', theme: ['#0a1a2a', '#0891b2', '#fb7185'] },
];

const allGuideChannels = [
  ['poplur_channel_101_food', 101, 'Food', 'vi.xi.mmvi  ▶  sauceboss  ▶  lateplate'],
  ['create_ic_game', 102, 'Games', 'arcade.nearby  ▶  Pop Runner  ▶  0.4 km'],
  ['poplur_channel_103_beauty', 103, 'Beauty', 'leurdavoir  ▶  glowgetter  ▶  soft glam'],
  ['poplur_channel_104_sports', 104, 'Sports', 'pitchside  ▶  courtside  ▶  stoppage time'],
  ['poplur_channel_105_modelling', 105, 'Modelling', 'runwayraw  ▶  casting call  ▶  backstage'],
  ['poplur_channel_106_fashion', 106, 'Fashion', 'fitcheckdaily  ▶  thrift loop  ▶  street style'],
  ['poplur_channel_107_music', 107, 'Music', 'basement.set  ▶  warehouse live  ▶  CBC Music 94.1'],
  ['poplur_channel_108_tech', 108, 'Tech', 'shipit  ▶  desk setup  ▶  new demo'],
  ['poplur_channel_109_news', 109, 'News', 'localwire  ▶  harbourfront rally  ▶  breaking'],
  ['poplur_channel_112_shopping', 112, 'Shopping', 'sample sale  ▶  pop-up finds  ▶  under $20'],
  ['poplur_channel_113_cartoon', 113, 'Cartoon', 'doodlecast  ▶  clay OC  ▶  new upload'],
  ['poplur_channel_115_comedy', 115, 'Comedy', 'bitmerchant  ▶  crowd work  ▶  late show'],
];

const byId = id => channels.find(c => c.id === id) || channels[0];

const groups = {
  feed: {
    label: 'Feed',
    screens: [
      { id: 'feed-tvguide', title: 'TV Guide', detail: 'FeedOpenTVGuide overlay', icon: H.tvGuide, render: () => feedTVGuide() },
      { id: 'feed-comments', title: 'Comments', detail: 'Feed comment credits roll', icon: H.chat, render: () => feedComments() },
      { id: 'feed-news', title: 'News', detail: 'Poplur Newspaper page', icon: H.news, render: () => feedNews() },
      { id: 'feed-music', title: 'Music', detail: 'Hold menu music channel', icon: H.music, render: () => feedMusic() },
      { id: 'feed-games', title: 'Games', detail: 'Hold menu games channel', icon: H.games, render: () => feedGames() },
      { id: 'feed-like', title: 'Like', detail: 'Double-tap heart burst', icon: H.like, render: () => feedLike() },
      { id: 'feed-cc', title: 'CC On/Off', detail: 'Captions + auto translation', icon: H.cc, render: () => feedCC() },
    ],
  },
  camera: {
    label: 'Camera',
    screens: [
      { id: 'camera-capture', title: 'Capture', detail: 'Record tab camera controls', icon: H.create, render: () => cameraCapture() },
      { id: 'camera-roll', title: 'Camera Roll', detail: 'showCameraRollWindow', icon: H.cameraRoll, render: () => cameraRoll() },
      { id: 'camera-create', title: 'Create', detail: 'OpenCreatorRequested', icon: H.create, render: () => creatorScreen() },
      { id: 'camera-preview', title: 'Preview', detail: 'CapturePreviewOverlay', icon: H.tvGuide, render: () => cameraPreview() },
      { id: 'camera-live', title: 'Live', detail: 'LiveVideoStatusBadge', icon: H.tvGuide, render: () => cameraLive() },
      { id: 'camera-chat', title: 'Chat', detail: 'OpenDMsRequested', icon: H.chat, render: () => messagesScreen('Camera') },
      { id: 'camera-store', title: 'Store', detail: 'OpenPoplurStoreRequested', icon: H.store, render: () => storeScreen() },
    ],
  },
  map: {
    label: 'Map',
    screens: [
      { id: 'map-locate', title: 'Locate', detail: 'CenterMapOnUser', icon: H.locate, render: () => mapLocate() },
      { id: 'map-post', title: 'Post', detail: 'PoplurAIStartMapPost', icon: H.post, render: () => mapPost() },
      { id: 'map-tour', title: 'Tour', detail: 'PoplurAISetTourActive', icon: H.tour, render: () => mapTour() },
      { id: 'map-search', title: 'Search', detail: 'PoplurMapSearchOverlay', icon: H.locate, render: () => mapSearch() },
      { id: 'map-claims', title: 'Claims', detail: 'Dominance and radius pins', icon: H.stats, render: () => mapClaims() },
      { id: 'map-chat', title: 'Chat', detail: 'OpenDMsRequested', icon: H.chat, render: () => messagesScreen('Map') },
    ],
  },
  profile: {
    label: 'Profile',
    screens: [
      { id: 'profile-messages', title: 'Messages', detail: 'MessagesRootView', icon: H.chat, render: () => messagesScreen('Profile') },
      { id: 'profile-settings', title: 'Settings', detail: 'AppSettingsView', icon: H.settings, render: () => settingsScreen() },
      { id: 'profile-stats', title: 'Stats', detail: 'ProfileStatsView', icon: H.stats, render: () => statsScreen() },
      { id: 'profile-alerts', title: 'Notifications', detail: 'ProfileNotificationBanner', icon: H.notifications, render: () => notificationsScreen() },
      { id: 'profile-store', title: 'Store', detail: 'RadiusStoreView', icon: H.store, render: () => storeScreen() },
      { id: 'profile-phone', title: 'Phone', detail: 'PopularPhone overlay', icon: H.phone, render: () => phoneScreen() },
      { id: 'profile-creator', title: 'Creator', detail: 'PoplurAICreateView', icon: H.create, render: () => creatorScreen() },
    ],
  },
};

let activeGroup = 'feed';
let activeScreen = groups.feed.screens[0].id;
let phoneBootTimer = null;
let phoneColorIndex = 0;
let phoneMenuScreen = 'main';
let phoneMenuIndex = 0;
let phoneMode = 'menu';

const params = new URLSearchParams(window.location.search);
const embeddedScreen = params.get('embed');
if (params.get('rcl') === '1') {
  document.body.classList.add('rcl-clay');
}
if (embeddedScreen) {
  const embeddedGroup = Object.entries(groups).find(([, group]) => group.screens.some(screen => screen.id === embeddedScreen));
  if (embeddedGroup) {
    activeGroup = embeddedGroup[0];
    activeScreen = embeddedScreen;
    document.body.classList.add('embed');
  }
}

const tabsEl = document.getElementById('groupTabs');
const listEl = document.getElementById('screenList');
const screenEl = document.getElementById('screen');
const gclRefreshBarEl = document.getElementById('gclRefreshBar');
const gclRefreshTextEl = document.getElementById('gclRefreshText');

function esc(value) {
  return String(value).replace(/[&<>"']/g, ch => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#039;',
  }[ch]));
}

function formatGclRefresh(value) {
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) return 'Last refreshed: unavailable';
  const formatted = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short',
  }).format(date);
  return `Last refreshed: ${formatted}`;
}

function renderGclRefresh() {
  if (!gclRefreshTextEl) return;
  const generatedAt = window.GCL_REFRESH_META?.generatedAt ||
    window.GCL_CATALOG_DATA?.generatedAt ||
    gclRefreshBarEl?.dataset.generatedAt;
  gclRefreshTextEl.textContent = formatGclRefresh(generatedAt);
}

function renderNav() {
  tabsEl.innerHTML = Object.entries(groups).map(([key, group]) =>
    `<button type="button" class="${key === activeGroup ? 'active' : ''}" data-group="${key}">${group.label}</button>`
  ).join('');

  const group = groups[activeGroup];
  listEl.innerHTML = group.screens.map(item => `
    <button type="button" class="${item.id === activeScreen ? 'active' : ''}" data-screen="${item.id}">
      <img src="${item.icon}" alt="">
      <span><strong>${esc(item.title)}</strong><small>${esc(item.detail)}</small></span>
    </button>
  `).join('');
}

function renderScreen() {
  stopPhoneBoot();
  const group = groups[activeGroup];
  const item = group.screens.find(s => s.id === activeScreen) || group.screens[0];
  screenEl.className = `screen ${activeGroup}-screen`;
  screenEl.innerHTML = item.render();
  if (item.id === 'profile-phone' && typeof window !== 'undefined' && window.setTimeout) {
    window.setTimeout(initPhoneTwin, 0);
  }
}

function update() {
  renderGclRefresh();
  renderNav();
  renderScreen();
}

tabsEl.addEventListener('click', e => {
  const btn = e.target.closest('[data-group]');
  if (!btn) return;
  activeGroup = btn.dataset.group;
  activeScreen = groups[activeGroup].screens[0].id;
  update();
});

listEl.addEventListener('click', e => {
  const btn = e.target.closest('[data-screen]');
  if (!btn) return;
  activeScreen = btn.dataset.screen;
  update();
});

screenEl.addEventListener('change', e => {
  const input = e.target.closest('.music-file-input');
  if (!input || !input.files || !input.files.length) return;

  const files = Array.from(input.files);
  const audio = screenEl.querySelector('.music-audio');
  const title = screenEl.querySelector('.ipod-track-title');
  const subtitle = screenEl.querySelector('.ipod-track-subtitle');
  const list = screenEl.querySelector('.uploaded-tracks');

  if (audio) {
    audio.src = URL.createObjectURL(files[0]);
    audio.play().catch(() => {});
  }
  if (title) title.textContent = files[0].name.replace(/\.[^.]+$/, '');
  if (subtitle) subtitle.textContent = `${files.length} uploaded file${files.length === 1 ? '' : 's'} in this radius`;
  if (list) {
    list.innerHTML = files.slice(0, 4).map((file, index) => `
      <button type="button" class="${index === 0 ? 'on' : ''}">
        <b>${String(index + 1).padStart(2, '0')}</b>
        <span>${esc(file.name)}</span>
        <em>${formatBytes(file.size)}</em>
      </button>
    `).join('');
  }
});

screenEl.addEventListener('click', e => {
  const colorStep = e.target.closest('[data-phone-step]');
  if (colorStep) {
    stepPhoneColor(Number(colorStep.dataset.phoneStep));
    return;
  }

  const key = e.target.closest('[data-phone-key]');
  if (key) {
    handlePhoneKey(key.dataset.phoneKey);
  }
});

document.addEventListener('keydown', e => {
  if (activeScreen === 'profile-phone' && /^[0-9*#]$/.test(e.key)) {
    handlePhoneKey(e.key);
    e.preventDefault();
    return;
  }

  const group = groups[activeGroup];
  const index = group.screens.findIndex(item => item.id === activeScreen);
  if (e.key === 'ArrowDown') {
    activeScreen = group.screens[Math.min(group.screens.length - 1, index + 1)].id;
    update();
  }
  if (e.key === 'ArrowUp') {
    activeScreen = group.screens[Math.max(0, index - 1)].id;
    update();
  }
});

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 KB';
  const mb = bytes / 1024 / 1024;
  if (mb >= 1) return `${mb.toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function stopPhoneBoot() {
  if (phoneBootTimer) {
    window.clearInterval(phoneBootTimer);
    phoneBootTimer = null;
  }
}

function initPhoneTwin() {
  const page = screenEl.querySelector('.phone-page');
  if (!page) return;
  phoneMenuScreen = 'main';
  phoneMenuIndex = 0;
  phoneMode = 'menu';
  applyPhoneColor();
  renderPhoneMenu();
  startPhoneBoot();
}

function currentPhoneColorway() {
  return phoneColorways[phoneColorIndex] || phoneColorways[0];
}

function applyPhoneColor() {
  const page = screenEl.querySelector('.phone-page');
  if (!page) return;
  const colorway = currentPhoneColorway();
  const rest = page.querySelector('.phone-resting');
  const boot = page.querySelector('.phone-boot-frame');
  const label = page.querySelector('.phone-color-label');
  if (rest) rest.src = colorway.rest;
  if (boot) boot.style.backgroundImage = `url("${colorway.boot}")`;
  if (label) label.textContent = colorway.title;
}

function startPhoneBoot() {
  const page = screenEl.querySelector('.phone-page');
  const boot = screenEl.querySelector('.phone-boot-frame');
  const device = screenEl.querySelector('.popular-phone-device');
  if (!page || !boot || !device) return;

  stopPhoneBoot();
  phoneMenuScreen = 'main';
  phoneMenuIndex = 0;
  phoneMode = 'boot';
  page.classList.remove('is-ready');
  page.classList.add('is-booting');
  device.classList.add('phone-vibrating');
  setPhoneBootFrame(0);
  phoneVibrate([38, 28, 38, 28, 58]);

  let frame = 0;
  phoneBootTimer = window.setInterval(() => {
    frame += 1;
    if (frame >= 16) {
      stopPhoneBoot();
      phoneMode = 'menu';
      page.classList.remove('is-booting');
      page.classList.add('is-ready');
      device.classList.remove('phone-vibrating');
      renderPhoneMenu();
      return;
    }
    setPhoneBootFrame(frame);
  }, 112);
}

function setPhoneBootFrame(frame) {
  const boot = screenEl.querySelector('.phone-boot-frame');
  if (!boot) return;
  const col = frame % 4;
  const row = Math.floor(frame / 4);
  boot.style.backgroundPosition = `${(col / 3) * 100}% ${(row / 3) * 100}%`;
}

function stepPhoneColor(direction) {
  phoneColorIndex = (phoneColorIndex + direction + phoneColorways.length) % phoneColorways.length;
  applyPhoneColor();
  startPhoneBoot();
}

function phoneVibrate(pattern = 18) {
  try {
    if (typeof navigator !== 'undefined' && navigator.vibrate) navigator.vibrate(pattern);
  } catch (_) {}
}

function phoneMenuItems() {
  return (phoneMenus[phoneMenuScreen] || phoneMenus.main).items;
}

function renderPhoneMenu() {
  const lcd = screenEl.querySelector('.phone-lcd-overlay');
  if (!lcd) return;

  if (phoneMode === 'call') {
    lcd.innerHTML = phoneStatus('CALLING', 'POPLUR PHONE', '5 HANG UP  * BACK');
    return;
  }
  if (phoneMode === 'dial') {
    lcd.innerHTML = phoneStatus('DIAL NUMBER', '555-POPLUR', 'TYPE KEYS  * BACK');
    return;
  }
  if (phoneMode === 'snake') {
    lcd.innerHTML = `
      <div class="lcd-topline-mini"><span>SNAKE 0</span><span>5=PLAY</span></div>
      <div class="lcd-snake-board">
        <i style="--x:3;--y:4"></i><i style="--x:4;--y:4"></i><i style="--x:5;--y:4"></i><b style="--x:10;--y:6"></b>
      </div>
      <div class="lcd-softkeys">2/8 MOVE&nbsp;&nbsp;5 OK&nbsp;&nbsp;* BACK</div>
    `;
    return;
  }
  if (phoneMode === 'flash') return;

  const menu = phoneMenus[phoneMenuScreen] || phoneMenus.main;
  const items = menu.items;
  const start = Math.max(0, Math.min(phoneMenuIndex - 1, Math.max(0, items.length - 3)));
  const visible = items.slice(start, start + 3);
  lcd.innerHTML = `
    <div class="lcd-topline-mini"><span>▮▮▮ ⋮</span><span>▮▮</span></div>
    <div class="lcd-title-row"><strong>${esc(menu.title).toUpperCase()}</strong><em>${phoneMenuIndex + 1}/${items.length}</em></div>
    <div class="lcd-menu-list">
      ${visible.map((item, offset) => phoneMenuRow(item, start + offset === phoneMenuIndex)).join('')}
    </div>
    <div class="lcd-softkeys">2/8 SCROLL&nbsp;&nbsp;5 OK&nbsp;&nbsp;* BACK</div>
  `;
}

function phoneStatus(line1, line2, footer) {
  return `
    <div class="lcd-topline-mini"><span>▮▮▮ ⋮</span><span>▮▮</span></div>
    <div class="lcd-call-status"><strong>${esc(line1)}</strong><span>${esc(line2)}</span></div>
    <div class="lcd-softkeys">${esc(footer)}</div>
  `;
}

function phoneMenuRow(item, selected) {
  return `
    <div class="lcd-menu-row ${selected ? 'selected' : ''}">
      <b>${esc(item.glyph)}</b>
      <span><strong>${esc(item.title)}</strong><em>${esc(item.detail)}</em></span>
    </div>
  `;
}

function handlePhoneKey(key) {
  if (activeScreen !== 'profile-phone') return;
  if (phoneMode === 'boot') return;
  phoneVibrate(18);
  pulsePhoneKey(key);

  if (phoneMode !== 'menu') {
    if (key === '*') {
      phoneMode = 'menu';
      renderPhoneMenu();
      return;
    }
    if (phoneMode === 'call' && (key === '5' || key === '#')) {
      flashPhoneMessage('CALL ENDED');
      return;
    }
    if (phoneMode === 'dial' && /^[0-9#]$/.test(key)) {
      flashPhoneMessage(`DIAL ${key}`, 420, 'dial');
      return;
    }
    return;
  }

  const items = phoneMenuItems();
  if (key === '2') {
    phoneMenuIndex = (phoneMenuIndex - 1 + items.length) % items.length;
    renderPhoneMenu();
    return;
  }
  if (key === '8') {
    phoneMenuIndex = (phoneMenuIndex + 1) % items.length;
    renderPhoneMenu();
    return;
  }
  if (key === '5' || key === '#') {
    activatePhoneMenuItem();
    return;
  }
  if (key === '*') {
    if (phoneMenuScreen !== 'main') {
      phoneMenuScreen = 'main';
      phoneMenuIndex = 0;
      renderPhoneMenu();
    }
    return;
  }
  if (/^[1-6]$/.test(key) && phoneMenuScreen === 'main') {
    const shortcut = Number(key) - 1;
    if (items[shortcut]) {
      phoneMenuIndex = shortcut;
      activatePhoneMenuItem();
    }
  }
}

function activatePhoneMenuItem() {
  const item = phoneMenuItems()[phoneMenuIndex];
  if (!item) return;
  if (item.destination) {
    phoneMenuScreen = item.destination;
    phoneMenuIndex = 0;
    renderPhoneMenu();
    return;
  }
  if (item.action === 'call') {
    phoneMode = 'call';
    renderPhoneMenu();
    return;
  }
  if (item.action === 'dial') {
    phoneMode = 'dial';
    renderPhoneMenu();
    return;
  }
  if (item.action === 'snake') {
    phoneMode = 'snake';
    renderPhoneMenu();
    return;
  }
  if (item.action === 'exit') {
    startPhoneBoot();
    return;
  }
  flashPhoneMessage(`${item.title.toUpperCase()}\\nCOMING SOON`);
}

function flashPhoneMessage(message, delay = 850, returnMode = 'menu') {
  const lcd = screenEl.querySelector('.phone-lcd-overlay');
  if (!lcd) return;
  phoneMode = 'flash';
  const [line1, line2 = ''] = String(message).split('\\n');
  lcd.innerHTML = phoneStatus(line1, line2, '* BACK');
  window.setTimeout(() => {
    if (activeScreen !== 'profile-phone') return;
    phoneMode = returnMode;
    renderPhoneMenu();
  }, delay);
}

function pulsePhoneKey(key) {
  const device = screenEl.querySelector('.popular-phone-device');
  const hit = Array.from(screenEl.querySelectorAll('[data-phone-key]')).find(btn => btn.dataset.phoneKey === key);
  if (!device) return;
  device.classList.add('phone-key-pressed');
  if (hit) hit.classList.add('pressed');
  window.setTimeout(() => {
    device.classList.remove('phone-key-pressed');
    if (hit) hit.classList.remove('pressed');
  }, 150);
}

function feedTopInfo(ch, channelMode = false) {
  return `
    <div class="feed-top-info">
      <span class="flag">${ch.flag}</span>
      <img class="channel-icon" src="${ch.icon}" alt="">
      <div class="ticker">
        <strong class="${channelMode ? 'green mono' : ''}">${channelMode ? `CH ${ch.number}` : esc(ch.user)}</strong>
        <span class="${channelMode ? 'green mono' : ''}">${channelMode ? ch.name.toUpperCase() : esc(ch.coords)}</span>
      </div>
    </div>
  `;
}

function feedBase(ch, options = {}) {
  const mode = options.channelMode ?? false;
  const caption = options.caption || ch.program;
  const badge = options.badge || 'AI -> EN';
  const captionHidden = options.captionHidden || false;
  const extra = options.extra || '';
  return `
    <div class="ios-screen feed" style="--feed0:${ch.theme[0]};--feed1:${ch.theme[1]};--feed2:${ch.theme[2]}">
      <div class="feed-video"></div>
      <div class="feed-vignette"></div>
      ${feedTopInfo(ch, mode)}
      <div class="feed-actions">
        <span class="${options.liked ? 'liked' : ''}">♥</span>
        <span>💬</span>
        <span>↗</span>
      </div>
      <div class="feed-stepper">
        <img src="${A.up}" alt="">
        <img class="ch" src="${A.ch}" alt="">
        <img src="${A.down}" alt="">
      </div>
      <div class="feed-caption ${captionHidden ? 'caption-off' : ''}">
        <p>${esc(caption)}</p>
        <small>${esc(badge)}</small>
      </div>
      <img class="feed-logo-bug" src="${A.logo}" alt="">
      ${extra}
    </div>
  `;
}

function feedTVGuide() {
  const current = byId('food');
  const rows = allGuideChannels.map((row, index) => {
    const [icon, number, category, now] = row;
    return `
      <div class="guide-row ${index === 0 ? 'on' : ''}">
        <div class="guide-ch"><img src="${channelIcon(icon)}" alt=""><span>${number}</span></div>
        <div class="guide-cat">${category.toUpperCase()}</div>
        <div class="guide-now">${esc(now)}</div>
        <span class="live-badge">LIVE</span>
      </div>
    `;
  }).join('');

  return feedBase(current, {
    channelMode: true,
    caption: 'AI host says Yonge-Dundas Square is live right now',
    extra: `
      <div class="tv-guide">
        <div class="guide-header">
          <div>
            <h1>TV GUIDE</h1>
            <span>LIVE CHANNELS</span>
          </div>
          <div class="close-dot">×</div>
        </div>
        <div class="pip-band">
          <div class="pip-video"></div>
          <div>
            <div class="green mono" style="font-weight:950">CH 101</div>
            <div class="mono" style="font-size:11px;color:rgba(255,255,255,.62);font-weight:950">FOOD</div>
            <div style="font-size:11px;color:rgba(255,255,255,.42);font-weight:800">late-night poutine run downtown</div>
          </div>
          <span class="live-badge">LIVE</span>
        </div>
        <div class="guide-columns"><span>CH</span><span>CATEGORY</span><span>ON NOW</span><span></span></div>
        <div class="guide-list">${rows}</div>
      </div>
    `,
  });
}

function feedComments() {
  const ch = byId('beauty');
  return feedBase(ch, {
    caption: 'soft glam in 60 seconds',
    extra: `
      <div class="comment-roll">
        <div>
          <h2>Comments</h2>
          <div class="display">leurdavoir</div>
          ${comment('vi.xi.mmvi', 'this is live right now')}
          ${comment('leurdavoir', 'keep the camera there')}
          ${comment('monsekee', 'the radius is going crazy')}
          ${comment('poplur', 'watching leurdavoir')}
        </div>
      </div>
    `,
  });
}

function feedNews() {
  return `
    <div class="ios-screen newspaper-page">
      <div class="newspaper-stack">
        ${newspaperArticle({
          edition: 'No. 1',
          chip: 'MAP EVENT',
          chipClass: 'yellow',
          city: 'Toronto',
          flag: '🇨🇦',
          time: '2m ago',
          headline: 'Viral Content Surge Detected Near Yonge-Dundas Square',
          detail: 'Poplur AI flagged an unusual spike in post activity within a 2 km radius. More than 3,200 users captured content here in the last 90 minutes, pushing the square into the lead story slot.',
          stat1: '3.2K users nearby',
          stat2: '43.653°N, 79.383°W',
          style: 'map'
        })}
        ${newspaperArticle({
          edition: 'No. 2',
          chip: 'TRENDING',
          chipClass: 'green',
          city: 'London',
          flag: '🇬🇧',
          time: '11m ago',
          headline: 'Post Volume Triples as City Breaks Into Global Top 10',
          detail: 'An unprecedented wave of creator activity has catapulted the city into Poplur Daily. AI trend analysis points to weather, cultural momentum, and rising radius posts.',
          stat1: '+312% engagement',
          stat2: '14.2K active',
          style: 'trend'
        })}
        ${newspaperArticle({
          edition: 'No. 3',
          chip: 'DOMINANCE',
          chipClass: 'red',
          city: 'New York',
          flag: '🇺🇸',
          time: '18m ago',
          headline: '@CityQueen_Riri Claims Full Control of Metro District',
          detail: 'Through sustained high-radius posts and fast engagement, this user locked down the metro zone. Challengers within 10 km were pushed off the local leaderboard.',
          stat1: '28 km radius',
          stat2: '42.0K score',
          style: 'dominance'
        })}
      </div>
    </div>
  `;
}

function newspaperArticle(article) {
  return `
    <article class="newspaper-article">
      <header class="newspaper-masthead">
        <div>
          <strong>POPLUR</strong><span> DAILY</span>
        </div>
        <aside>
          <b>${esc(newspaperDate())}</b>
          <em>${esc(article.edition)}</em>
        </aside>
      </header>
      <div class="newspaper-rules"><i></i><i></i></div>
      <div class="newspaper-meta">
        <span class="${esc(article.chipClass)}">${esc(article.chip)}</span>
        <b>${esc(article.flag)} ${esc(article.city)}</b>
        <em>${esc(article.time)}</em>
      </div>
      <h1>${esc(article.headline)}</h1>
      <div class="newspaper-divider"></div>
      <div class="newspaper-visual ${esc(article.style)}">
        <div class="paper-map-grid"></div>
        <div class="paper-signal"><i></i><i></i><i></i></div>
        <strong>${esc(article.city)}</strong>
      </div>
      <p>${esc(article.detail)}</p>
      <div class="newspaper-stats">
        <span>● ${esc(article.stat1)}</span>
        <span>⌖ ${esc(article.stat2)}</span>
      </div>
      <footer>Hold to view on map · Swipe for next story · Reading aloud</footer>
    </article>
  `;
}

function newspaperDate() {
  return new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });
}

function feedMusic() {
  const ch = byId('music');
  return feedBase(ch, {
    channelMode: true,
    caption: 'Now playing uploaded music inside your radius',
    badge: 'CC EN',
    extra: `
      <div class="feed-channel-label glass">
        <img src="${H.music}" alt="">
        <span>HOLD MENU</span>
        <strong>MUSIC CHANNEL</strong>
      </div>
      <div class="music-player-panel glass">
        <div class="ipod-device">
          <div class="ipod-screen">
            <div class="equalizer"><i></i><i></i><i></i><i></i></div>
            <strong class="ipod-track-title">warehouse_loop.wav</strong>
            <span class="ipod-track-subtitle">Uploaded by @basement.set · 0.8 km</span>
            <div class="music-progress"><b></b></div>
            <audio class="music-audio" controls></audio>
          </div>
          <div class="click-wheel">
            <span class="top">MENU</span>
            <span class="left">◀</span>
            <span class="right">▶</span>
            <span class="bottom">▮▮</span>
            <b>▶</b>
          </div>
        </div>
        <div class="channel-sidecar">
          <div class="radius-chip"><strong>6.3 km</strong><span>radius</span></div>
          <label class="upload-button">
            <input class="music-file-input" type="file" accept="audio/*" multiple>
            <span>Upload Music</span>
          </label>
          <div class="uploaded-tracks">
            ${musicTrack('01', 'warehouse_loop.wav', '0.8 km')}
            ${musicTrack('02', 'late-night-demo.mp3', '1.4 km')}
            ${musicTrack('03', 'dundas-square-live.m4a', '2.1 km')}
          </div>
        </div>
      </div>
    `,
  });
}

function musicTrack(number, title, radius) {
  return `
    <button type="button" class="${number === '01' ? 'on' : ''}">
      <b>${number}</b>
      <span>${esc(title)}</span>
      <em>${esc(radius)}</em>
    </button>
  `;
}

function feedGames() {
  const ch = byId('games');
  return feedBase(ch, {
    channelMode: true,
    caption: 'User-created games are entering your radius',
    badge: 'CC EN',
    extra: `
      <div class="feed-channel-label glass">
        <img src="${H.games}" alt="">
        <span>HOLD MENU</span>
        <strong>GAMES CHANNEL</strong>
      </div>
      <div class="games-channel-panel glass">
        <div class="games-channel-head">
          <div>
            <span class="pill pink-pill">CH 102</span>
            <h2>Games In Your Radius</h2>
          </div>
          <div class="radius-chip"><strong>6.3 km</strong><span>radius</span></div>
        </div>
        <div class="radius-game-list">
          ${radiusGame('Pop Runner', '@arcade.nearby', '0.4 km', 'Runner', '#f72686')}
          ${radiusGame('Stella Blast', '@stella.ai', '1.2 km', 'Shooter', '#37e6ff')}
          ${radiusGame('Zyla Quest', '@questmaker', '2.8 km', 'Adventure', '#4dff40')}
          ${radiusGame('Poplurgatchi', '@petpixel', '5.9 km', 'Pet Sim', '#ffb020')}
        </div>
      </div>
    `,
  });
}

function radiusGame(title, creator, distance, kind, color) {
  return `
    <div class="radius-game-card" style="--accent:${color}">
      <div class="game-orb">▶</div>
      <div>
        <strong>${esc(title)}</strong>
        <span>${esc(creator)} · ${esc(kind)}</span>
      </div>
      <em>${esc(distance)}</em>
    </div>
  `;
}

function feedLike() {
  const ch = byId('sports');
  return feedBase(ch, {
    caption: 'stoppage-time winner, crowd goes wild',
    badge: 'CC EN',
    liked: true,
    extra: `
      <div class="like-heart">♥</div>
      <div class="tour-card glass" style="bottom:196px">
        <div class="pill pink-pill">LIKE</div>
        <h2 style="margin-top:10px">Liked</h2>
        <p style="margin:6px 0 0;color:rgba(255,255,255,.78);font-weight:800">Matches the feed double-tap heart burst and persists the local like state.</p>
      </div>
    `,
  });
}

function feedCC() {
  const ch = byId('beauty');
  return feedBase(ch, {
    caption: 'Translated from FR: soft glam in 60 seconds',
    badge: 'AI FR -> EN',
    extra: `
      <div class="cc-panel glass">
        <div class="cc-row">
          <div>
            <strong>Closed Captions</strong>
            <span>On by default</span>
          </div>
          <div class="switch on"><b></b></div>
        </div>
        <div class="cc-row">
          <div>
            <strong>Auto Translation</strong>
            <span>Translate captions to English</span>
          </div>
          <span class="pill green">ENGLISH</span>
        </div>
      </div>
    `,
  });
}

function comment(user, text) {
  return `<div class="comment-item"><strong>${esc(user)}</strong><span>${esc(text)}</span></div>`;
}

function cameraCapture() {
  return `
    <div class="ios-screen camera">
      <div class="camera-preview"></div>
      <div class="camera-top-controls">
        <div class="camera-icon-btn">ϟ</div>
        <div class="camera-icon-btn">↻</div>
      </div>
      <div class="ml-bubble">
        <div class="face-box"></div>
        <span>@creator</span>
      </div>
      <div class="camera-focus"></div>
      <div class="camera-hint">The cube is the shutter · Hold it for Photo, Video, or Live</div>
    </div>
  `;
}

function cameraRoll() {
  return `
    <div class="ios-screen camera">
      <div class="camera-preview"></div>
      <div class="camera-top-controls">
        <div class="camera-icon-btn">ϟ</div>
        <div class="camera-icon-btn">↻</div>
      </div>
      <div class="bottom-sheet">
        <div class="sheet-handle"></div>
        <div class="page-title"><img src="${H.cameraRoll}" alt=""><h1 style="font-size:30px">Camera Roll</h1></div>
        <p class="page-sub">Recent media opens as the same window shown by <b>showCameraRollWindow</b>.</p>
        <div class="media-grid">
          ${mediaCell('#f472b6', '#2a0620')}
          ${mediaCell('#38bdf8', '#04121f')}
          ${mediaCell('#4ade80', '#052012')}
          ${mediaCell('#fbbf24', '#2a1204')}
          ${mediaCell('#a78bfa', '#170a2e')}
          ${mediaCell('#94a3b8', '#0b1220')}
          ${mediaCell('#fb7185', '#0a1a2a')}
          ${mediaCell('#c084fc', '#12061f')}
          ${mediaCell('#f59e0b', '#3a1206')}
        </div>
      </div>
    </div>
  `;
}

function mediaCell(a, b) {
  return `<div class="media-cell" style="--a:${a};--b:${b}"></div>`;
}

function cameraPreview() {
  return `
    <div class="ios-screen camera">
      <div class="camera-preview" style="background:radial-gradient(circle at 48% 38%,rgba(255,255,255,.24),transparent 18%),linear-gradient(140deg,#35353d,#101014)"></div>
      <div class="scan-badge">
        <i></i>
        <span>SCANNING BROADCAST</span>
      </div>
      <div class="preview-actions">
        <div class="preview-action"><i class="white">×</i><span>Retake</span></div>
        <div class="preview-action"><i class="red">✓</i><span>Keep</span></div>
      </div>
    </div>
  `;
}

function cameraLive() {
  return `
    <div class="ios-screen camera">
      <div class="camera-preview"></div>
      <div class="camera-top-controls">
        <div class="camera-icon-btn">ϟ</div>
        <div class="camera-icon-btn">↻</div>
      </div>
      <div class="live-status"><i></i><b>LIVE</b><span>1:42</span><span class="green">128 watching</span><span>Yonge-Dundas</span></div>
      <div class="camera-focus"></div>
    </div>
  `;
}

function creatorScreen() {
  const tools = [
    ['image', 'Image', 'GPT Image'],
    ['video', 'Video', 'Video model'],
    ['3d', '3D Model', 'Meshy'],
    ['voice', 'Voice', 'ElevenLabs'],
    ['music', 'Music', 'MusicGen'],
    ['game', 'Game', 'Game Maker'],
    ['vfx', 'VFX', 'Effects'],
    ['coupon', 'Coupon', 'Campaign'],
  ].map(([key, title, provider]) => `
    <div class="tool-card">
      <img src="${createIcon(key)}" alt="">
      <strong>${title}</strong>
      <span>${provider}</span>
    </div>
  `).join('');

  return `
    <div class="light-page">
      <div class="page-title">
        <img src="${H.create}" alt="">
        <h1>Create</h1>
        <div class="credits-card">
          <img src="${A.createCredits}" alt="">
          <div><strong>0</strong><span>Creator Credits</span></div>
        </div>
      </div>
      <p class="page-sub">Use Creator Credits to generate premium AI content, then publish it to a real Poplur map location.</p>
      <div class="plan-tabs"><span class="on">Free</span><span>Pro</span><span>Ultra</span></div>
      <div class="tool-grid">${tools}</div>
      <div class="white-card coming-card">
        <div><strong>More tools coming soon!</strong><span>New ways to create and share on Poplur.</span></div>
        <img src="${A.createP}" alt="">
      </div>
    </div>
  `;
}

function messagesScreen(from) {
  return `
    <div class="ios-screen messages">
      <div class="message-top">
        <img src="${H.chat}" alt="">
        <div><h1>Chats</h1><span style="color:#777;font-weight:800">${esc(from)} route · OpenDMsRequested</span></div>
      </div>
      <div class="message-list">
        ${thread('AL', 'Chat a31f62', 'No messages yet', 2)}
        ${thread('VI', 'vi.xi.mmvi', 'this is live right now', 0)}
        ${thread('PO', 'Poplur Phone', 'Ready for a video call', 1)}
        ${thread('AI', 'AI host', 'Yonge-Dundas Square is popping', 0)}
      </div>
    </div>
  `;
}

function thread(initials, title, preview, unread) {
  return `
    <div class="thread">
      <div class="avatar">${initials}</div>
      <div><strong>${esc(title)}</strong><span>${esc(preview)}</span></div>
      <div class="video-dot">${unread ? unread : '▶'}</div>
    </div>
  `;
}

function storeScreen() {
  return `
    <div class="ios-screen store-page">
      <div class="browser-bar">
        <strong>Poplur</strong>
        <span style="font-size:12px;color:#666;font-weight:800">Store</span>
        <span style="font-size:12px;color:#666;font-weight:800">Cards</span>
        <span style="font-size:12px;color:#666;font-weight:800">Radius</span>
        <span style="margin-left:auto">⌂</span>
      </div>
      <div class="store-hero">
        <h1>Poplur Store</h1>
        <p>World Service cards, radius boosts, and Poplur hardware.</p>
        <img src="${A.storeHero}" alt="" style="width:210px;max-height:170px;object-fit:contain">
      </div>
      <div class="store-products">
        <div style="display:flex;align-items:center;gap:10px"><img src="${A.storeBag}" style="width:44px;height:44px;object-fit:contain" alt=""><h2 style="margin:0">Featured</h2></div>
        <div class="product-grid">
          ${product(A.storeCard, 'Poplur World Card', '$24.99')}
          ${product(A.storeCube, 'Poplur Cube V2', '$39.99')}
          ${product(A.store5, '5km Radius Boost', '$4.99')}
          ${product(A.store25, '25km Radius Boost', '$19.99')}
        </div>
      </div>
    </div>
  `;
}

function product(img, title, price) {
  return `<div class="product-card"><img src="${img}" alt=""><strong>${esc(title)}</strong><span>${price}</span></div>`;
}

function mapBase(extra, modeClass = '') {
  return `
    <div class="ios-screen map ${modeClass}">
      <div class="map-world"></div>
      ${mapBuildings()}
      <img class="map-pin" src="${A.pin}" style="left:54%;top:43%" alt="">
      <img class="map-pin" src="${A.pin}" style="left:23%;top:30%;transform:scale(.68)" alt="">
      <img class="map-pin" src="${A.pin}" style="right:14%;top:26%;transform:scale(.58)" alt="">
      <div class="floating-controls"><span>⌖</span><span>◉</span><span>＋</span><span>−</span><span>▲</span><span>◒</span></div>
      ${extra}
    </div>
  `;
}

function mapBuildings() {
  const items = [
    ['building', 'CN Tower', '68%', '20%'],
    ['building', 'Eaton', '14%', '18%'],
    ['house', 'House', '31%', '49%'],
    ['house', 'Homes', '76%', '55%'],
    ['building', 'Arena', '48%', '67%'],
    ['house', 'Lofts', '12%', '72%'],
  ];
  return items.map(([cls, label, left, top]) =>
    `<div class="${cls}" style="left:${left};top:${top}"><b></b><span>${label}</span></div>`
  ).join('');
}

function mapLocate() {
  return mapBase(`
    <div class="map-ai">
      <h2>Toronto</h2>
      <p>Centering on your location</p>
    </div>
  `);
}

function mapPost() {
  return mapBase(`
    <div class="map-ai">
      <h2>Select Post Location</h2>
      <p>Tap where you want to post your capture</p>
    </div>
    <div class="post-button">📷 Post Here</div>
  `);
}

function mapTour() {
  return mapBase(`
    <div class="map-ai">
      <h2>Paris</h2>
      <p>Now playing - Finding local station...</p>
    </div>
    <div class="tour-card glass">
      <span class="pill pink-pill">TOUR ACTIVE</span>
      <h2>Eiffel Tower energy</h2>
      <p style="margin:8px 0 0;color:rgba(255,255,255,.76);font-weight:800">AI host city tour with radio, radius pulses, and live moments.</p>
      <div class="tour-list"><span>New York</span><span>Toronto</span><span>Tokyo</span><span>London</span><span>Dubai</span><span>Sydney</span></div>
    </div>
  `);
}

function mapSearch() {
  return mapBase(`
    <div class="map-search-bar">
      <div class="search-card">
        <div class="search-input"><b style="color:var(--pink)">⌕</b><span>Search places, people, vibes...</span></div>
        <div class="chips"><span>Nearby vibes</span><span>Coffee spots</span><span>Rooftops</span><span>Live music</span></div>
      </div>
      <div class="search-card search-results">
        ${resultRow('☕', 'Jimmy’s Coffee', '107 Portland St')}
        ${resultRow('♪', 'Live music', 'Queen Street West')}
        ${resultRow('★', 'Rooftop', 'Downtown')}
      </div>
    </div>
  `);
}

function resultRow(icon, name, addr) {
  return `<div class="result-row"><i>${icon}</i><div><strong>${esc(name)}</strong><br><span style="color:#777;font-size:12px;font-weight:750">${esc(addr)}</span></div><b>›</b></div>`;
}

function mapClaims() {
  return mapBase(`
    <div class="map-ai">
      <h2>Radius Claims</h2>
      <p>Viewing dominance pins and post radius overlays</p>
    </div>
    <div class="tour-card glass">
      <span class="pill green">TRENDING</span>
      <h2>128 posts</h2>
      <p style="margin:8px 0 0;color:rgba(255,255,255,.78);font-weight:800">Pins grow and claim cards surface when a radius starts taking over an area.</p>
      <div class="tour-list"><span>41.8 km</span><span>CN Tower</span><span>3 claims</span></div>
    </div>
  `);
}

function settingsScreen() {
  const rows = [
    [ios('settings_ic_film', 'settings_ic_film.png'), 'Video duration', 'Current limit: 10s'],
    [ios('settings_ic_film', 'settings_ic_film.png'), 'Closed Captions', 'On'],
    [ios('settings_ic_info', 'settings_ic_info.png'), 'Auto Translation', 'English'],
    [ios('settings_ic_bell', 'settings_ic_bell.png'), 'Notifications', 'Daily Poplur alerts'],
    [ios('settings_ic_flask', 'settings_ic_flask.png'), 'Seed NA (1000)', 'Demo content controls'],
    [ios('settings_ic_play', 'settings_ic_play.png'), 'TV guide animation', 'Flip animation on'],
    [ios('settings_ic_wrench', 'settings_ic_wrench.png'), 'Fix Empty UserIDs', 'Maintenance'],
    [ios('settings_ic_cloud', 'settings_ic_cloud.png'), 'Back Up Data', 'Cloud export'],
    [ios('settings_ic_info', 'settings_ic_info.png'), 'About Poplur', 'Version and credits'],
    [ios('settings_ic_doc', 'settings_ic_doc.png'), 'Terms of Service', 'Legal'],
  ].map(([img, title, sub]) => `
    <div class="settings-row"><img src="${img}" alt=""><div><strong>${title}</strong><span>${sub}</span></div><b>›</b></div>
  `).join('');
  return `
    <div class="ios-screen settings-page">
      <div class="settings-hero"><img src="${H.settings}" alt=""><div><h1>Settings</h1><span style="color:var(--subtle);font-weight:800">AppSettingsView</span></div></div>
      <div class="translation-card">
        <div>
          <strong>Translate captions to</strong>
          <span>Default language is English</span>
        </div>
        <div class="language-picker">
          <span class="on">🇺🇸 English</span>
          <span>🇫🇷 French</span>
          <span>🇪🇸 Spanish</span>
        </div>
      </div>
      <div class="settings-list">${rows}</div>
      <div class="settings-row" style="margin-top:16px;background:#fff"><img src="${ios('settings_ic_signout', 'settings_ic_signout.png')}" alt=""><div><strong>Sign Out</strong><span>Account</span></div><b>›</b></div>
    </div>
  `;
}

function statsScreen() {
  return `
    <div class="ios-screen stats-page">
      <div class="stats-header">
        <div>
          <div class="page-title"><img src="${H.stats}" alt=""><h1 style="font-size:36px">Stats</h1></div>
          <p class="page-sub">Creator performance and radius progress.</p>
        </div>
        <img src="${A.statsSphere}" alt="">
      </div>
      <div class="ring"><div><div><strong>74%</strong><span>GOAL</span></div></div></div>
      <div class="stats-grid">
        <div class="stat-card"><img src="${A.statsPosts}" alt=""><strong>128</strong><span>Total Posts</span></div>
        <div class="stat-card"><img src="${A.statsGoal}" alt=""><strong>41.8 km</strong><span>Radius Reach</span></div>
        <div class="stat-card"><img src="${A.statsOrbit}" alt=""><strong>8x</strong><span>Trending Speed</span></div>
        <div class="stat-card"><img src="${H.create}" alt=""><strong>12</strong><span>Creator Streak</span></div>
      </div>
    </div>
  `;
}

function notificationsScreen() {
  const items = [
    ['♥', 'Area takeover', 'Your radius passed a nearby creator.', true],
    ['↗', 'Post radius is growing', 'Harbourfront rally gained 4.2 km.', true],
    ['↘', 'Accumulated radius dipped', 'One older post cooled down.', false],
    ['★', 'Daily insight', 'Food and music are trending near you.', false],
  ].map(([icon, title, detail, unread]) => `
    <div class="thread" style="background:white;border-top:0;border-radius:16px;margin:0 16px 10px;box-shadow:0 4px 12px rgba(0,0,0,.07)">
      <div class="avatar" style="background:${unread ? '#f72686' : '#29c46a'}">${icon}</div>
      <div><strong>${title}</strong><span>${detail}</span></div>
      <div>${unread ? '<span style="display:block;width:10px;height:10px;border-radius:50%;background:red"></span>' : ''}</div>
    </div>
  `).join('');

  return `
    <div class="ios-screen" style="background:#fef0f5;color:#111;padding-top:76px">
      <div style="background:#ff9fc6;padding:24px 0 22px;border-radius:0 0 28px 28px;box-shadow:0 12px 24px rgba(0,0,0,.14)">
        <div class="message-top"><img src="${H.notifications}" alt=""><div><h1>Notifications</h1><span style="font-weight:800;color:rgba(0,0,0,.55)">ProfileNotificationBanner</span></div></div>
        ${items}
      </div>
    </div>
  `;
}

function phoneScreen() {
  const colorway = currentPhoneColorway();
  return `
    <div class="ios-screen phone-page">
      <button type="button" class="phone-swipe-arrow left" data-phone-step="-1" aria-label="Previous phone colorway">‹</button>
      <button type="button" class="phone-swipe-arrow right" data-phone-step="1" aria-label="Next phone colorway">›</button>
      <div class="phone-color-label">${esc(colorway.title)}</div>
      <div class="popular-phone-device">
        <img class="phone-resting" src="${colorway.rest}" alt="">
        <div class="phone-boot-frame" style="background-image:url('${colorway.boot}')"></div>
        <div class="phone-lcd-overlay" aria-live="polite"></div>
        <div class="phone-hit-zones" aria-label="Poplur phone keypad">
          ${phoneKey('1', 20.5, 62.2, 17, 6)}
          ${phoneKey('2', 41.5, 62.2, 17, 6)}
          ${phoneKey('3', 62.5, 62.2, 17, 6)}
          ${phoneKey('4', 20.5, 69.4, 17, 6)}
          ${phoneKey('5', 41.5, 69.4, 17, 6)}
          ${phoneKey('6', 62.5, 69.4, 17, 6)}
          ${phoneKey('7', 20.5, 76.7, 17, 6)}
          ${phoneKey('8', 41.5, 76.7, 17, 6)}
          ${phoneKey('9', 62.5, 76.7, 17, 6)}
          ${phoneKey('*', 20.5, 84.0, 17, 6)}
          ${phoneKey('0', 41.5, 84.0, 17, 6)}
          ${phoneKey('#', 62.5, 84.0, 17, 6)}
          ${phoneKey('5', 39.5, 50.9, 21, 7, 'Center select')}
        </div>
      </div>
    </div>
  `;
}

function phoneKey(key, left, top, width, height, label = key) {
  return `<button type="button" data-phone-key="${esc(key)}" aria-label="${esc(label)}" style="left:${left}%;top:${top}%;width:${width}%;height:${height}%"></button>`;
}

update();
