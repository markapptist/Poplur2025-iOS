/**
 * Codebase "digest" — scheduled engagement digests, kept apart from the main
 * `functions/` codebase on purpose:
 *
 *  - the main codebase loads ~195 MiB of modules (googleapis, genkit, AI SDKs)
 *    before it can listen, and three nearbyPopsDigest deploys from it failed
 *    Cloud Run's 240 s startup probe on 11 Sep 2026 without a single log line;
 *  - it binds unset secrets (wardrobeGarments) that block every deploy.
 *
 * This codebase depends only on firebase-admin and firebase-functions, so a
 * cold start is about a second and `firebase deploy --only functions:digest`
 * needs no workaround.
 */
export { nearbyPopsDigest } from "./nearbyPopsDigest";
