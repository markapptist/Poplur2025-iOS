/**
 * Meshy image-to-3D, behind Poplur's own authorization and credit ledger.
 *
 * The key never leaves this function: the app posts an image, this decides
 * whether the caller may generate at all, debits credits, calls Meshy, and
 * hands back a Poplur-hosted model. See functions/MESHY-ENDPOINT-SPEC.md.
 *
 * WHY onRequest AND NOT onCall: the caller is the clay web bundle, which has no
 * Firebase SDK and no identity of its own — the native shell owns auth. So the
 * shell must pass its Firebase ID token into the web layer, and the web sends
 * it as `Authorization: Bearer <idToken>`. That bridge hand-off does not exist
 * yet; until it does, this function will correctly reject every call as
 * unauthenticated. That is the right failure: the alternative is trusting a
 * client that cannot prove who it is.
 */
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { Request, Response } from "express";
import { FieldValue } from "firebase-admin/firestore";

const meshyApiKey = defineSecret("MESHY_API_KEY");

const MESHY_API = "https://api.meshy.ai/openapi/v1/image-to-3d";
/** Credits per generation. One knob, deliberately — pricing is a product call. */
const GENERATION_COST = 25;
/** Per-account ceiling. Generation is slow and paid; a loop is expensive. */
const MAX_JOBS_PER_DAY = 20;

type ModelKind = "landmark" | "business";

/**
 * Landmarks are shared world furniture — one generation is rendered for every
 * user — so only an admin may mint one. A business account may generate a model
 * of its own business, and nobody else may generate anything.
 *
 * The allowlist lives in Firestore (`poplurConfig/meshy.adminUids`) rather than
 * in code so it can change without a deploy, and it is readable only by
 * functions. It is NEVER derived from anything the client sends.
 */
async function authorize(uid: string, kind: ModelKind): Promise<void> {
  const db = admin.firestore();
  if (kind === "landmark") {
    const config = await db.collection("poplurConfig").doc("meshy").get();
    const admins: unknown = config.data()?.adminUids;
    const allowed = Array.isArray(admins) && admins.includes(uid);
    if (!allowed) throw httpError(403, "Only an admin may generate landmark models.");
    return;
  }
  const user = await db.collection("users").doc(uid).get();
  if (user.data()?.accountType !== "business") {
    throw httpError(403, "Business models require a business account.");
  }
}

class MeshyHttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}
function httpError(status: number, message: string): MeshyHttpError {
  return new MeshyHttpError(status, message);
}

/** Verify the shell's Firebase ID token. No token, no generation. */
async function requireUid(req: Request): Promise<string> {
  const header = req.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) throw httpError(401, "Sign in before generating a model.");
  try {
    const decoded = await admin.auth().verifyIdToken(match[1]);
    return decoded.uid;
  } catch {
    throw httpError(401, "That session is no longer valid. Sign in again.");
  }
}

/**
 * Debit before calling Meshy, keyed by job id so a retry cannot double-charge.
 * Returns the balance left, and throws if the account cannot afford it.
 */
async function debitCredits(uid: string, jobId: string): Promise<number> {
  const db = admin.firestore();
  const balanceRef = db.collection("creatorCreditBalances").doc(uid);
  const ledgerRef = db.collection("creatorCreditTransactions").doc(`meshy_${jobId}`);
  return db.runTransaction(async transaction => {
    const [ledger, balance] = await Promise.all([
      transaction.get(ledgerRef),
      transaction.get(balanceRef),
    ]);
    const available = Number(balance.data()?.availableCredits ?? 0);
    if (ledger.exists) return available; // already charged for this job
    if (available < GENERATION_COST) {
      throw httpError(402, `This costs ${GENERATION_COST} credits and you have ${available}.`);
    }
    transaction.set(balanceRef, {
      availableCredits: available - GENERATION_COST,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(ledgerRef, {
      uid, jobId, kind: "meshy_generation",
      credits: -GENERATION_COST,
      createdAt: FieldValue.serverTimestamp(),
    });
    return available - GENERATION_COST;
  });
}

/** A failed generation must not cost the user. Idempotent, like the debit. */
async function refundCredits(uid: string, jobId: string): Promise<void> {
  const db = admin.firestore();
  const balanceRef = db.collection("creatorCreditBalances").doc(uid);
  const refundRef = db.collection("creatorCreditTransactions").doc(`meshy_refund_${jobId}`);
  await db.runTransaction(async transaction => {
    const [refund, balance] = await Promise.all([
      transaction.get(refundRef),
      transaction.get(balanceRef),
    ]);
    if (refund.exists) return;
    transaction.set(balanceRef, {
      availableCredits: Number(balance.data()?.availableCredits ?? 0) + GENERATION_COST,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(refundRef, {
      uid, jobId, kind: "meshy_refund",
      credits: GENERATION_COST,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
}

async function enforceRateLimit(uid: string): Promise<void> {
  const since = admin.firestore.Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
  const recent = await admin.firestore().collection("meshyJobs")
    .where("uid", "==", uid).where("createdAt", ">", since).count().get();
  if (recent.data().count >= MAX_JOBS_PER_DAY) {
    throw httpError(429, "Daily generation limit reached. Try again tomorrow.");
  }
}

/** POST /  { image: <data URI>, style?, name?, kind: "landmark" | "business" } */
export const meshyGenerate = onRequest(
  { secrets: [meshyApiKey], cors: false, memory: "512MiB", timeoutSeconds: 120 },
  async (req: Request, res: Response) => {
    try {
      if (req.method !== "POST") throw httpError(405, "POST only.");
      const uid = await requireUid(req);
      const kind: ModelKind = req.body?.kind === "landmark" ? "landmark" : "business";
      await authorize(uid, kind);
      await enforceRateLimit(uid);

      const image = String(req.body?.image ?? "");
      if (!image.startsWith("data:image/")) throw httpError(400, "image must be a data URI.");

      const jobId = admin.firestore().collection("meshyJobs").doc().id;
      await debitCredits(uid, jobId);

      const meshy = await fetch(MESHY_API, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${meshyApiKey.value()}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          image_url: image,
          enable_pbr: true,
          should_remesh: true,
          // Named so a Meshy-side audit can be traced back to a Poplur job
          // without exposing the uid to the vendor.
          name: String(req.body?.name ?? `poplur_${kind}_${jobId.slice(0, 8)}`),
        }),
      });

      if (!meshy.ok) {
        await refundCredits(uid, jobId);
        logger.error("meshy_start_failed", { status: meshy.status, jobId });
        throw httpError(502, "The model service refused the job. You were not charged.");
      }

      const started = await meshy.json() as { result?: string };
      const taskId = started.result;
      if (!taskId) {
        await refundCredits(uid, jobId);
        throw httpError(502, "The model service did not return a task. You were not charged.");
      }

      await admin.firestore().collection("meshyJobs").doc(jobId).set({
        uid, kind, taskId, status: "PENDING",
        createdAt: FieldValue.serverTimestamp(),
      });

      res.json({ taskId: jobId });
    } catch (error) {
      respondWithError(res, error, "meshy_generate");
    }
  }
);

/** GET /{jobId} -> { status, progress, modelUrl? } */
export const meshyStatus = onRequest(
  { secrets: [meshyApiKey], cors: false, memory: "512MiB", timeoutSeconds: 120 },
  async (req: Request, res: Response) => {
    try {
      const uid = await requireUid(req);
      const jobId = req.path.split("/").filter(Boolean).pop() ?? "";
      const jobRef = admin.firestore().collection("meshyJobs").doc(jobId);
      const job = await jobRef.get();
      // Ownership, not just authentication: one account must never poll (or
      // collect the model from) another account's job.
      if (!job.exists || job.data()?.uid !== uid) throw httpError(404, "No such job.");

      const data = job.data()!;
      if (data.status === "SUCCEEDED" && data.modelUrl) {
        res.json({ status: "SUCCEEDED", progress: 100, modelUrl: data.modelUrl });
        return;
      }

      const poll = await fetch(`${MESHY_API}/${data.taskId}`, {
        headers: { Authorization: `Bearer ${meshyApiKey.value()}` },
      });
      if (!poll.ok) throw httpError(502, "Could not read the job status.");
      const task = await poll.json() as {
        status?: string; progress?: number; model_urls?: { glb?: string };
      };

      if (task.status === "FAILED") {
        await refundCredits(uid, jobId);
        await jobRef.set({ status: "FAILED" }, { merge: true });
        res.json({ status: "FAILED", progress: task.progress ?? 0 });
        return;
      }

      if (task.status !== "SUCCEEDED" || !task.model_urls?.glb) {
        res.json({ status: task.status ?? "PENDING", progress: task.progress ?? 0 });
        return;
      }

      // Take a copy: Meshy's URL expires, and handing it to the client leaks the
      // vendor into the app and breaks the model later.
      const glb = await fetch(task.model_urls.glb);
      if (!glb.ok) throw httpError(502, "The finished model could not be collected.");
      const bytes = Buffer.from(await glb.arrayBuffer());
      const path = data.kind === "landmark"
        ? `landmarks/pending/${jobId}.glb`   // pending: a human approves before it ships
        : `businessModels/${uid}/${jobId}.glb`;
      const file = admin.storage().bucket().file(path);
      await file.save(bytes, { contentType: "model/gltf-binary" });
      const [modelUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 365 * 24 * 60 * 60 * 1000,
      });
      await jobRef.set({ status: "SUCCEEDED", modelUrl, storagePath: path }, { merge: true });
      res.json({ status: "SUCCEEDED", progress: 100, modelUrl });
    } catch (error) {
      respondWithError(res, error, "meshy_status");
    }
  }
);

function respondWithError(res: Response, error: unknown, tag: string): void {
  if (error instanceof MeshyHttpError) {
    res.status(error.status).json({ error: error.message });
    return;
  }
  logger.error(`${tag}_unexpected`, {
    error: error instanceof Error ? error.message.slice(0, 240) : "unknown",
  });
  res.status(500).json({ error: "Model generation is unavailable right now." });
}
