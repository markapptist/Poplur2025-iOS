# Poplur CLO/EveryWear worker contract

`wardrobeGarmentApi` is Poplur's public control plane. CLO/EveryWear remains a
private, licensed asset worker and is never called from a phone.

## Required deployment configuration

- Secret `CLO_WORKER_TOKEN`: bearer token accepted only by the private worker.
- Secret `CLO_CALLBACK_SECRET`: HMAC-SHA256 secret shared only with the worker.
- Parameter `CLO_WORKER_URL`: HTTPS origin hosting `POST /v1/garment-jobs`.
- Parameter `WARDROBE_CALLBACK_URL`: deployed `wardrobeGarmentApi` function URL.
- Firestore `poplurConfig/wardrobe.publisherUids`: publisher UID allowlist, or
  the equivalent `wardrobePublisher: true` Firebase custom claim.
- Private Storage avatars:
  - `wardrobe/private/avatars/poplur-female-v1.fbx`
  - `wardrobe/private/avatars/poplur-male-v1.fbx`

Source garment projects are uploaded separately to
`wardrobe/private/sources/`. The API only passes short-lived signed URLs.

## Worker request

The worker receives `POST /v1/garment-jobs` with a bearer token and JSON:

```json
{
  "jobId": "firestore-job-id",
  "styleId": "clo-arc-coat",
  "slot": "top",
  "gender": "female",
  "rig": "poplur-humanoid-65-v1",
  "source": { "downloadUrl": "short-lived signed URL" },
  "avatar": {
    "downloadUrl": "short-lived signed URL",
    "objectPath": "wardrobe/private/avatars/poplur-female-v1.fbx"
  },
  "output": {
    "uploadUrl": "short-lived signed PUT URL",
    "contentType": "model/gltf-binary",
    "maximumBytes": 12582912
  },
  "callback": {
    "url": "https://.../wardrobeGarmentApi/callbacks",
    "algorithm": "hmac-sha256"
  },
  "qa": {
    "exactBoneCount": 65,
    "maximumWeightsPerVertex": 4,
    "requiredMorphTargets": ["Muscle", "YouthfulAdult"],
    "requireEmbeddedResources": true
  }
}
```

The worker must import the canonical avatar, simulate/drape the garment,
transfer/prune weights to the exact Poplur skeleton, bake the required body
morphs, export one self-contained GLB, validate it, and PUT it with
`Content-Type: model/gltf-binary`.

## Signed callback

The worker POSTs the raw JSON body to `/callbacks` and sends
`X-Poplur-Signature: sha256=<hex HMAC of raw body>`. A successful callback is:

```json
{
  "jobId": "firestore-job-id",
  "status": "completed",
  "sha256": "64 lowercase hex characters",
  "qa": {
    "rig": "poplur-humanoid-65-v1",
    "boneCount": 65,
    "maximumWeightsPerVertex": 4,
    "morphTargets": ["Muscle", "YouthfulAdult"],
    "externalUriCount": 0
  }
}
```

The function independently checks the uploaded byte length and SHA-256. A
completed job becomes `needs_review`, not public. A publisher calls
`POST /publish` after visual pose/collision review. Both female and male
variants must be approved before `GET /catalog` returns the style. The publish
request must send `{ "jobId": "...", "reviewConfirmed": true }`.

## Phone behavior

The clay-map Wardrobe requests `GET /catalog` after its first UI paint. It
rejects wrong rigs, unsafe URLs, malformed hashes and oversized assets. When a
user selects a fitted style, Three.js stages and validates that one garment,
binds it to the already-live 65-bone skeleton, then atomically replaces only
the selected slot. It does not reload the body or create another WebGL context.
