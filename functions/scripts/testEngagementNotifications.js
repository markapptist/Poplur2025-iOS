const assert = require('node:assert/strict');
const { engagementNotification, engagementIsSynthetic, NOTIFY_FOR_SYNTHETIC_ENGAGEMENT } = require('../lib/engagementNotifications');
for (const kind of ['like', 'view', 'dislike', 'comment']) {
  const delta = kind === 'dislike' ? -1000 : 1000;
  const n = engagementNotification({ kind, applied: true, actorHandle: '@person', radiusDeltaMeters: delta, body: 'A real comment' });
  assert.ok(n);
  assert.match(n.body, delta < 0 ? /Radius decreased 1 km/ : /Radius grew 1 km/);
  if (kind === 'comment') assert.match(n.body, /A real comment/);
  assert.equal(engagementNotification({ kind, applied: false }), null);
}
assert.equal(engagementNotification({ applied: true }), null);
assert.doesNotMatch(engagementNotification({ kind: 'view', applied: true, radiusDeltaMeters: 0 }).body, /grew|decreased/);
assert.doesNotMatch(engagementNotification({ kind: 'like', applied: true, radiusDeltaMeters: NaN }).body, /NaN/);
console.log('Engagement notification policy checks passed');

// ── Simulation engagement must not notify (owner decision, 12 Sep 2026) ──────
// The cohort's hourly batch was landing 32 banners an hour on the owner's
// phone. Classification is by actor, so bot-to-bot is covered by the same rule.
assert.equal(NOTIFY_FOR_SYNTHETIC_ENGAGEMENT, false,
  'beta phase: simulation engagement must stay silent until a human tester exists');

(async () => {
  // Every id the cohort and the lab use is answered by prefix, with no read —
  // if this ever needs a users/{uid} lookup, the trigger pays it ~1,300 times
  // every three hours.
  for (const uid of ['sim-food-001', 'sim-daily-42', 'synthetic-conquer-3']) {
    assert.equal(await engagementIsSynthetic(uid), true, `${uid} should classify as synthetic`);
  }
  // A real Firebase uid has no prefix; with no users doc reachable the lookup
  // fails open and the person still gets their alert.
  assert.equal(await engagementIsSynthetic('eoP2Z0ElxIa0Eua7xpFxNlr6tur1'), false,
    'a real uid must not be classified synthetic by prefix');
  // Unknown actor: cannot tell, so notify — dropping a real alert is worse.
  assert.equal(await engagementIsSynthetic(undefined), false, 'missing actorUid must fail open');
  assert.equal(await engagementIsSynthetic(''), false, 'empty actorUid must fail open');
  console.log('engagement notification tests passed');
})().catch(error => { console.error(error); process.exit(1); });
