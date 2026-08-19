/**
 * generateRetroGame — the callable a player's "make me a game" hits.
 *
 * It designs and stores a specification; it does not build a ROM. Firebase
 * Functions cannot build a .gba (Butano needs devkitARM and a POSIX toolchain,
 * and this is a short-lived Node sandbox), so the build doc written here is the
 * work order the builder job picks up. A caller polls the build doc.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { CREATURE_SPEC_VERSION } from "./creatureCollectorSpec";
import {
  GenerationError,
  PROMPT_MAX_LENGTH,
  generateCreatureCollectorSpecification,
} from "./retroGameGenerationService";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const protectedRegion = "us-central1";

/** A design takes real thinking and real money; one at a time, and not many. */
const COOLDOWN_MS = 20_000;
const DAILY_LIMIT = 20;

/** Map a generation failure onto the callable error the app can act on. */
function toHttpsError(error: GenerationError): HttpsError {
  switch (error.code) {
    case "prompt_rejected":
      return new HttpsError("invalid-argument", error.message);
    case "spec_invalid":
      return new HttpsError("failed-precondition", error.message);
    case "model_unavailable":
      return new HttpsError("unavailable", error.message);
    case "designer_misconfigured":
      // Ours to fix, not the player's to retry.
      return new HttpsError("internal", "The game designer is not set up correctly.");
  }
}

export const generateRetroGame = onCall(
  {
    region: protectedRegion,
    enforceAppCheck: true,
    secrets: [anthropicApiKey],
    // Two streamed designs at up to 180s each, plus Firestore.
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to make a game.");

    const prompt = typeof request.data?.prompt === "string" ? request.data.prompt.trim() : "";
    if (!prompt) {
      throw new HttpsError("invalid-argument", "Describe the game you want.");
    }
    if (prompt.length > PROMPT_MAX_LENGTH) {
      throw new HttpsError("invalid-argument", `Keep the idea under ${PROMPT_MAX_LENGTH} characters.`);
    }

    // Resolved here, not at module scope: index.ts re-exports this module before
    // it calls initializeApp(), and re-exports are hoisted.
    const db = admin.firestore();

    // Cooldown and daily cap in one transaction, so two concurrent calls cannot
    // both read "under the limit" and both proceed.
    const rateRef = db.collection("retroGameRate").doc(uid);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(rateRef);
      const data = snapshot.data();
      const lastAt = data?.lastAt as Timestamp | undefined;
      const now = Date.now();

      if (lastAt && now - lastAt.toMillis() < COOLDOWN_MS) {
        throw new HttpsError("resource-exhausted", "Let this game finish designing before starting another.");
      }

      const today = new Date(now).toISOString().slice(0, 10);
      const count = data?.day === today ? ((data?.count as number) ?? 0) : 0;
      if (count >= DAILY_LIMIT) {
        throw new HttpsError("resource-exhausted", "That's every game for today. Try again tomorrow.");
      }

      transaction.set(rateRef, { lastAt: FieldValue.serverTimestamp(), day: today, count: count + 1 }, { merge: true });
    });

    const apiKey = anthropicApiKey.value() || process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new HttpsError("internal", "The game designer is not configured.");
    }

    let result;
    try {
      result = await generateCreatureCollectorSpecification(prompt, uid, apiKey);
    } catch (error) {
      if (error instanceof GenerationError) {
        logger.warn("retro game generation failed", {
          uid, code: error.code, detail: error.detail, violations: error.violations,
        });
        throw toHttpsError(error);
      }
      throw error;
    }

    // The spec and the build are separate docs on purpose: the spec is the
    // reviewable artefact and never changes, while the build doc churns through
    // statuses and can be retried against the same spec.
    const buildRef = db.collection("retroGameBuilds").doc();
    await buildRef.set({
      uid,
      prompt,
      spec: result.spec,
      template: "creature_collector",
      specVersion: CREATURE_SPEC_VERSION,
      status: "queued",
      createdAt: FieldValue.serverTimestamp(),
      attempts: result.attempts,
      usage: result.usage,
    });

    logger.info("retro game designed", {
      uid,
      buildId: buildRef.id,
      creatures: result.spec.creatures.length,
      attempts: result.attempts,
      outputTokens: result.usage.outputTokens,
    });

    return { buildId: buildRef.id, spec: result.spec, status: "queued" };
  },
);
