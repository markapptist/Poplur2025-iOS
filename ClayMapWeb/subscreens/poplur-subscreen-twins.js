const IOS = 'assets/';
const CLAY = '../';
const STORE_MODELS = './store-models/';
const STORE_POSTERS = './store-posters/';

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
let phoneThemeTimer = null;
let phoneToneContext = null;
let phoneToneSuspendTimer = null;
let phoneColorIndex = 0;
let phoneMenuScreen = 'main';
let phoneMenuIndex = 0;
let phoneMode = 'menu';
let profileMailThread = null;
let profileStoreProduct = null;
let profileStoreNotice = '';
let profileStoreBag = [];
let profileStoreView = 'catalog';
let profileStoreCheckoutPending = false;
let profileStoreCheckoutRequestId = null;
let profileStoreCheckoutSnapshot = null;
let profileStoreTab = 'featured';
let profileStoreSlide = 0;
let storeCarouselTimer = null;
let profileStat = null;
let profileSettingsPanel = null;
let profileSettingsNotice = '';

const profileMailThreads = [
  {
    id: 'chat-a31f62',
    initials: 'AL',
    title: 'Chat a31f62',
    preview: 'No messages yet',
    unread: 2,
    messages: [
      { from: 'them', text: 'Hey — are you around the radius tonight?' },
      { from: 'me', text: 'Yes. Send me the channel when it goes live.' },
    ],
  },
  {
    id: 'vi-xi-mmvi',
    initials: 'VI',
    title: 'vi.xi.mmvi',
    preview: 'this is live right now',
    unread: 0,
    messages: [
      { from: 'them', text: 'this is live right now' },
      { from: 'me', text: 'I see it on channel 101.' },
    ],
  },
  {
    id: 'poplur-phone',
    initials: 'PO',
    title: 'Poplur Phone',
    preview: 'Ready for a video call',
    unread: 1,
    messages: [
      { from: 'them', text: 'Your Poplur Phone is ready for a video call.' },
    ],
  },
  {
    id: 'ai-host',
    initials: 'AI',
    title: 'AI host',
    preview: 'Yonge-Dundas Square is popping',
    unread: 0,
    messages: [
      { from: 'them', text: 'Yonge-Dundas Square is popping. Want a quick tour?' },
    ],
  },
];

const profileStoreProducts = [
  {
    id: 'inverted',
    iosProductId: 'com.apptist.Poplur2025.card.inverted',
    androidProductId: 'com.apptists.poplur2025.card.inverted',
    model: `${STORE_MODELS}poplur_card_inverted.glb`,
    poster: `${STORE_POSTERS}poplur_card_inverted.jpg`,
    title: 'Inverted Card',
    category: 'cards',
    price: '$2.99',
    priceAmount: 2.99,
    credits: 300,
    kicker: 'BOLD BY DESIGN',
    tone: 'inverted',
    description: 'A sharp inside-out Poplur finish. Adds 300 Poplur Credits after a verified purchase.',
  },
  {
    id: 'lens',
    iosProductId: 'com.apptist.Poplur2025.card.lens',
    androidProductId: 'com.apptists.poplur2025.card.lens',
    model: `${STORE_MODELS}poplur_card_lens.glb`,
    poster: `${STORE_POSTERS}poplur_card_lens.jpg`,
    title: 'Lens Card',
    category: 'cards',
    price: '$4.99',
    priceAmount: 4.99,
    credits: 550,
    kicker: 'FOCUS FORWARD',
    tone: 'lens',
    description: 'A glossy optical card with a camera-lens core. Adds 550 Poplur Credits after a verified purchase.',
  },
  {
    id: 'splitDiamond',
    iosProductId: 'com.apptist.Poplur2025.card.splitdiamond',
    androidProductId: 'com.apptists.poplur2025.card.splitdiamond',
    model: `${STORE_MODELS}poplur_card_split_diamond.glb`,
    poster: `${STORE_POSTERS}poplur_card_split_diamond.jpg`,
    title: 'Split Diamond Card',
    category: 'cards',
    price: '$6.99',
    priceAmount: 6.99,
    credits: 800,
    kicker: 'CUT TO STAND OUT',
    tone: 'splitdiamond',
    description: 'A faceted split-diamond card built for standout profiles. Adds 800 Poplur Credits after a verified purchase.',
  },
  {
    id: 'swoosh',
    iosProductId: 'com.apptist.Poplur2025.card.swoosh',
    androidProductId: 'com.apptists.poplur2025.card.swoosh',
    model: `${STORE_MODELS}poplur_card_swoosh.glb`,
    poster: `${STORE_POSTERS}poplur_card_swoosh.jpg`,
    title: 'Swoosh Card',
    category: 'cards',
    price: '$9.99',
    priceAmount: 9.99,
    credits: 1200,
    kicker: 'MADE TO MOVE',
    tone: 'swoosh',
    description: 'A flowing sculpted card with Poplur motion. Adds 1,200 Poplur Credits after a verified purchase.',
  },
];

const profileStorePromos = profileStoreProducts.map(item => ({
  kicker: item.kicker,
  title: item.title,
  copy: item.description,
  credits: `${item.credits.toLocaleString('en-US')} Poplur Credits`,
  price: item.price,
  product: item.id,
  tone: item.tone,
  model: item.model,
  poster: item.poster,
}));

const storeBagCount = () => profileStoreBag.reduce((total, line) => total + line.quantity, 0);

function storeBagLines() {
  return profileStoreBag.map(line => ({
    ...line,
    product: profileStoreProducts.find(item => item.id === line.cardId),
  })).filter(line => line.product);
}

function storeBagTotal() {
  return storeBagLines().reduce((total, line) => total + (line.product.priceAmount * line.quantity), 0);
}

function formatStoreMoney(amount) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
}

function storeBagMutationIsLocked() {
  if (!profileStoreCheckoutPending) return false;
  profileStoreNotice = 'Checkout is still in progress. Your bag stays locked until the store returns a final result.';
  return true;
}

function addStoreProduct(cardId) {
  if (storeBagMutationIsLocked()) return;
  const productItem = profileStoreProducts.find(item => item.id === cardId);
  if (!productItem) return;
  const existing = profileStoreBag.find(line => line.cardId === cardId);
  if ((existing?.quantity || 0) >= 10 || storeBagCount() >= 20) {
    profileStoreNotice = 'Your bag can hold up to 10 of one card and 20 cards total.';
    return;
  }
  profileStoreBag = existing
    ? profileStoreBag.map(line => line.cardId === cardId ? { ...line, quantity: line.quantity + 1 } : line)
    : [...profileStoreBag, { cardId, quantity: 1 }];
  profileStoreNotice = `${productItem.title} added to your bag.`;
}

function updateStoreQuantity(cardId, delta) {
  if (storeBagMutationIsLocked()) return;
  const current = profileStoreBag.find(line => line.cardId === cardId);
  if (!current) return;
  if (delta > 0 && (current.quantity >= 10 || storeBagCount() >= 20)) {
    profileStoreNotice = 'Your bag can hold up to 10 of one card and 20 cards total.';
    return;
  }
  const nextQuantity = current.quantity + delta;
  profileStoreBag = nextQuantity > 0
    ? profileStoreBag.map(line => line.cardId === cardId ? { ...line, quantity: nextQuantity } : line)
    : profileStoreBag.filter(line => line.cardId !== cardId);
  profileStoreNotice = '';
}

function removeStoreProduct(cardId) {
  if (storeBagMutationIsLocked()) return;
  profileStoreBag = profileStoreBag.filter(line => line.cardId !== cardId);
  profileStoreNotice = '';
}

function removeCompletedStoreItems(completedItems) {
  if (!Array.isArray(completedItems) || !completedItems.length || !Array.isArray(profileStoreCheckoutSnapshot)) return 0;
  const requestedByCard = new Map(profileStoreCheckoutSnapshot.map(line => [line.cardId, line.quantity]));
  const completedByCard = new Map();
  let removed = 0;
  completedItems.forEach(item => {
    const key = String(item?.cardId || item?.productId || item?.id || '');
    const quantity = Math.max(0, Math.floor(Number(item?.quantity) || 0));
    const productItem = profileStoreProducts.find(product =>
      key === product.id || key === product.iosProductId || key === product.androidProductId
    );
    if (!productItem || !quantity) return;
    const requested = requestedByCard.get(productItem.id) || 0;
    const alreadyCompleted = completedByCard.get(productItem.id) || 0;
    completedByCard.set(productItem.id, Math.min(requested, alreadyCompleted + quantity));
  });
  profileStoreBag = profileStoreBag.flatMap(line => {
    const completed = completedByCard.get(line.cardId) || 0;
    removed += Math.min(line.quantity, completed);
    const quantity = line.quantity - completed;
    return quantity > 0 ? [{ ...line, quantity }] : [];
  });
  profileStoreCheckoutSnapshot = profileStoreCheckoutSnapshot.flatMap(line => {
    const quantity = line.quantity - (completedByCard.get(line.cardId) || 0);
    return quantity > 0 ? [{ ...line, quantity }] : [];
  });
  return removed;
}

function requestStoreCheckout() {
  const lines = storeBagLines();
  if (!lines.length) {
    profileStoreNotice = 'Your bag is empty. Choose a card to continue.';
    renderScreen();
    return;
  }
  if (profileStoreCheckoutPending) return;

  profileStoreCheckoutRequestId = window.crypto?.randomUUID?.() ||
    `poplur-store-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  profileStoreCheckoutSnapshot = lines.map(line => ({
    cardId: line.product.id,
    iosProductId: line.product.iosProductId,
    androidProductId: line.product.androidProductId,
    quantity: line.quantity,
  }));
  profileStoreCheckoutPending = true;
  profileStoreNotice = 'Opening secure checkout…';

  const message = {
    type: 'poplurStoreCheckoutRequested',
    requestId: profileStoreCheckoutRequestId,
    currency: 'USD',
    total: Number(storeBagTotal().toFixed(2)),
    items: lines.map(line => ({
      id: line.product.id,
      cardId: line.product.id,
      iosProductId: line.product.iosProductId,
      androidProductId: line.product.androidProductId,
      name: line.product.title,
      quantity: line.quantity,
      unitPrice: line.product.priceAmount,
      credits: line.product.credits,
      creditTotal: line.product.credits * line.quantity,
      lineTotal: Number((line.product.priceAmount * line.quantity).toFixed(2)),
    })),
  };

  if (window.parent === window) {
    profileStoreCheckoutPending = false;
    profileStoreCheckoutRequestId = null;
    profileStoreCheckoutSnapshot = null;
    profileStoreNotice = 'Secure checkout is available in the Poplur app.';
    renderScreen();
    return;
  }
  window.parent.postMessage(message, '*');
  renderScreen();
}

function handleStoreCheckoutResult(data) {
  if (!data || data.type !== 'poplurStoreCheckoutResult') return;
  if (!profileStoreCheckoutPending || typeof profileStoreCheckoutRequestId !== 'string') return;
  if (typeof data.requestId !== 'string' || data.requestId !== profileStoreCheckoutRequestId) return;

  const status = String(data.status || '').toLowerCase();
  if (!['pending', 'success', 'cancelled', 'canceled', 'failure'].includes(status)) return;
  const completed = removeCompletedStoreItems(data.completedItems);
  if (status === 'pending') {
    profileStoreNotice = data.message || (completed
      ? 'Completed items were verified. Your remaining bag stays locked while approval is pending.'
      : 'Purchase approval is pending. Your bag stays locked until the store returns a final result.');
  } else {
    const remainingRequested = Array.isArray(profileStoreCheckoutSnapshot)
      ? profileStoreCheckoutSnapshot.reduce((total, line) => total + line.quantity, 0)
      : 0;
    profileStoreCheckoutPending = false;
    profileStoreCheckoutRequestId = null;
    profileStoreCheckoutSnapshot = null;
    if (status === 'success') {
      if (remainingRequested === 0) {
        profileStoreView = 'catalog';
        profileStoreProduct = null;
      }
      profileStoreNotice = remainingRequested > 0
        ? 'Verified items were removed, but an unmatched item remains in your bag. It was not charged.'
        : (data.message || 'Purchase verified. Your Poplur Credits are ready.');
    } else if (status === 'cancelled' || status === 'canceled') {
      profileStoreNotice = data.message || (completed
        ? 'Checkout stopped after completed items were verified. Unpurchased items remain in your bag.'
        : 'Checkout was cancelled. Your bag is unchanged.');
    } else {
      profileStoreNotice = data.message || (completed
        ? 'Completed items were verified. Unpurchased items remain in your bag.'
        : 'Checkout could not be completed. Your bag is unchanged.');
    }
  }
  renderScreen();
}

window.addEventListener('message', event => {
  if (window.parent !== window && event.source !== window.parent) return;
  handleStoreCheckoutResult(event.data);
});


const profileStats = [
  {
    id: 'posts',
    img: A.statsPosts,
    value: '128',
    label: 'Total Posts',
    delta: '+18 this month',
    description: 'Your publishing pace is above your recent four-week average.',
    benchmark: 'You publish 1.6× more often than creators with a similar radius.',
    driver: 'Food and local-discovery posts account for 61% of your recent radius growth.',
    action: 'Keep the pace, but move one of every four posts into a new city opportunity window.',
    points: [34, 52, 46, 68, 74, 88, 96],
  },
  {
    id: 'reach',
    img: A.statsGoal,
    value: '41.8 km',
    label: 'Radius Reach',
    delta: '+4.2 km today',
    description: 'Harbourfront and downtown posts are extending your active radius.',
    benchmark: 'Your 41.8 km active reach is in the top 18% of nearby creators.',
    driver: 'Fast first-hour reactions are carrying your posts past their original neighbourhoods.',
    action: 'Post in Toronto between 7:30–9:00 PM, then test one global opportunity each week.',
    points: [28, 38, 51, 44, 63, 72, 84],
  },
  {
    id: 'speed',
    img: A.statsOrbit,
    value: '8x',
    label: 'Trending Speed',
    delta: 'Top 12% nearby',
    description: 'Your latest post is spreading eight times faster than your baseline.',
    benchmark: 'Your strongest posts reach their first 100 viewers 6 minutes faster than peers.',
    driver: 'Clear subjects in the first second and comment replies within ten minutes raise velocity.',
    action: 'Lead with the location or payoff immediately and answer the first three comments.',
    points: [18, 26, 44, 39, 58, 78, 92],
  },
  {
    id: 'streak',
    img: H.create,
    value: '12',
    label: 'Creator Streak',
    delta: '12 days',
    description: 'Keep posting daily to reach the next creator streak milestone.',
    benchmark: 'Only 9% of creators in your radius have maintained a streak this long.',
    driver: 'Your strongest days pair one discovery post with one short reply or update.',
    action: 'Protect the streak with a prepared 9–14 second post before your local 9:00 PM cutoff.',
    points: [22, 31, 42, 54, 66, 78, 90],
  },
];

const worldPostingOpportunities = [
  {
    city: 'Toronto',
    region: 'Canada',
    content: 'Food · local discovery',
    window: 'Thu 7:30–9:00 PM local',
    lift: '+31%',
    confidence: '92%',
    reason: 'Viewer demand is climbing while the number of fresh neighbourhood posts is still low.',
    move: 'Lead with the place in the first second, show the payoff by second four, and reply early.',
  },
  {
    city: 'Lagos',
    region: 'Nigeria',
    content: 'Fashion · music',
    window: 'Sat 5:00–7:00 PM local',
    lift: '+24%',
    confidence: '87%',
    reason: 'Weekend reshares are carrying visual culture posts beyond their original radius.',
    move: 'Use a strong reveal, keep the cut under 14 seconds, and add a location-aware caption.',
  },
  {
    city: 'London',
    region: 'United Kingdom',
    content: 'News · live events',
    window: 'Wed 12:00–1:30 PM local',
    lift: '+18%',
    confidence: '84%',
    reason: 'Midday viewers are reacting quickly to concise, place-specific updates.',
    move: 'State what changed, where it happened, and why it matters before the fifth second.',
  },
  {
    city: 'São Paulo',
    region: 'Brazil',
    content: 'Sports · comedy',
    window: 'Sun 6:00–8:00 PM local',
    lift: '+16%',
    confidence: '80%',
    reason: 'Conversation density is high, but creator supply drops after live events finish.',
    move: 'Post the reaction immediately after the event and ask one specific question.',
  },
  {
    city: 'Seoul',
    region: 'South Korea',
    content: 'Tech · beauty',
    window: 'Tue 8:00–10:00 PM local',
    lift: '+14%',
    confidence: '78%',
    reason: 'Saves and repeat views are strongest for fast demonstrations during evening discovery.',
    move: 'Show the finished result first, then explain one technique with captions on.',
  },
];

const profileSettingState = {
  videoDuration: '10s',
  captions: true,
  notifications: true,
  tvGuide: true,
  language: 'English',
  // REAL setting, not a demo row: mirrors poplur.radio.background in the app.
  // In the shell this document shares the app's origin (both served off the
  // poplur-clay:// bundle) so localStorage IS the app's; on the dev workbench
  // (twins on :8945, app on :5173) origins differ, so the value also travels
  // by postMessage — mapRadio.ts answers the query and accepts the writes.
  radioBackground: (() => {
    try { return window.localStorage.getItem('poplur.radio.background') === '1'; } catch { return false; }
  })(),
};

function persistRadioBackground(on) {
  try { window.localStorage.setItem('poplur.radio.background', on ? '1' : '0'); } catch { /* embedded */ }
  try {
    if (window.parent !== window) window.parent.postMessage({ poplurRadioBackground: on }, '*');
  } catch { /* parent gone */ }
}

if (window.parent !== window) {
  // Embedded in the app: ask the app for the current value (covers the
  // cross-origin dev case where our localStorage is not the app's), and adopt
  // whatever it pushes back.
  window.addEventListener('message', (e) => {
    const d = e.data;
    if (d && typeof d === 'object' && 'poplurRadioBackground' in d && !('poplurRadioBackgroundQuery' in d)) {
      profileSettingState.radioBackground = !!d.poplurRadioBackground;
      if (typeof renderScreen === 'function') renderScreen();
    }
  });
  try { window.parent.postMessage({ poplurRadioBackgroundQuery: true }, '*'); } catch { /* solo */ }
}

const params = new URLSearchParams(window.location.search);
const embeddedScreen = params.get('embed');
if (params.get('rcl') === '1') {
  document.body.classList.add('rcl-clay');
}
if (embeddedScreen) {
  // Chrome off the moment the host asks to embed -- BEFORE resolving the id.
  // This class is the only thing hiding the picker sidebar, the GCL refresh bar
  // and the mock status bar/island. Gating it on a successful lookup meant a
  // single stale screen id exposed the entire review catalogue inside the
  // shipped app, complete with a "Last refreshed" banner and a fake clock two
  // millimetres above the real one. The host's ids and this artifact's ids drift
  // independently (camera-ai-chat vs camera-chat, map-home with no counterpart
  // at all), so a miss is expected and must degrade to a blank screen, never to
  // a dev tool.
  document.body.classList.add('embed');
  const embeddedGroup = Object.entries(groups).find(([, group]) => group.screens.some(screen => screen.id === embeddedScreen));
  if (embeddedGroup) {
    activeGroup = embeddedGroup[0];
    activeScreen = embeddedScreen;
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
  stopPhoneThemeChange();
  stopStoreCarousel();
  const group = groups[activeGroup];
  const item = group.screens.find(s => s.id === activeScreen) || group.screens[0];
  screenEl.className = `screen ${activeGroup}-screen`;
  screenEl.innerHTML = item.render();
  if (item.id === 'profile-phone' && typeof window !== 'undefined' && window.setTimeout) {
    window.setTimeout(initPhoneTwin, 0);
  }
  if ((item.id === 'profile-store' || item.id === 'camera-store') && typeof window !== 'undefined' && window.setTimeout) {
    window.setTimeout(initStoreTwin, 0);
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
  const storeTab = e.target.closest('[data-store-tab]');
  if (storeTab) {
    profileStoreTab = storeTab.dataset.storeTab;
    profileStoreSlide = 0;
    renderScreen();
    return;
  }

  const storeSlide = e.target.closest('[data-store-slide]');
  if (storeSlide) {
    setStoreSlide(Number(storeSlide.dataset.storeSlide) || 0);
    return;
  }

  const mailThread = e.target.closest('[data-mail-thread]');
  if (mailThread) {
    profileMailThread = mailThread.dataset.mailThread;
    const threadItem = profileMailThreads.find(item => item.id === profileMailThread);
    if (threadItem) threadItem.unread = 0;
    renderScreen();
    return;
  }

  if (e.target.closest('[data-mail-back]')) {
    profileMailThread = null;
    renderScreen();
    return;
  }

  const storeQuantity = e.target.closest('[data-store-quantity]');
  if (storeQuantity) {
    updateStoreQuantity(storeQuantity.dataset.storeQuantity, Number(storeQuantity.dataset.delta) || 0);
    renderScreen();
    return;
  }

  const storeRemove = e.target.closest('[data-store-remove]');
  if (storeRemove) {
    removeStoreProduct(storeRemove.dataset.storeRemove);
    renderScreen();
    return;
  }

  const storeProduct = e.target.closest('[data-store-product]');
  if (storeProduct) {
    profileStoreProduct = storeProduct.dataset.storeProduct;
    profileStoreView = 'catalog';
    profileStoreNotice = '';
    renderScreen();
    return;
  }

  if (e.target.closest('[data-store-back]')) {
    if (profileStoreView === 'bag') profileStoreView = 'catalog';
    else profileStoreProduct = null;
    profileStoreNotice = '';
    renderScreen();
    return;
  }

  const storeAction = e.target.closest('[data-store-action]');
  if (storeAction) {
    const action = storeAction.dataset.storeAction;
    if (action === 'add') {
      addStoreProduct(profileStoreProduct || profileStorePromos[profileStoreSlide]?.product);
    } else if (action === 'bag') {
      profileStoreProduct = null;
      profileStoreView = 'bag';
      profileStoreNotice = '';
    } else if (action === 'continue') {
      profileStoreView = 'catalog';
      profileStoreNotice = '';
    } else if (action === 'checkout') {
      requestStoreCheckout();
      return;
    }
    renderScreen();
    return;
  }

  const statCard = e.target.closest('[data-stat-key]');
  if (statCard) {
    profileStat = statCard.dataset.statKey;
    renderScreen();
    return;
  }

  if (e.target.closest('[data-stat-back]')) {
    profileStat = null;
    renderScreen();
    return;
  }

  const settingToggle = e.target.closest('[data-setting-toggle]');
  if (settingToggle) {
    const key = settingToggle.dataset.settingToggle;
    if (key in profileSettingState) profileSettingState[key] = !profileSettingState[key];
    // Radio-in-background is live app state, not twin demo state.
    if (key === 'radioBackground') persistRadioBackground(profileSettingState.radioBackground);
    renderScreen();
    return;
  }

  const settingLanguage = e.target.closest('[data-setting-language]');
  if (settingLanguage) {
    profileSettingState.language = settingLanguage.dataset.settingLanguage;
    profileSettingsNotice = `Captions will translate to ${profileSettingState.language}.`;
    renderScreen();
    return;
  }

  const settingPanel = e.target.closest('[data-setting-panel]');
  if (settingPanel) {
    profileSettingsPanel = settingPanel.dataset.settingPanel;
    profileSettingsNotice = '';
    renderScreen();
    return;
  }

  if (e.target.closest('[data-setting-back]')) {
    profileSettingsPanel = null;
    profileSettingsNotice = '';
    renderScreen();
    return;
  }

  const settingChoice = e.target.closest('[data-setting-choice]');
  if (settingChoice) {
    const key = settingChoice.dataset.settingChoice;
    if (key in profileSettingState) profileSettingState[key] = settingChoice.dataset.settingValue;
    profileSettingsNotice = `Video duration changed to ${profileSettingState.videoDuration}.`;
    renderScreen();
    return;
  }

  const settingAction = e.target.closest('[data-setting-action]');
  if (settingAction) {
    const messages = {
      seed: 'Demo content controls opened for this test profile.',
      repair: 'User ID repair test completed without changing account data.',
      backup: 'A test backup is ready to export.',
      signout: 'Sign-out confirmation works. Account state was preserved for testing.',
    };
    profileSettingsNotice = messages[settingAction.dataset.settingAction] || 'This settings route is ready.';
    renderScreen();
    return;
  }

  const colorStep = e.target.closest('[data-phone-step]');
  if (colorStep) {
    stepPhoneColor(Number(colorStep.dataset.phoneStep));
    return;
  }

  const menuChoice = e.target.closest('[data-phone-menu-index]');
  if (menuChoice && activeScreen === 'profile-phone' && phoneMode === 'menu') {
    const choiceIndex = Number(menuChoice.dataset.phoneMenuIndex);
    const items = phoneMenuItems();
    if (Number.isInteger(choiceIndex) && items[choiceIndex]) {
      phoneMenuIndex = choiceIndex;
      phoneVibrate(18);
      playPhoneKeyTone('5');
      activatePhoneMenuItem();
    }
    return;
  }

  const key = e.target.closest('[data-phone-key]');
  if (key) {
    handlePhoneKey(key.dataset.phoneKey);
  }
});

screenEl.addEventListener('submit', e => {
  const form = e.target.closest('[data-mail-compose]');
  if (!form) return;
  e.preventDefault();

  const field = form.elements.message;
  const text = field?.value?.trim();
  const threadItem = profileMailThreads.find(item => item.id === profileMailThread);
  if (!text || !threadItem) return;

  threadItem.messages.push({ from: 'me', text });
  threadItem.preview = text;
  threadItem.unread = 0;
  renderScreen();
  window.setTimeout(() => screenEl.querySelector('[name="message"]')?.focus(), 0);
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

function stopPhoneThemeChange() {
  if (phoneThemeTimer) {
    window.clearTimeout(phoneThemeTimer);
    phoneThemeTimer = null;
  }
  const page = screenEl.querySelector('.phone-page');
  const device = screenEl.querySelector('.popular-phone-device');
  const lcd = screenEl.querySelector('.phone-lcd-overlay');
  page?.classList.remove('phone-theme-changing');
  device?.classList.remove('phone-vibrating');
  lcd?.classList.remove('theme-changed');
}

function stopStoreCarousel() {
  if (storeCarouselTimer) {
    window.clearInterval(storeCarouselTimer);
    storeCarouselTimer = null;
  }
}

function setStoreSlide(index) {
  const count = profileStorePromos.length;
  profileStoreSlide = (index + count) % count;
  const promo = profileStorePromos[profileStoreSlide];
  const featured = screenEl.querySelector('[data-store-featured]');
  if (featured && promo) {
    featured.className = `store-promo ${promo.tone}`;
    featured.setAttribute('aria-label', `${promo.title} featured product`);
    const kicker = featured.querySelector('[data-store-featured-kicker]');
    const title = featured.querySelector('[data-store-featured-title]');
    const copy = featured.querySelector('[data-store-featured-copy]');
    const credits = featured.querySelector('[data-store-featured-credits]');
    const price = featured.querySelector('[data-store-featured-price]');
    const link = featured.querySelector('[data-store-featured-link]');
    const viewer = featured.querySelector('model-viewer');
    if (kicker) kicker.textContent = promo.kicker;
    if (title) title.textContent = promo.title;
    if (copy) copy.textContent = promo.copy;
    if (credits) credits.textContent = promo.credits;
    if (price) price.textContent = promo.price;
    if (link) link.dataset.storeProduct = promo.product;
    if (viewer && viewer.getAttribute('poster') !== promo.poster) viewer.setAttribute('poster', promo.poster);
    if (viewer && viewer.getAttribute('src') !== promo.model) viewer.setAttribute('src', promo.model);
    if (viewer) viewer.setAttribute('alt', `${promo.title} rotating 3D preview`);
  }
  screenEl.querySelectorAll('[data-store-slide]').forEach((dot, dotIndex) => {
    dot.classList.toggle('on', dotIndex === profileStoreSlide);
    dot.setAttribute('aria-current', dotIndex === profileStoreSlide ? 'true' : 'false');
  });
}

function initStoreTwin() {
  if (!screenEl.querySelector('.store-carousel')) return;
  setStoreSlide(profileStoreSlide);
  storeCarouselTimer = window.setInterval(() => setStoreSlide(profileStoreSlide + 1), 3000);
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
  if (rest) rest.src = colorway.rest;
  if (boot) boot.style.backgroundImage = `url("${colorway.boot}")`;
}

function startPhoneBoot() {
  const page = screenEl.querySelector('.phone-page');
  const boot = screenEl.querySelector('.phone-boot-frame');
  const device = screenEl.querySelector('.popular-phone-device');
  if (!page || !boot || !device) return;

  stopPhoneBoot();
  stopPhoneThemeChange();
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
  startPhoneThemeChange();
}

function startPhoneThemeChange() {
  const page = screenEl.querySelector('.phone-page');
  const device = screenEl.querySelector('.popular-phone-device');
  const lcd = screenEl.querySelector('.phone-lcd-overlay');
  if (!page || !device || !lcd) return;

  stopPhoneBoot();
  stopPhoneThemeChange();
  phoneMode = 'theme';
  page.classList.remove('is-booting');
  page.classList.add('is-ready', 'phone-theme-changing');
  device.classList.add('phone-vibrating');
  lcd.classList.add('theme-changed');
  lcd.innerHTML = '<div class="lcd-theme-changed"><span>THEME</span><strong>CHANGED</strong></div>';
  phoneVibrate([52, 34, 52, 34, 82]);
  page.classList.remove('phone-led-flash');
  void page.offsetWidth;
  page.classList.add('phone-led-flash');
  try {
    if (window.parent !== window) window.parent.postMessage({ type: 'poplur-phone-theme-effects' }, '*');
  } catch (_) {}

  phoneThemeTimer = window.setTimeout(() => {
    phoneThemeTimer = null;
    if (activeScreen !== 'profile-phone' || !page.isConnected) return;
    page.classList.remove('phone-theme-changing');
    device.classList.remove('phone-vibrating');
    lcd.classList.remove('theme-changed');
    phoneMode = 'menu';
    renderPhoneMenu();
  }, 1280);
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
  lcd.classList.remove('theme-changed');

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
      ${visible.map((item, offset) => phoneMenuRow(item, start + offset, start + offset === phoneMenuIndex)).join('')}
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

function phoneMenuRow(item, index, selected) {
  return `
    <button type="button" class="lcd-menu-row ${selected ? 'selected' : ''}" data-phone-menu-index="${index}" aria-label="Open ${esc(item.title)}">
      <b>${esc(item.glyph)}</b>
      <span><strong>${esc(item.title)}</strong><em>${esc(item.detail)}</em></span>
    </button>
  `;
}

function handlePhoneKey(key) {
  if (activeScreen !== 'profile-phone') return;
  phoneVibrate(18);
  pulsePhoneKey(key);
  playPhoneKeyTone(key);
  if (phoneMode === 'boot' || phoneMode === 'theme') return;

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

function playPhoneKeyTone(key) {
  const dtmf = {
    '1': [697, 1209], '2': [697, 1336], '3': [697, 1477],
    '4': [770, 1209], '5': [770, 1336], '6': [770, 1477],
    '7': [852, 1209], '8': [852, 1336], '9': [852, 1477],
    '*': [941, 1209], '0': [941, 1336], '#': [941, 1477],
  }[key];
  if (!dtmf) return;
  try {
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) return;
    phoneToneContext ||= new AudioCtor();
    const context = phoneToneContext;
    if (context.state === 'suspended') void context.resume();
    if (phoneToneSuspendTimer) window.clearTimeout(phoneToneSuspendTimer);
    const gain = context.createGain();
    const started = context.currentTime;
    gain.gain.setValueAtTime(0.0001, started);
    gain.gain.exponentialRampToValueAtTime(0.055, started + 0.008);
    gain.gain.setValueAtTime(0.055, started + 0.075);
    gain.gain.exponentialRampToValueAtTime(0.0001, started + 0.115);
    gain.connect(context.destination);
    let ended = 0;
    dtmf.forEach(frequency => {
      const oscillator = context.createOscillator();
      oscillator.type = 'sine';
      oscillator.frequency.setValueAtTime(frequency, started);
      oscillator.connect(gain);
      oscillator.onended = () => {
        oscillator.disconnect();
        ended += 1;
        if (ended === dtmf.length) gain.disconnect();
      };
      oscillator.start(started);
      oscillator.stop(started + 0.12);
    });
    phoneToneSuspendTimer = window.setTimeout(() => {
      phoneToneSuspendTimer = null;
      if (phoneToneContext?.state === 'running') void phoneToneContext.suspend();
    }, 700);
  } catch (_) {}
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
  const selected = profileMailThreads.find(item => item.id === profileMailThread);
  if (selected) {
    return `
      <div class="ios-screen messages profile-scroll-page">
        <div class="profile-subscreen-toolbar">
          <button type="button" class="profile-back" data-mail-back aria-label="Back to messages">‹</button>
          <div class="avatar">${esc(selected.initials)}</div>
          <div>
            <h1>${esc(selected.title)}</h1>
            <span>Active in your Poplur radius</span>
          </div>
        </div>
        <div class="mail-conversation" aria-live="polite">
          ${selected.messages.map(message => `
            <div class="mail-bubble ${message.from === 'me' ? 'mine' : ''}">${esc(message.text)}</div>
          `).join('')}
        </div>
        <form class="mail-compose" data-mail-compose>
          <label class="sr-only" for="profileMailMessage">Message</label>
          <input id="profileMailMessage" name="message" autocomplete="off" placeholder="Message ${esc(selected.title)}">
          <button type="submit" class="profile-action compact">Send</button>
        </form>
      </div>
    `;
  }

  return `
    <div class="ios-screen messages profile-scroll-page">
      <div class="message-top">
        <img src="${H.chat}" alt="">
        <div><h1>Chats</h1><span style="color:#777;font-weight:800">${esc(from)} route · OpenDMsRequested</span></div>
      </div>
      <div class="message-list">
        ${profileMailThreads.map(item => thread(item)).join('')}
      </div>
    </div>
  `;
}

function thread(item) {
  return `
    <button type="button" class="thread thread-button" data-mail-thread="${esc(item.id)}">
      <div class="avatar">${esc(item.initials)}</div>
      <div><strong>${esc(item.title)}</strong><span>${esc(item.preview)}</span></div>
      <div class="video-dot">${item.unread ? item.unread : '›'}</div>
    </button>
  `;
}

function storeModelViewer(item, className) {
  return `<model-viewer class="${className}" src="${esc(item.model)}" poster="${esc(item.poster)}" alt="${esc(item.title)} rotating 3D preview" loading="eager" reveal="auto" auto-rotate rotation-per-second="18deg" camera-controls interaction-prompt="none" environment-image="neutral" shadow-intensity="1" exposure="1.08"></model-viewer>`;
}

function storeScreen() {
  if (profileStoreView === 'bag') return storeBagScreen();

  const selected = profileStoreProducts.find(item => item.id === profileStoreProduct);
  const bagCount = storeBagCount();
  if (selected) {
    return `
      <div class="ios-screen store-page store-new profile-scroll-page">
        <div class="profile-subscreen-toolbar store-toolbar">
          <button type="button" class="profile-back" data-store-back aria-label="Back to store">‹</button>
          <div><h1>${esc(selected.title)}</h1><span>${selected.credits.toLocaleString('en-US')} Poplur Credits</span></div>
          <button type="button" class="store-cart-button" data-store-action="bag" aria-label="Open bag with ${bagCount} items">Bag ${bagCount}</button>
        </div>
        <div class="store-detail">
          <div class="store-detail-visual ${esc(selected.tone)}">${storeModelViewer(selected, 'store-detail-model')}</div>
          <span class="profile-kicker">${esc(selected.kicker)}</span>
          <h2>${esc(selected.title)}</h2>
          <strong class="store-detail-price">${esc(selected.price)}</strong>
          <p>${esc(selected.description)}</p>
          <div class="store-credit-pill">${selected.credits.toLocaleString('en-US')} credits after verified purchase</div>
          <button type="button" class="profile-action wide" data-store-action="add" ${profileStoreCheckoutPending ? 'disabled aria-disabled="true"' : ''}>Add to Bag</button>
          <button type="button" class="profile-secondary-action" data-store-action="bag">View Bag${bagCount ? ` (${bagCount})` : ''}</button>
          ${profileStoreNotice ? `<div class="profile-notice" role="status">${esc(profileStoreNotice)}</div>` : ''}
        </div>
      </div>
    `;
  }

  const featured = profileStorePromos[profileStoreSlide] || profileStorePromos[0];
  const featuredProduct = profileStoreProducts.find(item => item.id === featured.product) || profileStoreProducts[0];
  const tabs = [['featured', 'Featured'], ['cards', 'Cards']];
  const visibleProducts = profileStoreTab === 'featured'
    ? profileStoreProducts
    : profileStoreProducts.filter(item => item.category === profileStoreTab);
  return `
    <div class="ios-screen store-page store-new profile-scroll-page">
      <nav class="store-nav" aria-label="Store categories">
        <img class="store-logo" src="${A.logo}" alt="Poplur">
        <div class="store-tabs">${tabs.map(([id, label]) => `<button type="button" class="${profileStoreTab === id ? 'on' : ''}" data-store-tab="${id}" aria-pressed="${profileStoreTab === id}">${label}</button>`).join('')}</div>
        <button type="button" class="store-cart-button" data-store-action="bag" aria-label="Open bag with ${bagCount} items">Bag ${bagCount}</button>
      </nav>

      <header class="store-heading">
        <span>POPLUR CARDS</span>
        <h1>Pick your card.<br>Power your Poplur.</h1>
        <p>Explore every card in 3D, then add Poplur Credits through verified in-app checkout.</p>
      </header>

      <section class="store-carousel" aria-label="Featured card carousel">
        <article class="store-promo ${esc(featured.tone)}" data-store-featured aria-label="${esc(featured.title)} featured product">
          <div class="store-promo-copy">
            <small data-store-featured-kicker>${esc(featured.kicker)}</small>
            <strong data-store-featured-title>${esc(featured.title)}</strong>
            <em data-store-featured-copy>${esc(featured.copy)}</em>
            <b data-store-featured-credits>${esc(featured.credits)}</b>
            <span data-store-featured-price>${esc(featured.price)}</span>
            <button type="button" class="store-promo-link" data-store-featured-link data-store-product="${esc(featured.product)}">View card</button>
          </div>
          ${storeModelViewer(featuredProduct, 'store-featured-model')}
        </article>
        <div class="store-carousel-dots" aria-label="Choose featured card">
          ${profileStorePromos.map((promo, index) => `<button type="button" class="${index === profileStoreSlide ? 'on' : ''}" data-store-slide="${index}" aria-label="Show ${esc(promo.title)}" aria-current="${index === profileStoreSlide}"></button>`).join('')}
        </div>
      </section>

      <section class="store-products">
        <div class="store-section-title"><img src="${A.storeBag}" alt=""><div><small>CARDS</small><h2>Shop the collection</h2></div></div>
        <div class="product-grid">${visibleProducts.map(product).join('')}</div>
        ${profileStoreNotice ? `<div class="profile-notice" role="status">${esc(profileStoreNotice)}</div>` : ''}
      </section>
    </div>
  `;
}

function storeBagScreen() {
  const lines = storeBagLines();
  const totalCredits = lines.reduce((total, line) => total + (line.product.credits * line.quantity), 0);
  return `
    <div class="ios-screen store-page store-new profile-scroll-page">
      <div class="profile-subscreen-toolbar store-toolbar">
        <button type="button" class="profile-back" data-store-back aria-label="Back to store">‹</button>
        <div><h1>Your Bag</h1><span>${storeBagCount()} item${storeBagCount() === 1 ? '' : 's'}</span></div>
      </div>
      <main class="store-bag">
        ${lines.length ? `
          <div class="store-bag-lines">${lines.map(line => `
            <article class="store-bag-line">
              <img class="store-product-poster" src="${esc(line.product.poster)}" alt="">
              <div class="store-bag-copy"><strong>${esc(line.product.title)}</strong><span>${line.product.credits.toLocaleString('en-US')} credits each</span><b>${formatStoreMoney(line.product.priceAmount * line.quantity)}</b></div>
              <div class="store-quantity" aria-label="Quantity for ${esc(line.product.title)}">
                <button type="button" data-store-quantity="${esc(line.product.id)}" data-delta="-1" aria-label="Decrease quantity" ${profileStoreCheckoutPending ? 'disabled' : ''}>−</button>
                <span>${line.quantity}</span>
                <button type="button" data-store-quantity="${esc(line.product.id)}" data-delta="1" aria-label="Increase quantity" ${profileStoreCheckoutPending || line.quantity >= 10 || storeBagCount() >= 20 ? 'disabled' : ''}>+</button>
              </div>
              <button type="button" class="store-remove" data-store-remove="${esc(line.product.id)}" ${profileStoreCheckoutPending ? 'disabled' : ''}>Remove</button>
            </article>
          `).join('')}</div>
          <section class="store-bag-summary">
            <div><span>Total credits</span><strong>${totalCredits.toLocaleString('en-US')}</strong></div>
            <div><span>Total</span><strong>${formatStoreMoney(storeBagTotal())}</strong></div>
            <p>Credits are added only after Poplur receives a verified purchase result.</p>
            <button type="button" class="store-checkout-button" data-store-action="checkout" ${profileStoreCheckoutPending ? 'disabled aria-busy="true"' : ''}>${profileStoreCheckoutPending ? 'Checkout in progress…' : `Check Out · ${formatStoreMoney(storeBagTotal())}`}</button>
          </section>
        ` : `
          <section class="store-empty-bag"><div class="store-empty-icon">P</div><h2>Your bag is empty.</h2><p>Choose a 3D Poplur card to add credits to your account.</p><button type="button" class="profile-action wide" data-store-action="continue">Shop Cards</button></section>
        `}
        ${profileStoreNotice ? `<div class="profile-notice" role="status">${esc(profileStoreNotice)}</div>` : ''}
      </main>
    </div>
  `;
}

function product(item) {
  return `
    <button type="button" class="product-card product-button" data-store-product="${esc(item.id)}">
      <img class="store-product-poster" src="${esc(item.poster)}" alt="${esc(item.title)} 3D card">
      <small>${esc(item.kicker)}</small>
      <strong>${esc(item.title)}</strong>
      <em>${item.credits.toLocaleString('en-US')} Poplur Credits</em>
      <span>${esc(item.price)} · View</span>
    </button>
  `;
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
  if (profileSettingsPanel) return settingsPanelScreen(profileSettingsPanel);

  const rows = [
    {
      img: ios('settings_ic_film', 'settings_ic_film.png'),
      title: 'Video duration',
      sub: `Current limit: ${profileSettingState.videoDuration}`,
      panel: 'video-duration',
    },
    {
      img: ios('settings_ic_film', 'settings_ic_film.png'),
      title: 'Closed Captions',
      sub: profileSettingState.captions ? 'On' : 'Off',
      toggle: 'captions',
    },
    {
      img: ios('settings_ic_info', 'settings_ic_info.png'),
      title: 'Auto Translation',
      sub: profileSettingState.language,
      panel: 'translation',
    },
    {
      img: ios('settings_ic_bell', 'settings_ic_bell.png'),
      title: 'Notifications',
      sub: profileSettingState.notifications ? 'Daily Poplur alerts' : 'Off',
      toggle: 'notifications',
    },
    {
      img: ios('settings_ic_flask', 'settings_ic_flask.png'),
      title: 'Seed NA (1000)',
      sub: 'Demo content controls',
      panel: 'seed',
    },
    {
      img: ios('settings_ic_play', 'settings_ic_play.png'),
      title: 'TV guide animation',
      sub: profileSettingState.tvGuide ? 'Flip animation on' : 'Animation off',
      toggle: 'tvGuide',
    },
    {
      img: ios('settings_ic_play', 'settings_ic_play.png'),
      title: 'Radio in background',
      sub: profileSettingState.radioBackground
        ? 'Keeps playing when you leave the radio'
        : 'Plays only on the radio screen',
      toggle: 'radioBackground',
    },
    {
      img: ios('settings_ic_wrench', 'settings_ic_wrench.png'),
      title: 'Fix Empty UserIDs',
      sub: 'Maintenance',
      panel: 'repair',
    },
    {
      img: ios('settings_ic_cloud', 'settings_ic_cloud.png'),
      title: 'Back Up Data',
      sub: 'Cloud export',
      panel: 'backup',
    },
    {
      img: ios('settings_ic_info', 'settings_ic_info.png'),
      title: 'About Poplur',
      sub: 'Version and credits',
      panel: 'about',
    },
    {
      img: ios('settings_ic_doc', 'settings_ic_doc.png'),
      title: 'Terms of Service',
      sub: 'Legal',
      panel: 'terms',
    },
  ].map(settingsRow).join('');

  return `
    <div class="ios-screen settings-page profile-scroll-page">
      <div class="settings-hero"><img src="${H.settings}" alt=""><div><h1>Settings</h1><span style="color:var(--subtle);font-weight:800">AppSettingsView</span></div></div>
      <div class="translation-card">
        <div>
          <strong>Translate captions to</strong>
          <span>Current language is ${esc(profileSettingState.language)}</span>
        </div>
        <div class="language-picker">
          ${[
            ['🇺🇸', 'English'],
            ['🇫🇷', 'French'],
            ['🇪🇸', 'Spanish'],
          ].map(([flag, language]) => `
            <button type="button" class="${profileSettingState.language === language ? 'on' : ''}" data-setting-language="${language}">
              ${flag} ${language}
            </button>
          `).join('')}
        </div>
      </div>
      <div class="settings-list">${rows}</div>
      ${settingsRow({
        img: ios('settings_ic_signout', 'settings_ic_signout.png'),
        title: 'Sign Out',
        sub: 'Account',
        panel: 'signout',
        className: 'settings-signout',
      })}
      ${profileSettingsNotice ? `<div class="profile-notice" role="status">${esc(profileSettingsNotice)}</div>` : ''}
    </div>
  `;
}

function settingsRow(item) {
  const attr = item.toggle
    ? `data-setting-toggle="${esc(item.toggle)}"`
    : `data-setting-panel="${esc(item.panel)}"`;
  const state = item.toggle
    ? `<span class="settings-switch ${profileSettingState[item.toggle] ? 'on' : ''}" aria-hidden="true"><i></i></span>`
    : '<b>›</b>';
  return `
    <button type="button" class="settings-row settings-button ${item.className || ''}" ${attr}>
      <img src="${item.img}" alt="">
      <div><strong>${esc(item.title)}</strong><span>${esc(item.sub)}</span></div>
      ${state}
    </button>
  `;
}

function settingsPanelScreen(panel) {
  const panels = {
    'video-duration': {
      title: 'Video duration',
      detail: 'Choose how long a standard Poplur capture may run.',
      choices: ['10s', '30s', '60s'],
    },
    translation: {
      title: 'Auto Translation',
      detail: `Captions currently translate to ${profileSettingState.language}. Use the language controls on the main Settings screen to change it.`,
    },
    seed: {
      title: 'Seed NA',
      detail: 'Preview the demo-content controls without modifying production data.',
      action: ['seed', 'Open demo controls'],
    },
    repair: {
      title: 'Fix Empty UserIDs',
      detail: 'Run the safe test version of the account-maintenance check.',
      action: ['repair', 'Run test repair'],
    },
    backup: {
      title: 'Back Up Data',
      detail: 'Prepare a test archive of profile, message, and post metadata.',
      action: ['backup', 'Prepare test backup'],
    },
    about: {
      title: 'About Poplur',
      detail: 'Poplur Rough Copy interactive subscreens. Built for device-parity testing.',
    },
    terms: {
      title: 'Terms of Service',
      detail: 'This test route opens the legal surface without leaving the Profile flow.',
    },
    signout: {
      title: 'Sign Out',
      detail: 'Confirm that the sign-out route responds. Testing keeps your current account active.',
      action: ['signout', 'Test sign-out confirmation'],
    },
  };
  const item = panels[panel] || panels.about;
  return `
    <div class="ios-screen settings-page profile-scroll-page">
      <div class="profile-subscreen-toolbar">
        <button type="button" class="profile-back" data-setting-back aria-label="Back to settings">‹</button>
        <div>
          <h1>${esc(item.title)}</h1>
          <span>Settings detail</span>
        </div>
      </div>
      <div class="settings-detail-card">
        <img src="${H.settings}" alt="">
        <p>${esc(item.detail)}</p>
        ${item.choices ? `
          <div class="settings-choice-grid">
            ${item.choices.map(value => `
              <button type="button" class="${profileSettingState.videoDuration === value ? 'on' : ''}" data-setting-choice="videoDuration" data-setting-value="${value}">
                ${value}
              </button>
            `).join('')}
          </div>
        ` : ''}
        ${item.action ? `
          <button type="button" class="profile-action wide" data-setting-action="${item.action[0]}">${esc(item.action[1])}</button>
        ` : ''}
        ${profileSettingsNotice ? `<div class="profile-notice" role="status">${esc(profileSettingsNotice)}</div>` : ''}
      </div>
    </div>
  `;
}

function statsScreen() {
  const selected = profileStats.find(item => item.id === profileStat);
  if (selected) {
    return `
      <div class="ios-screen stats-page profile-scroll-page">
        <div class="profile-subscreen-toolbar">
          <button type="button" class="profile-back" data-stat-back aria-label="Back to stats">‹</button>
          <img class="stats-detail-icon" src="${selected.img}" alt="">
          <div>
            <h1>${esc(selected.label)}</h1>
            <span>Profile analytics</span>
          </div>
        </div>
        <div class="stats-detail-card">
          <span class="profile-kicker">LAST 7 DAYS</span>
          <strong class="stats-detail-value">${esc(selected.value)}</strong>
          <span class="stats-detail-delta">${esc(selected.delta)}</span>
          <div class="stats-bars" aria-label="${esc(selected.label)} seven day trend">
            ${selected.points.map((point, index) => `
              <i style="height:${point}%" title="Day ${index + 1}: ${point}%"></i>
            `).join('')}
          </div>
          <p>${esc(selected.description)}</p>
          <div class="stats-detail-explanation">
            <article><span>BENCHMARK</span><p>${esc(selected.benchmark)}</p></article>
            <article><span>WHAT DRIVES IT</span><p>${esc(selected.driver)}</p></article>
            <article><span>NEXT MOVE</span><p>${esc(selected.action)}</p></article>
          </div>
        </div>
      </div>
    `;
  }

  return `
    <div class="ios-screen stats-page stats-world-page profile-scroll-page">
      <header class="stats-world-header">
        <span class="profile-kicker">AI WORLD INTELLIGENCE</span>
        <h1>Your signal, everywhere.</h1>
        <p>Live recommendations from your performance and anonymized aggregate activity across Poplur.</p>
      </header>

      <section class="stats-globe-stage" aria-label="Your worldwide creator performance">
        <div class="stats-globe-halo" aria-hidden="true"></div>
        <div class="stats-globe-spin" aria-hidden="true">
          <div class="stats-globe-sphere">
            <i class="stats-meridian m1"></i>
            <i class="stats-meridian m2"></i>
            <i class="stats-meridian m3"></i>
            <i class="stats-meridian m4"></i>
            <i class="stats-latitude l1"></i>
            <i class="stats-latitude l2"></i>
            <i class="stats-latitude l3"></i>
            <i class="stats-latitude l4"></i>
            <i class="stats-continent c1"></i>
            <i class="stats-continent c2"></i>
            <i class="stats-continent c3"></i>
            <i class="stats-continent c4"></i>
          </div>
        </div>

        <div class="stats-globe-core">
          <strong>74%</strong>
          <span>WORLD GOAL</span>
          <em>on track</em>
        </div>

        ${profileStats.map((item, index) => `
          <button type="button" class="stats-orbit-callout callout-${index + 1}" data-stat-key="${esc(item.id)}" aria-label="Open ${esc(item.label)} details">
            <span>${esc(item.label)}</span>
            <strong>${esc(item.value)}</strong>
            <em>${esc(item.delta)}</em>
          </button>
        `).join('')}

        <div class="stats-live-signal" aria-hidden="true"><i></i><span>AI MODEL LIVE</span></div>
      </section>

      <section class="stats-ai-briefing" aria-label="Worldwide posting opportunities">
        <div class="stats-section-heading">
          <div><span>YOUR NEXT BEST MOVES</span><h2>AI opportunity map</h2></div>
          <strong>5 markets</strong>
        </div>
        <p class="stats-section-copy">Lift estimates compare each market’s current audience demand, creator supply, local time, content fit, and your own history. Times are shown in each city’s local time.</p>
        <div class="stats-opportunity-list">
          ${worldPostingOpportunities.map((item, index) => `
            <article class="stats-opportunity ${index === 0 ? 'priority' : ''}">
              <div class="stats-opportunity-rank">${String(index + 1).padStart(2, '0')}</div>
              <div class="stats-opportunity-main">
                <header>
                  <div><h3>${esc(item.city)}</h3><span>${esc(item.region)}</span></div>
                  <strong>${esc(item.lift)} lift</strong>
                </header>
                <div class="stats-opportunity-tags"><span>${esc(item.content)}</span><span>${esc(item.window)}</span></div>
                <p><b>Why now:</b> ${esc(item.reason)}</p>
                <p><b>What to do:</b> ${esc(item.move)}</p>
                <footer><span>AI confidence</span><strong>${esc(item.confidence)}</strong><i style="--confidence:${esc(item.confidence)}"></i></footer>
              </div>
            </article>
          `).join('')}
        </div>
      </section>

      <section class="stats-improvement-plan" aria-label="Personal improvement plan">
        <div class="stats-section-heading">
          <div><span>PERSONAL PLAYBOOK</span><h2>How to grow your radius</h2></div>
          <strong>Next 7 days</strong>
        </div>
        <ol>
          <li><strong>Protect the hook.</strong><span>Name the place, result, or question in the first 1.5 seconds. Your clearest openings travel 2.3× farther.</span></li>
          <li><strong>Post into demand gaps.</strong><span>Publish Toronto food on Thursday night, then test one global market instead of repeating a saturated local slot.</span></li>
          <li><strong>Create conversation early.</strong><span>Reply to the first three comments within ten minutes. Comments add more radius than passive views.</span></li>
          <li><strong>Keep clips decisive.</strong><span>Your 9–14 second videos retain 19% more viewers than longer posts; captions raise completion in sound-off sessions.</span></li>
        </ol>
      </section>

      <section class="stats-method-card">
        <span class="profile-kicker">HOW THIS AI WORKS</span>
        <h2>Recommendations, explained.</h2>
        <p>The model scores anonymized aggregate demand, active-post supply, completion, reactions, comment velocity, radius change, local time, and category fit. Your personal history adjusts the ranking so the advice is useful to you—not merely globally popular.</p>
        <p>Lift is an estimate, not a guarantee. Confidence falls when a market has less recent activity. No other creator’s private identity or individual behaviour is shown.</p>
      </section>
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
