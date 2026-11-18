/**
 * Track rows, against the real rules engine: anyone can read them, so their
 * place must be the ~110 m public cell (0.001 degree), never the exact spot.
 *
 *   firebase emulators:exec --only firestore "node scripts/testTrackRules.mjs"
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";

const here = dirname(fileURLToPath(import.meta.url));
const env = await initializeTestEnvironment({
  projectId: "demo-poplur-tracks",
  firestore: { rules: readFileSync(join(here, "../../firestore.rules"), "utf8") },
});
let passed = 0;
const check = async (name, fn) => { await fn(); passed += 1; console.log(`PASS ${name}`); };
const db = (uid) => env.authenticatedContext(uid).firestore();
// The same rounding the shells use: Swift .rounded() (half away from zero)
// and Kotlin roundToInt() (half up).
const swiftCell = (v) => (Math.sign(v) * Math.round(Math.abs(v) * 1000)) / 1000;
const kotlinCell = (v) => Math.round(v * 1000) / 1000;
const row = (lat, lng) => ({
  userID: "artist", title: "Night bus", audioURL: "https://example.test/a.wav",
  lat, lng, createdAt: serverTimestamp(), createdAtMillis: Date.now(), licence: "own-work",
  artist: "artist", postedBy: "artist",
});
let n = 0;
const put = (uid, data) => setDoc(doc(db(uid), "tracks", `t${++n}`), data);
try {
  await check("a track on the public grid is accepted", () => assertSucceeds(put("artist", row(43.653, -79.383))));
  await check("a track at the exact spot is refused", () => assertFails(put("artist", row(43.6532107, -79.3831843))));
  await check("an exact latitude alone is refused", () => assertFails(put("artist", row(43.6532107, -79.383))));
  await check("an exact longitude alone is refused", () => assertFails(put("artist", row(43.653, -79.3831843))));
  await check("four decimals is refused", () => assertFails(put("artist", row(43.6531, -79.383))));
  await check("a whole-degree spot is accepted", () => assertSucceeds(put("artist", row(43, -79))));

  // Every hemisphere, both shells' rounding: what the apps send must pass.
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let i = 0; i < 40; i += 1) {
    const lat = rand() * 180 - 90;
    const lng = rand() * 360 - 180;
    await assertSucceeds(put("artist", row(swiftCell(lat), swiftCell(lng))));
    await assertSucceeds(put("artist", row(kotlinCell(lat), kotlinCell(lng))));
    await assertFails(put("artist", row(lat, lng)));
  }
  passed += 1; console.log("PASS 40 random places: both shells' rounding accepted, the exact spot refused");

  const ref = doc(db("artist"), "tracks", "t1");
  await check("renaming a track is still allowed", () => assertSucceeds(updateDoc(ref, { title: "Night bus 2" })));
  await check("moving a track to another cell is allowed", () => assertSucceeds(updateDoc(ref, { lat: 43.654, lng: -79.384 })));
  await check("moving a track to an exact spot is refused", () => assertFails(updateDoc(ref, { lat: 43.6541234 })));
  await check("anyone signed out can still read a track", () => assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "tracks", "t1"))));
  await check("posting as someone else is still refused", () => assertFails(put("intruder", row(43.653, -79.383))));
  console.log(`${passed} track rule checks passed`);
} finally {
  await env.cleanup();
}
