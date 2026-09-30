/**
 * Reports, against the real rules engine: a person report as before, a pop
 * report that names the pop, and everything the rule must refuse.
 *
 *   firebase emulators:exec --only firestore "node scripts/testReportRules.mjs"
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { addDoc, collection, doc, getDoc, serverTimestamp } from "firebase/firestore";

const here = dirname(fileURLToPath(import.meta.url));
const env = await initializeTestEnvironment({
  projectId: "demo-poplur-reports",
  firestore: { rules: readFileSync(join(here, "../../firestore.rules"), "utf8") },
});
let passed = 0;
const check = async (name, fn) => { await fn(); passed += 1; console.log(`PASS ${name}`); };
const reports = (uid) => collection(env.authenticatedContext(uid).firestore(), "reports");
const person = { reporterId: "reporter", userId: "poster", username: "poster", reason: "profile", source: "profile", platform: "android", createdAt: serverTimestamp() };
const pop = { ...person, reason: "pop", source: "post", postId: "post-123" };
try {
  await check("a person report is accepted as before", () => assertSucceeds(addDoc(reports("reporter"), person)));
  await check("a pop report that names the pop is accepted", () => assertSucceeds(addDoc(reports("reporter"), pop)));
  await check("reporting your own pop is refused", () => assertFails(addDoc(reports("poster"), { ...pop, reporterId: "poster" })));
  await check("an empty pop id is refused", () => assertFails(addDoc(reports("reporter"), { ...pop, postId: "" })));
  await check("an over-long pop id is refused", () => assertFails(addDoc(reports("reporter"), { ...pop, postId: "x".repeat(129) })));
  await check("a pop id that is not text is refused", () => assertFails(addDoc(reports("reporter"), { ...pop, postId: 42 })));
  await check("an unknown field is refused", () => assertFails(addDoc(reports("reporter"), { ...pop, note: "extra" })));
  await check("filing as someone else is refused", () => assertFails(addDoc(reports("reporter"), { ...pop, reporterId: "someone-else" })));
  await check("signed-out reports are refused", () => assertFails(addDoc(collection(env.unauthenticatedContext().firestore(), "reports"), pop)));
  await check("nobody can read reports from a client", () => assertFails(getDoc(doc(env.authenticatedContext("reporter").firestore(), "reports", "any"))));
  console.log(`${passed} report rule checks passed`);
} finally {
  await env.cleanup();
}
