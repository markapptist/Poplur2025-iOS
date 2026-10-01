/**
 * Ringing a closed iPhone (lib/callRingApple.js, A7's iPhone half): the APNs
 * provider token, the VoIP push and its headers, which tokens are rung and
 * which are pruned. A throwaway P-256 key stands in for the APNs key and a
 * local HTTP/2 server for APNs; nothing leaves the machine.
 *
 *   npm run build && node scripts/testCallRingApple.mjs
 */
import { createRequire } from "node:module";
import { generateKeyPairSync, verify } from "node:crypto";
import { createServer } from "node:http2";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const {
  apnsJwt, voipTokens, voipPayload, isDeadToken, sendVoip, VOIP_TOPIC, APNS_TEAM_ID,
} = require("../lib/callRingApple.js");
const { callPushFor } = require("../lib/callNotifications.js");

let passed = 0;
const check = async (name, fn) => { await fn(); passed += 1; console.log(`PASS ${name}`); };
const decode = (part) => JSON.parse(Buffer.from(part.replace(/-/g, "+").replace(/_/g, "/"), "base64").toString("utf8"));
const hex = (byte, length = 32) => byte.repeat(length);

await check("the provider token is an ES256 JWT APNs can verify", () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });
  const jwt = apnsJwt(pem, "ABC123DEFG", APNS_TEAM_ID, 1_790_000_000);
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(decode(header), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(decode(claims), { iss: "VDQS4882Z8", iat: 1_790_000_000 });
  const raw = Buffer.from(signature.replace(/-/g, "+").replace(/_/g, "/"), "base64");
  assert.equal(raw.length, 64, "JWS wants r||s, not DER");
  assert.ok(verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, raw));
});

await check("only well-formed tokens ring, each against its own APNs", () => {
  const tokens = voipTokens({
    voipTokens: {
      [hex("AB")]: { env: "production" },
      [hex("cd")]: { env: "development" },
      [hex("ef")]: {},
      "not-a-token": { env: "production" },
      [hex("1", 63)]: { env: "production" },
    },
  });
  assert.deepEqual(tokens, [
    { token: hex("ab"), env: "production" },
    { token: hex("cd"), env: "development" },
    { token: hex("ef"), env: "production" },
  ]);
  assert.deepEqual(voipTokens(undefined), []);
  assert.deepEqual(voipTokens({ fcmTokens: { x: { platform: "ios" } } }), []);
});

await check("the push carries what CallKit shows, and who it is for", () => {
  const push = callPushFor("call-9", undefined, {
    participants: ["callee", "caller"], callerId: "caller", callerName: "Sam", calleeId: "callee",
    status: "ringing", video: false, provider: "webrtc",
  });
  assert.deepEqual(JSON.parse(voipPayload(push.data, push.calleeId)), {
    aps: {}, kind: "incoming_call", callId: "call-9", callerId: "caller", callerName: "Sam",
    video: "false", context: "default", calleeId: "callee",
  });
});

await check("gone and foreign tokens are pruned; a bad payload or an outage is not", () => {
  assert.equal(isDeadToken({ token: "t", status: 410, reason: "Unregistered" }), true);
  assert.equal(isDeadToken({ token: "t", status: 400, reason: "BadDeviceToken" }), true);
  assert.equal(isDeadToken({ token: "t", status: 400, reason: "DeviceTokenNotForTopic" }), true);
  assert.equal(isDeadToken({ token: "t", status: 400, reason: "BadExpirationDate" }), false);
  assert.equal(isDeadToken({ token: "t", status: 503, reason: "ServiceUnavailable" }), false);
  assert.equal(isDeadToken({ token: "t", status: 0, reason: "timeout" }), false);
  assert.equal(isDeadToken({ token: "t", status: 200 }), false);
});

await check("each iPhone gets one VoIP request with APNs's headers, on its environment's host", async () => {
  const seen = [];
  const server = createServer();
  server.on("stream", (stream, headers) => {
    let body = "";
    stream.setEncoding("utf8");
    stream.on("data", (chunk) => { body += chunk; });
    stream.on("end", () => {
      seen.push({ headers, body });
      const token = headers[":path"].split("/").pop();
      if (token === hex("aa")) {
        stream.respond({ ":status": 200 });
        stream.end();
      } else if (token === hex("bb")) {
        stream.respond({ ":status": 410, "content-type": "application/json" });
        stream.end(JSON.stringify({ reason: "Unregistered", timestamp: 1 }));
      } else {
        stream.respond({ ":status": 400, "content-type": "application/json" });
        stream.end(JSON.stringify({ reason: "BadDeviceToken" }));
      }
    });
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    const results = await sendVoip(
      [
        { token: hex("aa"), env: "production" },
        { token: hex("bb"), env: "production" },
        { token: hex("cc"), env: "development" },
      ],
      '{"kind":"incoming_call"}',
      "header.claims.signature",
      1_790_000_045,
      { production: origin, development: origin },
    );
    assert.deepEqual(results, [
      { token: hex("aa"), status: 200, reason: undefined },
      { token: hex("bb"), status: 410, reason: "Unregistered" },
      { token: hex("cc"), status: 400, reason: "BadDeviceToken" },
    ]);
    assert.equal(seen.length, 3);
    for (const { headers, body } of seen) {
      assert.equal(headers[":method"], "POST");
      assert.match(headers[":path"], /^\/3\/device\/[0-9a-f]{64}$/);
      assert.equal(headers.authorization, "bearer header.claims.signature");
      assert.equal(headers["apns-topic"], VOIP_TOPIC);
      assert.equal(VOIP_TOPIC, "com.apptist.Poplur2025.voip");
      assert.equal(headers["apns-push-type"], "voip");
      assert.equal(headers["apns-priority"], "10");
      assert.equal(headers["apns-expiration"], "1790000045");
      assert.equal(body, '{"kind":"incoming_call"}');
    }
    assert.deepEqual(results.filter(isDeadToken).map((result) => result.token), [hex("bb"), hex("cc")]);
  } finally {
    server.close();
  }
});

await check("an unreachable APNs fails the request instead of the function", async () => {
  const results = await sendVoip(
    [{ token: hex("dd"), env: "production" }],
    "{}",
    "jwt",
    1,
    { production: "http://127.0.0.1:9", development: "http://127.0.0.1:9" },
  );
  assert.equal(results.length, 1);
  assert.equal(results[0].status, 0);
  assert.equal(isDeadToken(results[0]), false);
});

console.log(`${passed} checks passed`);
