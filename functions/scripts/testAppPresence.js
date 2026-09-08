const assert = require('node:assert/strict');
const { countPresentPeople, presenceInput, updateAppPresence } = require('../lib/appPresence');

const now = Date.now();
assert.equal(countPresentPeople([
  { uid: 'a', activeUntilMs: now + 60000 },
  { uid: 'a', activeUntilMs: now + 60000 }, // second phone, same person
  { uid: 'b', activeUntilMs: now }, // expired
  { uid: 'c', activeUntilMs: now + 60000, synthetic: true },
  { uid: 'd', activeUntilMs: now + 60000 },
  { uid: 'e', activeUntilMs: now + 10000000 }, // malformed lease
], now), 2);
assert.throws(() => presenceInput({ session: 'bad', active: true, sequence: 1 }));
assert.deepEqual(presenceInput({ session: 'test-session-1234', active: true, sequence: 1, uid: 'spoofed', screen: 'private' }),
  { session: 'test-session-1234', active: true, sequence: 1 });

// Exercise the complete transaction and aggregate with a small Firestore port.
// No live accounts, sessions or production counters are modified by this test.
const rows = new Map();
const db = {
  collection: () => ({
    doc: key => ({ key }),
    where: () => ({ select: () => ({ get: async () => ({ docs: [...rows.values()].map(value => ({ data: () => value })) }) }) }),
  }),
  runTransaction: async fn => fn({
    get: async ref => ({ data: () => rows.get(ref.key) }),
    set: (ref, value) => rows.set(ref.key, value),
  }),
};
(async () => {
  const send = (uid, session, sequence, active, synthetic = false) =>
    updateAppPresence(db, uid, synthetic, { session, sequence, active });
  const a = 'phone-session-1234', b = 'tablet-session-1234';
  assert.equal((await send('person', a, 1, true)).peopleOnline, 1);
  assert.equal((await send('person', b, 1, true)).peopleOnline, 1);
  assert.equal((await send('person', a, 3, false)).peopleOnline, 1); // other device still open
  assert.equal((await send('person', b, 2, false)).peopleOnline, 0);
  assert.equal((await send('person', a, 2, true)).peopleOnline, 0); // delayed foreground
  assert.equal((await send('robot', a, 1, true, true)).peopleOnline, 0);
  const result = await send('person', a, 4, true);
  assert.equal(result.peopleOnline, 1);
  assert.deepEqual(Object.keys(result).sort(), ['asOfMs', 'peopleOnline', 'validForMs']);
  console.log('App presence: expiry, deduplication, background, request ordering, privacy PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
