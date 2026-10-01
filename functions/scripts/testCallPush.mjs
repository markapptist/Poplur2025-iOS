/**
 * Which call writes ring a callee's Android phone, and which take the ring down
 * (lib/callNotifications.js, A7). Pure decisions; no emulator or network.
 *
 *   npm run build && node scripts/testCallPush.mjs
 */
import { createRequire } from "node:module";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const { callPushFor, androidTokens, RING_TTL_MS } = require("../lib/callNotifications.js");

const ringing = {
  participants: ["callee", "caller"],
  callerId: "caller",
  callerName: "Sam",
  calleeId: "callee",
  status: "ringing",
  video: false,
  provider: "webrtc",
};

let passed = 0;
const check = (name, fn) => { fn(); passed += 1; console.log(`PASS ${name}`); };

check("a new ringing call rings the callee with everything the ringing screen needs", () => {
  const push = callPushFor("call-1", undefined, ringing);
  assert.deepEqual(push, {
    calleeId: "callee",
    ttlMs: RING_TTL_MS,
    data: { kind: "incoming_call", callId: "call-1", callerId: "caller", callerName: "Sam", video: "false", context: "default" },
  });
  assert.equal(RING_TTL_MS, 45_000);
});

check("a video call and a House call say so", () => {
  const push = callPushFor("call-2", undefined, { ...ringing, video: true, context: "house" });
  assert.equal(push.data.video, "true");
  assert.equal(push.data.context, "house");
});

check("answer, decline, hang-up and deletion all take the ring down", () => {
  for (const after of [{ ...ringing, status: "connected" }, { ...ringing, status: "declined" }, { ...ringing, status: "ended" }, undefined]) {
    const push = callPushFor("call-1", ringing, after);
    assert.equal(push.calleeId, "callee");
    assert.equal(push.data.kind, "call_cancel");
    assert.equal(push.data.callId, "call-1");
    assert.equal(push.data.status, after?.status ?? "ended");
  }
});

check("writes that keep a call ringing push nothing (the offer, the answer merge, candidates)", () => {
  assert.equal(callPushFor("call-1", ringing, { ...ringing, offer: { type: "offer", sdp: "v=0" } }), null);
  assert.equal(callPushFor("call-1", { ...ringing, status: "connected" }, { ...ringing, status: "ended" }), null);
  assert.equal(callPushFor("call-1", undefined, { ...ringing, status: "ended" }), null);
});

check("only WebRTC calls ring; the old Agora documents are left alone", () => {
  assert.equal(callPushFor("call-3", undefined, { ...ringing, provider: "agora" }), null);
  assert.equal(callPushFor("call-3", { ...ringing, provider: "agora" }, undefined), null);
});

check("a call to yourself or without both people never rings", () => {
  assert.equal(callPushFor("call-4", undefined, { ...ringing, calleeId: "caller" }), null);
  assert.equal(callPushFor("call-4", undefined, { ...ringing, calleeId: "" }), null);
  assert.equal(callPushFor("call-4", undefined, { ...ringing, callerId: undefined }), null);
});

check("a missing caller name still rings, as Someone", () => {
  assert.equal(callPushFor("call-5", undefined, { ...ringing, callerName: "  " }).data.callerName, "Someone");
});

check("only Android devices are sent the ring; iPhones wait for CallKit", () => {
  assert.deepEqual(androidTokens({
    fcmTokens: {
      "android-1": { platform: "android" },
      "ios-1": { platform: "ios" },
      "android-2": { platform: "android" },
      "unknown": {},
    },
  }), ["android-1", "android-2"]);
  assert.deepEqual(androidTokens(undefined), []);
  assert.deepEqual(androidTokens({ fcmTokens: null }), []);
});

console.log(`${passed} call push checks passed`);
