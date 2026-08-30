const assert = require("node:assert/strict");
const {
  TEST_ACTIVITY_SCREEN_IDS,
  privacySafeTestActivityHeartbeat,
} = require("../lib/testActivity.js");

const EXPECTED_SCREENS = [
  "home", "map", "feed", "camera", "camera-roll", "profile",
  "hold-menu", "upload-flows", "arcade", "games", "battle",
  "map-conquer", "map-directions", "map-ipod", "map-radio", "map-show-me",
  "feed-apps", "feed-browser", "feed-casino", "feed-games", "feed-news", "feed-tvguide",
  "camera-ai-chat", "camera-studio",
  "profile-avatar", "profile-house", "profile-messages", "profile-notifications",
  "profile-phone", "profile-settings", "profile-stats", "profile-store",
  "profile-trophies", "profile-wallet", "profile-wardrobe",
];

assert.deepEqual([...TEST_ACTIVITY_SCREEN_IDS].sort(), [...EXPECTED_SCREENS].sort());

const heartbeat = privacySafeTestActivityHeartbeat({
  screen: "profile-messages",
  status: "foreground",
  platform: "native",
  appVersion: "0.1.0",
  message: "must not leave the client",
  media: "must not leave the client",
  latitude: 43.6532,
  longitude: -79.3832,
  typedInput: "must not leave the client",
  microphone: true,
  camera: true,
});

assert.deepEqual(heartbeat, {
  screen: "profile-messages",
  status: "foreground",
  platform: "native",
  appVersion: "0.1.0",
});
assert.deepEqual(Object.keys(heartbeat).sort(), ["appVersion", "platform", "screen", "status"]);

assert.deepEqual(
  privacySafeTestActivityHeartbeat({
    screen: "message-body:private text",
    status: "tracking",
    platform: "unknown",
    appVersion: "private-build-name",
  }),
  {
    screen: "home",
    status: "foreground",
    platform: "browser",
    appVersion: "0.1.0",
  },
);

console.log("testActivity privacy contract: PASS");
