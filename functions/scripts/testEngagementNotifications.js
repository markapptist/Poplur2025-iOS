const assert = require('node:assert/strict');
const { engagementNotification } = require('../lib/engagementNotifications');
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
