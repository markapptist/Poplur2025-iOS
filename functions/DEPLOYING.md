# Deploying these functions

Read this before your first deploy. Three things here are counter-intuitive and each one has
cost real time.

## `lib/` is what runs — nothing compiles at deploy time

`firebase.json` declares no predeploy hook and `package.json` has no `gcp-build` script.
Whatever sits in `functions/lib/` is uploaded and executed verbatim.

Two consequences:

1. **Change `src/` and you must `npm run build`**, or your change simply does not ship. The
   deploy will succeed and do nothing.
2. **`npm run build` recompiles everything.** If anyone else has uncommitted work in `src/`,
   it gets compiled into *your* artifact even though you never opened their files.

So check the tree **after** building, not just before:

```sh
git status --porcelain -- functions/src   # before: is anyone mid-edit?
npm --prefix functions run build
git status --porcelain -- functions/lib   # after: did more than your file change?
git checkout -- functions/lib/<file>      # revert anything you did not intend
```

On 4 Sep 2026 a rebuild between those two checks pulled another session's half-finished
`index.ts` and `syntheticBrowserRunner.ts` into a production deploy. It was caught by diffing
the build output, not by the pre-deploy check.

## Every deploy is blocked by an unset secret

Any deploy — even `--only functions:somethingElse` — fails with:

```
Error: In non-interactive mode but have no value for the secret CLO_WORKER_TOKEN
```

`wardrobeGarments.ts` binds `defineSecret("CLO_WORKER_TOKEN")` and
`defineSecret("CLO_CALLBACK_SECRET")`, and neither exists in Secret Manager. Function
discovery loads the whole codebase regardless of `--only`, so this one function blocks
everything.

**The real fix is to set them** (one command, needs the actual values):

```sh
firebase functions:secrets:set CLO_WORKER_TOKEN
firebase functions:secrets:set CLO_CALLBACK_SECRET
```

Until then, `wardrobeGarmentApi` cannot be deployed at all, and it silently takes every other
function down with it. That is why `notifyOnDirectMessage`, `wardrobeGarmentApi`,
`liveNewsApi` and `refreshLiveNews` sat undeployed for over a week — one deploy aborted
partway and nothing surfaced it.

### Workaround, if you must deploy before the secrets exist

`wardrobeGarmentApi` is not in production, so withholding it changes nothing live. Comment out
**both** lines in `lib/index.js` — hiding only the export is not enough, because `defineSecret`
binds when the module *loads*:

```js
var wardrobeGarments_1 = require("./wardrobeGarments");
Object.defineProperty(exports, "wardrobeGarmentApi", { ... });
```

Always restore from a copy and verify with `shasum` in the same command, so a failed deploy
cannot leave the repo holding a broken build.

## Discovery times out at 10s

Raise it or the deploy fails before it starts:

```sh
FUNCTIONS_DISCOVERY_TIMEOUT=120 firebase deploy --only functions:name --project poplur2025
```

## Do not use `npm run deploy`

That script runs `firebase deploy --only functions,firestore:rules` — every function plus the
security rules, from whatever is in the working tree. Name the functions you mean instead.
