const assert = require('node:assert/strict');
const {
  DEFAULT_NOTIFICATION_PREFS, normalisePrefs, prefsFromUser, pushAllowed, validatedPatch,
} = require('../lib/notificationPrefs');

// ── Absent means permissive ───────────────────────────────────────────────────
// Every account predating this feature carries no field; it must behave today
// exactly as it did yesterday.
assert.deepEqual(prefsFromUser(undefined), DEFAULT_NOTIFICATION_PREFS);
assert.deepEqual(prefsFromUser({}), DEFAULT_NOTIFICATION_PREFS);
assert.deepEqual(prefsFromUser({ notificationPrefs: {} }), DEFAULT_NOTIFICATION_PREFS);
for (const group of ['messages', 'engagement', 'radius']) {
  assert.equal(pushAllowed(prefsFromUser(null), group), true, `${group} must default to allowed`);
}

// ── Only an explicit off is off ──────────────────────────────────────────────
// A malformed value falls back to permissive for THAT switch alone, so a bad
// write can never silence an account wholesale.
assert.equal(pushAllowed(normalisePrefs({ messages: false }), 'messages'), false);
assert.equal(pushAllowed(normalisePrefs({ engagement: 'off' }), 'engagement'), false);
assert.equal(pushAllowed(normalisePrefs({ radius: 'off' }), 'radius'), false);
assert.equal(pushAllowed(normalisePrefs({ messages: 'nonsense' }), 'messages'), true);
assert.equal(pushAllowed(normalisePrefs({ engagement: 'nonsense' }), 'engagement'), true);
assert.equal(pushAllowed(normalisePrefs({ engagement: 'off' }), 'messages'), true,
  'one switch off must not affect another');

// `highlights` is legal in the device enum but nothing defines what a highlight
// is, so the server sends rather than guessing which ones to drop.
assert.equal(pushAllowed(normalisePrefs({ engagement: 'highlights' }), 'engagement'), true);

// ── The write path refuses what it cannot store ──────────────────────────────
assert.deepEqual(validatedPatch({ messages: false }), { messages: false });
assert.deepEqual(validatedPatch({ engagement: 'highlights' }), { engagement: 'every' },
  'highlights is accepted from a client and stored as the behaviour it gets');
assert.deepEqual(validatedPatch({}), {}, 'an empty patch is a read, not an error');
assert.deepEqual(validatedPatch(undefined), {});
assert.throws(() => validatedPatch({ messages: 'yes' }), /true or false/);
assert.throws(() => validatedPatch({ engagement: 'sometimes' }), /every, highlights or off/);
assert.throws(() => validatedPatch({ radius: 'hourly' }), /daily or off/);
assert.throws(() => validatedPatch({ fcmTokens: {} }), /Unknown notification preference/,
  'the write path must never reach another field on the account');

// A partial patch is the point: a screen toggling one switch does not resend
// the rest, and must not clear them.
assert.deepEqual(validatedPatch({ radius: 'off' }), { radius: 'off' });

console.log('notification preference tests passed');
