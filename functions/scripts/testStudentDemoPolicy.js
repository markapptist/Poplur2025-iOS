// node scripts/testStudentDemoPolicy.js  (after npm run build)
const assert = require("node:assert/strict");
const p = require("../lib/studentDemoPolicy.js");

const cfg = p.parseStudentDemoConfig({ enabled: true, firstBeatMs: 20000, actorsPerPost: 6 });
assert.equal(cfg.enabled, true); assert.equal(cfg.dmEnabled, true); assert.equal(cfg.actorsPerPost, 6);
assert.equal(p.parseStudentDemoConfig(undefined).enabled, false, "off by default");
assert.equal(p.parseStudentDemoConfig({ enabled: true, firstBeatMs: 1 }).firstBeatMs, 5000, "clamped low");

const pool = ["sim-food-001", "sim-sports-002", "sim-music-003", "sim-tech-004", "sim-news-005", "sim-daily-2026-09-18-1", "sim-daily-2026-09-18-2", "owner-uid"];
const now = 1_700_000_000_000;
const plan = p.buildDemoPlan("post-abc", "owner-uid", pool, cfg, now);
assert.ok(plan, "plan built");
assert.equal(plan.steps.length, 9);
assert.equal(plan.steps[0].dueAtMillis, now + 20000, "first beat = firstBeatMs");
assert.ok(plan.steps.every(s => s.actorUid !== "owner-uid"), "owner never reacts to own post");
assert.ok(plan.steps.some(s => s.kinds.includes("comment") && s.comment), "comments carry text");
assert.ok(plan.steps.some(s => s.dm), "one step opens a conversation");
assert.equal(plan.nextDueAtMillis, plan.steps[0].dueAtMillis);
const again = p.buildDemoPlan("post-abc", "owner-uid", pool, cfg, now);
assert.deepEqual(again, plan, "deterministic from the post id");
const other = p.buildDemoPlan("post-xyz", "owner-uid", pool, cfg, now);
assert.notDeepEqual(other.steps.map(s => s.actorUid), plan.steps.map(s => s.actorUid), "different post, different faces");
const noDm = p.buildDemoPlan("post-abc", "owner-uid", pool, { ...cfg, dmEnabled: false }, now);
assert.ok(noDm.steps.every(s => !s.dm), "dm can be switched off");
assert.equal(p.buildDemoPlan("post-1", "solo", ["solo"], cfg, now), null, "no actors → no plan");

assert.match(p.demoEventId("post-abc", 3, "like"), /^demo-[0-9a-f]+-3-like$/);
assert.match(p.demoMessageId("seed"), /^msg-[A-Za-z0-9-]{16,96}$/, "DM rules accept the id");
assert.equal(p.canonicalThreadId("b", "a"), "a_b");
assert.ok(p.demoEligiblePost({ status: "published", audience: "public" }));
assert.ok(!p.demoEligiblePost({ officialContent: true }));
assert.ok(!p.demoEligiblePost({ status: "deleted" }));
assert.ok(!p.demoEligiblePost({ audience: "private" }));
plan.steps[0].done = true; plan.steps[1].done = true;
assert.equal(p.nextDue(plan.steps), plan.steps[2].dueAtMillis);
plan.steps.forEach(s => { s.done = true; });
assert.equal(p.nextDue(plan.steps), null);
for (const list of [p.DEMO_COMMENTS, p.DEMO_DM_OPENERS, p.DEMO_DM_REPLIES]) for (const t of list) assert.ok(t.length > 0 && t.length <= 500);
console.log("studentDemoPolicy: all assertions passed");
