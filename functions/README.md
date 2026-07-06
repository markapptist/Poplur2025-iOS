# Poplur Premium AI Backend

This Firebase Functions package contains the premium-only Poplur AI callable and authenticated HTTP API used by both iOS and Android.

## HTTP API

Deploy exposes `poplurAiApi` in `us-central1`.

All requests must include:

```http
Authorization: Bearer <firebase-id-token>
Content-Type: application/json
```

Initial routes:

```text
GET  /credits/balance
GET  /ai/jobs
GET  /ai/jobs/:id
POST /ai/generate/image
POST /ai/generate/video
POST /ai/generate/edit
POST /ai/generate/vfx
POST /ai/generate/3d
POST /ai/generate/voice
POST /ai/generate/music
POST /ai/generate/game
POST /ai/jobs/:id/cancel
POST /ai/jobs/:id/publish-to-map
POST /posts/:id/radius-boost
POST /businesses/:businessId/ai-campaigns
```

## Deploy

```bash
cd functions
npm install
npm run build
firebase deploy --only functions,firestore:rules
```

## Runtime Reminder

Cloud Functions are currently pinned to Node 20 in `package.json`. Upgrade the Functions runtime before Google's Node 20 decommission date: October 30, 2026.

## AI Provider Secret

Set the Gemini key only in Firebase Functions. Do not add AI provider keys to either mobile app.

```bash
firebase functions:secrets:set GOOGLE_AI_API_KEY
firebase deploy --only functions:premiumAiAssist,poplurAiApi
```

The callable maps `GOOGLE_AI_API_KEY` into the environment variables expected by the Google GenAI tooling. The HTTP API uses `GOOGLE_AI_API_KEY` directly on the backend. Override models with `POPLUR_IMAGE_MODEL`, `POPLUR_VIDEO_MODEL`, or `POPLUR_TEXT_MODEL` if needed.

## Emulator Testing

```bash
cd functions
npm install
npm run serve
```

When running in the Functions emulator without `GOOGLE_AI_API_KEY`, the Genkit flow returns mock structured JSON so the premium gate and mobile UI can be tested locally.

## Credit Documents

Create credit balances server-side or from a trusted admin script:

```json
{
  "availableCredits": 100,
  "reservedCredits": 0,
  "lifetimeEarned": 100,
  "lifetimeSpent": 0,
  "planTier": "premium"
}
```

For test users, run the included Admin SDK seed script with Firebase application default credentials or a service account:

```bash
cd functions
npm run seed:creator-credits -- <test-user-uid> <another-test-user-uid>
```

You can also use environment variables:

```bash
TEST_USER_UIDS=uid1,uid2 CREATOR_TEST_CREDITS=500 CREATOR_TEST_PLAN_TIER=creator_test npm run seed:creator-credits
```

Client writes to balances, transactions, AI jobs, generated assets, radius boosts, and campaigns are blocked in `firestore.rules`. The Admin SDK in Functions owns those writes.

## Mark A Test User Premium

Create or update the signed-in user's Firestore document:

```json
{
  "isPremium": true,
  "premiumTier": "premium",
  "aiMonthlyLimit": 100,
  "aiUsedThisMonth": 0,
  "aiUsageMonth": "2026-07"
}
```

Business users can use `"premiumTier": "business"` and `aiMonthlyLimit: 500`.

## Security Notes

`firestore.rules` blocks clients from changing `isPremium`, `premiumTier`, `aiMonthlyLimit`, `aiUsedThisMonth`, and `aiUsageMonth`. Only Admin SDK code in trusted backend functions should update those fields.
