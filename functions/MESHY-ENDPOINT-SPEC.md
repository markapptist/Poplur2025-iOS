# Meshy endpoint — spec for review

Status: **not built**. `poplur-clay-map/src/meshy.ts` is a complete client for a
server that does not exist yet. `VITE_POPLUR_MESHY_ENDPOINT` is unset, so
`isMeshyAvailable()` is false and every Meshy path in the app is dark. Loading
credits onto an account changes nothing until this ships.

## Why it must be server-side

Not for tidiness — the client **cannot** do this job:

1. **It holds the API key.** A Meshy key in the bundle is a key in every user's
   hands.
2. **The web layer has no identity at all.** The clay bundle has no uid, no user
   object; the native shell owns Firebase auth (`PostComposer.tsx:125` states the
   contract). So the app literally cannot know who is asking, and any
   client-side role flag would be both uninformed and trivially bypassed.
3. **Credits are money.** A client-side debit is a suggestion.

The app may hide UI by role for tidiness; the server is what actually decides.

## Authorization model

| Caller | May generate | Scope of result |
|---|---|---|
| **Admin** (explicit uid allowlist) | world **landmarks** | shared — ships to every user |
| **Business account** | one model for **their own business** | that business only, shown via the Avatar screen |
| Everyone else | nothing | — |

Landmarks are shared world furniture: generated once, rendered by everyone.
Business models are per-account, like avatars. These are different products and
should not share a code path beyond the proxy itself.

Admin identity belongs in a server-side allowlist (config or a Firestore doc
readable only by functions) — **never** a client-visible flag, and never
inferred from an email string in the bundle.

## Endpoints (contract already assumed by `meshy.ts`)

```
POST {endpoint}/image-to-3d      { image: <data URI>, style, name }  -> { taskId }
GET  {endpoint}/image-to-3d/{id}                                     -> { status, progress, modelUrl? }
```

Server responsibilities per call:

1. **Verify** the Firebase ID token (reject unauthenticated outright).
2. **Authorize**: admin → `kind: "landmark"` allowed; business → `kind:
   "business"` allowed and forced to that account; otherwise 403.
3. **Debit credits** before calling Meshy, and **refund on failure** — a Meshy
   error must not cost the user. Debit must be idempotent per `taskId` so a
   retried poll never double-charges.
4. **Proxy** to `POST https://api.meshy.ai/openapi/v1/image-to-3d` with the key
   from secret config, never from the request.
5. **Persist** the result: download the GLB and store it in Firebase Storage
   under a path the client can read. Do not hand out Meshy's URL — it expires,
   and it leaks the vendor into the client.
6. **Rate limit** per uid. Generation is slow and paid; a loop is expensive.

## Landmark specifics

- A generated landmark GLB must be **reviewed before it ships**. Approval is a
  deliberate step, not an automatic consequence of generation — an unrecognisable
  CN Tower is worse than the honest extruded block it replaces.
- Store approved landmark models under `public/landmarks/`, **never**
  `public/models/`: that directory is stripped from every phone bundle, so a
  landmark placed there works on desktop and silently vanishes on device.
- Keep them small. The same size discipline as tab models applies (see
  `scripts/verify-tab-model-quality.mjs`); a 30MB landmark is not shippable.
- The placement half already exists: `poplur-clay-map/src/ClayLandmarks.ts`
  positions a GLB at real coordinates, scales it to its true height in metres,
  applies the world's clay material, and shares the clay layer's scene, camera
  and renderer (no second WebGL context, no second clock).

## What you must supply before this can be built

1. A **Meshy API key** (and which plan — it governs rate limits and quality).
2. The **admin uid(s)**.
3. How a **business account** is marked in Firestore (field and collection), or
   a decision to create that flag.
4. A **deploy**. I can write the function; I should not hold the key or deploy it.

## Honest expectation

Image-to-3D will not reliably reproduce a specific real landmark. Generative 3D
is plausible-but-approximate, and famous silhouettes are exactly where
approximate reads as wrong — thin masts and lattice (CN Tower, Eiffel) are the
classic failure cases. Trial ONE landmark and judge it in the map at real camera
angles before funding a set. If it disappoints, purpose-made models
(Sketchfab/Turbosquid, or a modeller) are the better spend, and you own them.
