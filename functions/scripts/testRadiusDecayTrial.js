const assert = require('node:assert/strict');
const { calculateRadiusDecay } = require('../lib/postEngagementPolicy');
const { radiusLossNotification } = require('../lib/radiusLossNotifications');
const day = 86400000, start = 1700000000000;
const post = { organicRadiusMeters: 100000, seedRadiusMeters: 5000, radiusMeters: 105000, decayedAt: { toMillis: () => start } };
const trial = { multiplier: 5, effectiveAtMillis: start };
const normal = calculateRadiusDecay(post, start + day);
const fast = calculateRadiusDecay(post, start + day, undefined, trial);
assert.equal(normal.organicRadiusMeters, 95000);
assert.equal(fast.organicRadiusMeters, Math.floor(100000 * .95 ** 5));
assert.equal(fast.seedRadiusMeters, Math.floor(5000 * .95 ** 5));
const delayed = calculateRadiusDecay(post, start + 2 * day, undefined, { ...trial, effectiveAtMillis: start + day });
assert.equal(delayed.organicRadiusMeters, Math.floor(100000 * .95 ** 6));
assert.equal(delayed.seedRadiusMeters, fast.seedRadiusMeters);
assert.equal(calculateRadiusDecay(post, start + 30 * 1000, undefined, trial), null);
const seedOnly = { ...post, organicRadiusMeters: 0, radiusMeters: 5000 };
assert.equal(calculateRadiusDecay(seedOnly, start + day, undefined, trial).seedRadiusMeters, fast.seedRadiusMeters);
const expired = calculateRadiusDecay(post, start + 100 * day, undefined, trial);
assert.equal(expired.radiusMeters, 0);
assert.equal(expired.organicRadiusMeters, 0);
assert.equal(expired.seedRadiusMeters, 0);
assert.match(radiusLossNotification({ cause: 'decay', delta: -100, radiusMeters: 0 }).body, /decreased 0.1 km.*expired/);
for (const entry of [{cause:'like',delta:-100}, {cause:'decay',delta:0}, {cause:'decay',delta:NaN}]) assert.equal(radiusLossNotification(entry), null);
console.log('Radius trial: exact 5x time, activation boundary, seed-only decay, zero expiry and loss notification checks passed');

// Legacy demo provisioning wrote reach into the boost component without a purchase.
const legacy = { organicRadiusMeters: 0, boostedRadiusMeters: 6371000, radiusMeters: 6371000, decayedAt: { toMillis: () => start } };
const allComponents = { ...trial, boostedEffectiveAtMillis: start + day };
assert.equal(calculateRadiusDecay(legacy, start + day, undefined, allComponents), null);
const legacyNext = calculateRadiusDecay(legacy, start + 2 * day, undefined, allComponents);
assert.equal(legacyNext.boostedRadiusMeters, Math.floor(6371000 * .95 ** 5));
assert.equal(legacyNext.radiusMeters, legacyNext.boostedRadiusMeters);
assert.equal(calculateRadiusDecay(legacy, start + 100 * day, undefined, allComponents).radiusMeters, 0);
assert.equal(calculateRadiusDecay(legacy, start + 2 * day, undefined, trial), null);
console.log('Legacy seeded reach: explicit activation, exact 5x decay, and zero expiry passed');

const { radiusDecayRates } = require('../lib/postEngagementPolicy');
const hour = 3600000;
const rapid = { multiplier: 10, effectiveAtMillis: start, boostedEffectiveAtMillis: start,
  halfLifeHours: 6, halfLifeEffectiveAtMillis: start + day };
const mixed = { organicRadiusMeters: 100000, seedRadiusMeters: 5000, boostedRadiusMeters: 10000,
  radiusMeters: 115000, decayedAt: { toMillis: () => start } };
const boundary = calculateRadiusDecay(mixed, start + day, undefined, rapid);
assert.equal(boundary.organicRadiusMeters, Math.floor(100000 * .95 ** 10));
const spanning = calculateRadiusDecay(mixed, start + day + 6 * hour, undefined, rapid);
assert.equal(spanning.organicRadiusMeters, Math.floor(100000 * .95 ** 10 * .5));
assert.equal(spanning.seedRadiusMeters, Math.floor(5000 * .95 ** 10 * .5));
assert.equal(spanning.boostedRadiusMeters, Math.floor(10000 * .95 ** 10 * .5));
const fresh = { ...mixed, decayedAt: { toMillis: () => start + day } };
assert.equal(calculateRadiusDecay(fresh, start + day + 6 * hour, undefined, rapid).organicRadiusMeters, 50000);
assert.equal(calculateRadiusDecay(fresh, start + 3 * day, undefined, rapid).radiusMeters, 0);
assert.deepEqual(radiusDecayRates(start + day, rapid), {organic: .9375, seed: .9375, boost: .9375});
assert.equal(radiusDecayRates(start + day - 1, rapid).organic, 1 - .95 ** 10);
for (const halfLifeHours of [0, -1, NaN, Infinity, 25]) {
  assert.equal(calculateRadiusDecay(mixed, start + day + 6 * hour, undefined, { ...rapid, halfLifeHours }).organicRadiusMeters,
    Math.floor(100000 * .95 ** 12.5));
}
// A user opening the app is not engagement and never resets this server clock.
const untouched = { ...fresh, updatedAt: { toMillis: () => start + 3 * day } };
assert.equal(calculateRadiusDecay(untouched, start + 3 * day, undefined, rapid).radiusMeters, 0);
// Frequent hourly ticks and one catch-up run agree apart from metre rounding.
let stepped = fresh;
for (let n = 1; n <= 12; n++) {
  const now = start + day + n * hour;
  stepped = { ...stepped, ...calculateRadiusDecay(stepped, now, undefined, rapid), decayedAt: { toMillis: () => now } };
}
const catchup = calculateRadiusDecay(fresh, start + day + 12 * hour, undefined, rapid);
assert.ok(Math.abs(stepped.radiusMeters - catchup.radiusMeters) <= 36);
console.log('Six-hour half-life: activation boundary, all components, 48-hour expiry, clock ownership, malformed config, projection and missed-tick catch-up passed');

const { radiusInactivityDeadline, MAX_POST_RADIUS_METERS } = require('../lib/postEngagementPolicy');
const bounded = { ...rapid, halfLifeHours:3, halfLifeEffectiveAtMillis:start,
  inactivityExpiryHours:24, inactivityEffectiveAtMillis:start };
const world = { organicRadiusMeters:MAX_POST_RADIUS_METERS, seedRadiusMeters:0,
  radiusMeters:MAX_POST_RADIUS_METERS, decayedAt:{toMillis:()=>start} };
assert.equal(radiusInactivityDeadline(world,bounded,start),start+day);
assert.ok(calculateRadiusDecay(world,start+day-1,undefined,bounded,start).radiusMeters>0);
assert.equal(calculateRadiusDecay(world,start+day,undefined,bounded,start).radiusMeters,0);
const engaged={...world,lastEngagementAt:{toMillis:()=>start+12*hour}};
assert.equal(radiusInactivityDeadline(engaged,bounded,start),start+36*hour);
assert.ok(calculateRadiusDecay(engaged,start+day,undefined,bounded,start).radiusMeters>0);
assert.equal(calculateRadiusDecay(engaged,start+36*hour,undefined,bounded,start).radiusMeters,0);
const forged={...world,createdAt:{toMillis:()=>start+100*day},createdAtMillis:start+100*day,updatedAt:start+100*day};
assert.equal(radiusInactivityDeadline(forged,bounded,start),start+day);
assert.equal(calculateRadiusDecay(forged,start+day,undefined,bounded,start).radiusMeters,0);
assert.equal(radiusInactivityDeadline(world,{...bounded,inactivityEffectiveAtMillis:start+day},start),start+2*day);
assert.deepEqual(radiusDecayRates(start,bounded),{organic:.99609375,seed:.99609375,boost:.99609375});
console.log('24-hour ceiling: world-sized post, engagement clock, server creation metadata, activation grace and three-hour projection passed');
