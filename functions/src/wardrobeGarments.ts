/**
 * Poplur's reviewed CLO/EveryWear garment pipeline.
 *
 * CLO itself runs in a separately licensed worker. This public function never
 * exposes that worker token, never sends garment CAD through the phone, and
 * never publishes an output merely because a solver finished. A publisher
 * starts one gender-specific fit job; the worker uploads to a signed private
 * path; a signed callback records automated rig QA; and a publisher explicitly
 * approves both variants before the item can enter the phone catalog.
 */
import * as admin from "firebase-admin";
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { Request, Response } from "express";

const cloWorkerToken = defineSecret("CLO_WORKER_TOKEN");
const cloCallbackSecret = defineSecret("CLO_CALLBACK_SECRET");
const cloWorkerUrl = defineString("CLO_WORKER_URL", { default: "" });
const wardrobeCallbackUrl = defineString("WARDROBE_CALLBACK_URL", { default: "" });

const REGION = "us-central1";
const RIG_ID = "poplur-humanoid-65-v1";
const MAX_SOURCE_BYTES = 80 * 1024 * 1024;
const MAX_GLB_BYTES = 12 * 1024 * 1024;
const SIGNED_TRANSFER_MS = 30 * 60 * 1000;
const SIGNED_CATALOG_MS = 6 * 60 * 60 * 1000;
const SOURCE_ROOT = "wardrobe/private/sources/";
const RESULT_ROOT = "wardrobe/private/results/";
const APPROVED_ROOT = "wardrobe/catalog/";
const AVATAR_PATHS = {
  female: "wardrobe/private/avatars/poplur-female-v1.fbx",
  male: "wardrobe/private/avatars/poplur-male-v1.fbx",
} as const;

type Gender = keyof typeof AVATAR_PATHS;
type GarmentSlot = "top" | "bottom";

type JobRecord = {
  uid: string;
  styleId: string;
  label: string;
  glyph: string;
  slot: GarmentSlot;
  gender: Gender;
  tintMaterial: string;
  sourceObjectPath: string;
  resultObjectPath: string;
  status: string;
  sha256?: string;
  bytes?: number;
};

class WardrobeHttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

function httpError(status: number, message: string): WardrobeHttpError {
  return new WardrobeHttpError(status, message);
}

function bodyRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw httpError(400, "Send a JSON object.");
  return value as Record<string, unknown>;
}

function shortText(value: unknown, name: string, maximum: number): string {
  if (typeof value !== "string") throw httpError(400, `${name} is required.`);
  const text = value.trim();
  if (!text || text.length > maximum) throw httpError(400, `${name} is invalid.`);
  return text;
}

function safeId(value: unknown): string {
  const id = shortText(value, "styleId", 64);
  if (!/^clo-[a-z0-9](?:[a-z0-9-]{0,62})$/.test(id)) {
    throw httpError(400, "styleId must begin with clo- and contain lowercase letters, numbers, or hyphens.");
  }
  return id;
}

function parseCreateJob(value: unknown) {
  const input = bodyRecord(value);
  const styleId = safeId(input.styleId);
  const label = shortText(input.label, "label", 80);
  const glyph = shortText(input.glyph, "glyph", 4);
  const tintMaterial = shortText(input.tintMaterial, "tintMaterial", 80);
  if (!/^[A-Za-z][A-Za-z0-9_.-]{0,79}$/.test(tintMaterial)) throw httpError(400, "tintMaterial is invalid.");
  if (input.slot !== "top" && input.slot !== "bottom") throw httpError(400, "slot must be top or bottom.");
  if (input.gender !== "female" && input.gender !== "male") throw httpError(400, "gender must be female or male.");
  const slot: GarmentSlot = input.slot;
  const gender: Gender = input.gender;
  const sourceObjectPath = shortText(input.sourceObjectPath, "sourceObjectPath", 300);
  if (!sourceObjectPath.startsWith(SOURCE_ROOT) || sourceObjectPath.includes("..")) {
    throw httpError(400, "The garment source must be in Poplur's private wardrobe source folder.");
  }
  return { styleId, label, glyph, tintMaterial, sourceObjectPath, slot, gender };
}

async function requirePublisher(req: Request): Promise<string> {
  const header = req.get("Authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) throw httpError(401, "Sign in with a Wardrobe publisher account.");
  let decoded: admin.auth.DecodedIdToken;
  try {
    decoded = await admin.auth().verifyIdToken(match[1]);
  } catch {
    throw httpError(401, "That publisher session is no longer valid.");
  }
  if (decoded.wardrobePublisher === true) return decoded.uid;
  const config = await admin.firestore().collection("poplurConfig").doc("wardrobe").get();
  const publishers: unknown = config.data()?.publisherUids;
  if (!Array.isArray(publishers) || !publishers.includes(decoded.uid)) {
    throw httpError(403, "This account cannot publish Wardrobe garments.");
  }
  return decoded.uid;
}

function route(req: Request): string[] {
  return req.path.split("/").filter(Boolean);
}

function configuredUrl(value: string, name: string): string {
  const candidate = value.trim();
  if (!candidate) throw httpError(503, `${name} is not configured.`);
  try {
    const parsed = new URL(candidate);
    if (parsed.protocol !== "https:") throw new Error("https required");
    return parsed.href.replace(/\/$/, "");
  } catch {
    throw httpError(503, `${name} must be an HTTPS URL.`);
  }
}

async function createJob(req: Request, res: Response): Promise<void> {
  const uid = await requirePublisher(req);
  const input = parseCreateJob(req.body);
  const worker = configuredUrl(cloWorkerUrl.value(), "CLO_WORKER_URL");
  const callback = configuredUrl(wardrobeCallbackUrl.value(), "WARDROBE_CALLBACK_URL");
  const bucket = admin.storage().bucket();
  const [sourceExists, avatarExists] = await Promise.all([
    bucket.file(input.sourceObjectPath).exists(),
    bucket.file(AVATAR_PATHS[input.gender]).exists(),
  ]);
  if (!sourceExists[0]) throw httpError(404, "The private garment source was not found.");
  if (!avatarExists[0]) throw httpError(503, `The canonical ${input.gender} CLO avatar is not installed.`);
  const [sourceMetadata] = await bucket.file(input.sourceObjectPath).getMetadata();
  if (Number(sourceMetadata.size ?? 0) <= 0 || Number(sourceMetadata.size) > MAX_SOURCE_BYTES) {
    throw httpError(400, "The garment source exceeds Poplur's source asset budget.");
  }

  const jobRef = admin.firestore().collection("wardrobeGarmentJobs").doc();
  const resultObjectPath = `${RESULT_ROOT}${input.styleId}/${input.gender}/${jobRef.id}.glb`;
  const expires = Date.now() + SIGNED_TRANSFER_MS;
  const [[sourceUrl], [avatarUrl], [uploadUrl]] = await Promise.all([
    bucket.file(input.sourceObjectPath).getSignedUrl({ action: "read", expires }),
    bucket.file(AVATAR_PATHS[input.gender]).getSignedUrl({ action: "read", expires }),
    bucket.file(resultObjectPath).getSignedUrl({
      version: "v4",
      action: "write",
      expires,
      contentType: "model/gltf-binary",
    }),
  ]);
  const createdAt = FieldValue.serverTimestamp();
  await jobRef.set({
    uid,
    ...input,
    resultObjectPath,
    rig: RIG_ID,
    status: "dispatching",
    createdAt,
    updatedAt: createdAt,
  });

  let response: globalThis.Response;
  try {
    response = await fetch(`${worker}/v1/garment-jobs`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${cloWorkerToken.value()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        jobId: jobRef.id,
        styleId: input.styleId,
        slot: input.slot,
        gender: input.gender,
        rig: RIG_ID,
        source: { downloadUrl: sourceUrl },
        avatar: { downloadUrl: avatarUrl, objectPath: AVATAR_PATHS[input.gender] },
        output: { uploadUrl, contentType: "model/gltf-binary", maximumBytes: MAX_GLB_BYTES },
        callback: { url: `${callback}/callbacks`, algorithm: "hmac-sha256" },
        qa: {
          exactBoneCount: 65,
          maximumWeightsPerVertex: 4,
          requiredMorphTargets: ["Muscle", "YouthfulAdult"],
          requireEmbeddedResources: true,
        },
      }),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    await jobRef.set({ status: "dispatch_failed", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    logger.error("wardrobe_clo_dispatch_failed", { jobId: jobRef.id, message: error instanceof Error ? error.message : "unknown" });
    throw httpError(502, "The CLO worker could not accept this garment job.");
  }
  if (!response.ok) {
    await jobRef.set({ status: "dispatch_failed", workerStatus: response.status, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw httpError(502, "The CLO worker refused this garment job.");
  }
  const started = await response.json().catch(() => ({})) as { providerJobId?: unknown };
  await jobRef.set({
    status: "processing",
    providerJobId: typeof started.providerJobId === "string" ? started.providerJobId.slice(0, 200) : null,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  res.status(202).json({ jobId: jobRef.id, status: "processing" });
}

function callbackIsAuthentic(req: Request): boolean {
  const supplied = (req.get("X-Poplur-Signature") ?? "").replace(/^sha256=/i, "").trim();
  if (!/^[a-f0-9]{64}$/i.test(supplied)) return false;
  const raw = (req as Request & { rawBody?: Buffer }).rawBody;
  if (!raw) return false;
  const expected = createHmac("sha256", cloCallbackSecret.value()).update(raw).digest();
  const actual = Buffer.from(supplied, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function receiveCallback(req: Request, res: Response): Promise<void> {
  if (!callbackIsAuthentic(req)) throw httpError(401, "The CLO callback signature is invalid.");
  const input = bodyRecord(req.body);
  const jobId = shortText(input.jobId, "jobId", 120);
  const jobRef = admin.firestore().collection("wardrobeGarmentJobs").doc(jobId);
  const snapshot = await jobRef.get();
  if (!snapshot.exists) throw httpError(404, "No such garment job.");
  if (input.status === "failed") {
    await jobRef.set({
      status: "failed",
      failureCode: typeof input.failureCode === "string" ? input.failureCode.slice(0, 80) : "worker_failed",
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    res.json({ accepted: true });
    return;
  }
  if (input.status !== "completed") throw httpError(400, "Unsupported callback status.");
  const qa = bodyRecord(input.qa);
  const morphTargets = Array.isArray(qa.morphTargets) ? qa.morphTargets : [];
  const maximumWeights = Number(qa.maximumWeightsPerVertex);
  if (
    qa.rig !== RIG_ID ||
    qa.boneCount !== 65 ||
    !Number.isInteger(maximumWeights) ||
    maximumWeights < 1 ||
    maximumWeights > 4 ||
    qa.externalUriCount !== 0 ||
    !morphTargets.includes("Muscle") ||
    !morphTargets.includes("YouthfulAdult")
  ) {
    await jobRef.set({ status: "qa_failed", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw httpError(422, "The garment failed Poplur rig validation.");
  }
  const job = snapshot.data() as JobRecord;
  const file = admin.storage().bucket().file(job.resultObjectPath);
  const [exists] = await file.exists();
  if (!exists) throw httpError(422, "The worker did not upload the fitted garment.");
  const [metadata] = await file.getMetadata();
  const bytes = Number(metadata.size ?? 0);
  if (!Number.isSafeInteger(bytes) || bytes <= 0 || bytes > MAX_GLB_BYTES) {
    await jobRef.set({ status: "qa_failed", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw httpError(422, "The fitted garment exceeds Poplur's asset budget.");
  }
  const [contents] = await file.download();
  const sha256 = createHash("sha256").update(contents).digest("hex");
  if (typeof input.sha256 === "string" && input.sha256.toLowerCase() !== sha256) {
    await jobRef.set({ status: "qa_failed", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw httpError(422, "The fitted garment checksum does not match the worker report.");
  }
  await jobRef.set({
    status: "needs_review",
    sha256,
    bytes,
    qa,
    completedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  res.json({ accepted: true, status: "needs_review" });
}

async function publishVariant(req: Request, res: Response): Promise<void> {
  const uid = await requirePublisher(req);
  const input = bodyRecord(req.body);
  if (input.reviewConfirmed !== true) throw httpError(400, "Confirm visual fit review before publishing.");
  const jobId = shortText(input.jobId, "jobId", 120);
  const jobRef = admin.firestore().collection("wardrobeGarmentJobs").doc(jobId);
  const snapshot = await jobRef.get();
  if (!snapshot.exists) throw httpError(404, "No such garment job.");
  const job = snapshot.data() as JobRecord;
  if (job.status !== "needs_review" || !job.sha256 || !job.bytes) {
    throw httpError(409, "This garment has not passed worker QA and human review.");
  }
  const bucket = admin.storage().bucket();
  const approvedPath = `${APPROVED_ROOT}${job.styleId}/${job.gender}/${job.sha256}.glb`;
  const source = bucket.file(job.resultObjectPath);
  const approved = bucket.file(approvedPath);
  await source.copy(approved);
  await approved.setMetadata({
    contentType: "model/gltf-binary",
    cacheControl: "public,max-age=31536000,immutable",
    metadata: { rig: RIG_ID, sha256: job.sha256, reviewedBy: uid },
  });

  const garmentRef = admin.firestore().collection("wardrobeGarments").doc(job.styleId);
  await admin.firestore().runTransaction(async transaction => {
    const garment = await transaction.get(garmentRef);
    const previous = garment.data() ?? {};
    const previousVariants = previous.variants && typeof previous.variants === "object" ? previous.variants : {};
    const variants = {
      ...previousVariants,
      [job.gender]: { storagePath: approvedPath, sha256: job.sha256, bytes: job.bytes },
    } as Record<string, unknown>;
    const published = Boolean(variants.female && variants.male);
    transaction.set(garmentRef, {
      styleId: job.styleId,
      label: job.label,
      glyph: job.glyph,
      slot: job.slot,
      tintMaterial: job.tintMaterial,
      rig: RIG_ID,
      variants,
      status: published ? "published" : "awaiting_other_variant",
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.set(jobRef, {
      status: "approved",
      approvedPath,
      approvedBy: uid,
      approvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  res.json({ approved: true, styleId: job.styleId, gender: job.gender });
}

async function jobStatus(req: Request, res: Response, jobId: string): Promise<void> {
  await requirePublisher(req);
  const snapshot = await admin.firestore().collection("wardrobeGarmentJobs").doc(jobId).get();
  if (!snapshot.exists) throw httpError(404, "No such garment job.");
  const data = snapshot.data() ?? {};
  res.json({
    jobId,
    status: data.status,
    styleId: data.styleId,
    gender: data.gender,
    failureCode: data.failureCode ?? null,
  });
}

async function catalog(res: Response): Promise<void> {
  const snapshot = await admin.firestore().collection("wardrobeGarments")
    .where("status", "==", "published")
    .limit(100)
    .get();
  const bucket = admin.storage().bucket();
  const expires = Date.now() + SIGNED_CATALOG_MS;
  const items = await Promise.all(snapshot.docs.map(async document => {
    const data = document.data();
    const variants = data.variants as Record<Gender, { storagePath: string; sha256: string; bytes: number }>;
    if (!variants?.female?.storagePath || !variants?.male?.storagePath) return null;
    const [[femaleUrl], [maleUrl]] = await Promise.all([
      bucket.file(variants.female.storagePath).getSignedUrl({ action: "read", expires }),
      bucket.file(variants.male.storagePath).getSignedUrl({ action: "read", expires }),
    ]);
    return {
      id: document.id,
      label: data.label,
      glyph: data.glyph,
      slot: data.slot,
      tintMaterial: data.tintMaterial,
      rig: RIG_ID,
      version: `${variants.female.sha256.slice(0, 12)}-${variants.male.sha256.slice(0, 12)}`,
      female: { url: femaleUrl, sha256: variants.female.sha256, bytes: variants.female.bytes },
      male: { url: maleUrl, sha256: variants.male.sha256, bytes: variants.male.bytes },
    };
  }));
  res.set("Cache-Control", "public, max-age=60, stale-while-revalidate=300");
  res.json({
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    items: items.filter(Boolean).sort((a, b) => String(a?.id).localeCompare(String(b?.id))),
  });
}

function respond(res: Response, error: unknown): void {
  if (error instanceof WardrobeHttpError) {
    res.status(error.status).json({ error: error.message });
    return;
  }
  logger.error("wardrobe_garment_api_unexpected", {
    message: error instanceof Error ? error.message : "unknown",
  });
  res.status(500).json({ error: "The Wardrobe service could not complete this request." });
}

export const wardrobeGarmentApi = onRequest(
  {
    region: REGION,
    cors: true,
    secrets: [cloWorkerToken, cloCallbackSecret],
    memory: "1GiB",
    timeoutSeconds: 120,
  },
  async (req: Request, res: Response) => {
    try {
      const parts = route(req);
      if (req.method === "GET" && parts.length === 1 && parts[0] === "catalog") return await catalog(res);
      if (req.method === "POST" && parts.length === 1 && parts[0] === "jobs") return await createJob(req, res);
      if (req.method === "GET" && parts.length === 2 && parts[0] === "jobs") return await jobStatus(req, res, parts[1]);
      if (req.method === "POST" && parts.length === 1 && parts[0] === "callbacks") return await receiveCallback(req, res);
      if (req.method === "POST" && parts.length === 1 && parts[0] === "publish") return await publishVariant(req, res);
      throw httpError(404, "No such Wardrobe API route.");
    } catch (error) {
      respond(res, error);
    }
  },
);
