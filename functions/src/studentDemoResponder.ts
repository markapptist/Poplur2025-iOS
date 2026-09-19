/**
 * Student demo responder — the synthetic cohort reacting to REAL posts.
 *
 * The daily simulation fills the map and engages itself; it never touches a
 * real tester's pop, and its engagement is muted on purpose. This is the other
 * half for the student test build: every post by a real account gets a plan
 * (studentDemoPolicy.ts) — first like within seconds, a comment, more likes, a
 * message, a steady tail over the hour — carried out by the fixed cohort and
 * the sim-daily actors through the production engagement transaction, from
 * anywhere on Earth (the radius rule is a discovery rule; a reaction needs no
 * proximity). Engagement ids carry the `demo-` prefix, which is what lets
 * notifyOnEngagement deliver these to a real phone while the hourly
 * simulation stays silent.
 *
 * Three functions:
 *   studentDemoOnPost   — posts/{postId} created by a real account → plan, and
 *                         the first beats inline so the student sees the
 *                         radius move before leaving the screen.
 *   studentDemoTick     — every minute: run every due step across plans.
 *   studentDemoOnMessage — a student writes to a fake tester → it answers.
 *
 * Off by default: testControl/studentDemo.enabled.
 */
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { applyPostEngagement } from "./postEngagement";
import { postOwnerUid } from "./accountRadius";
import { SYNTHETIC_BETA_PROFILES } from "./syntheticBetaCohort";
import { isSyntheticAccount } from "./syntheticIdentity";
import {
  buildDemoPlan, canonicalThreadId, demoEventId, demoMessageId, demoReply, demoEligiblePost, nextDue,
  parseStudentDemoConfig, DEMO_REPLIES_PER_HOUR, DEMO_REPLY_DELAY_MS, STUDENT_DEMO_CONFIG, STUDENT_DEMO_DM_LEDGER,
  STUDENT_DEMO_PLANS, STUDENT_DEMO_SOURCE, type DemoPlan, type DemoStep, type StudentDemoConfig,
} from "./studentDemoPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const REGION = "us-central1";
const DAILY_ACTORS = "testDailySimulationActors";
const DAILY_ACTOR_TAKE = 16;

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

async function loadConfig(): Promise<StudentDemoConfig> {
  return parseStudentDemoConfig((await db.doc(STUDENT_DEMO_CONFIG).get()).data());
}

/** Is this uid a person (a student, the owner, anyone real)? Synthetic
 *  accounts announce themselves by uid, flag, source or mailbox. */
async function isRealAccount(uid: string): Promise<boolean> {
  if (isSyntheticAccount(uid, null, null)) return false;
  const profile = (await db.collection("users").doc(uid).get()).data();
  let email: string | null = typeof profile?.email === "string" ? profile.email : null;
  if (!email) {
    try { email = (await admin.auth().getUser(uid)).email ?? null; } catch { /* unknown stays unknown */ }
  }
  return !isSyntheticAccount(uid, profile, email);
}

/** The cohort that reacts: the eight fixed runner personas plus the newest
 *  sim-daily testers, so faces vary from post to post. Only accounts that
 *  exist in Auth are used — never an impersonated uid. */
async function actorPool(): Promise<string[]> {
  const fixed = SYNTHETIC_BETA_PROFILES.map(p => p.id);
  const daily = await db.collection(DAILY_ACTORS).orderBy("joinedDay", "desc").limit(DAILY_ACTOR_TAKE).get();
  const ids = [...new Set([...fixed, ...daily.docs.map(d => d.id)])];
  const existing: string[] = [];
  for (const uid of ids) {
    try { await admin.auth().getUser(uid); existing.push(uid); } catch { /* skip a persona that was never provisioned */ }
  }
  return existing;
}

function actorHandle(uid: string, profile: Record<string, unknown> | undefined): string {
  const persona = SYNTHETIC_BETA_PROFILES.find(p => p.id === uid);
  if (persona) return persona.handle.replace(/^@/, "");
  if (typeof profile?.username === "string" && profile.username) return profile.username;
  return uid;
}

/** One reaction step through the production transaction. A refused post
 *  (blocked, deleted, private) ends the plan rather than being bypassed. */
async function runStep(plan: DemoPlan, step: DemoStep, config: StudentDemoConfig): Promise<"ok" | "stop"> {
  for (const kind of step.kinds) {
    try {
      await applyPostEngagement(step.actorUid, {
        postId: plan.postId, eventId: demoEventId(plan.postId, step.index, kind), kind,
        ...(kind === "comment" && step.comment ? { text: step.comment } : {}),
      });
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === "permission-denied" || code === "not-found" || code === "failed-precondition") {
        logger.info("[studentDemo] post no longer engageable, ending plan", { postId: plan.postId, code });
        return "stop";
      }
      throw error;
    }
  }
  if (step.dm && config.dmEnabled) await sendOpener(step.actorUid, plan.ownerUid, plan.postId, step.dm);
  return "ok";
}

/** A first message from a fake tester, at most once per pair per day, in the
 *  exact shape the phones write (participants sorted, unread counters, a
 *  `msg-` client id) so notifyOnDirectMessage pushes it and both inboxes
 *  render it. */
async function sendOpener(actorUid: string, ownerUid: string, postId: string, text: string): Promise<void> {
  const ledgerRef = db.collection(STUDENT_DEMO_DM_LEDGER).doc(`${actorUid}_${ownerUid}`);
  const now = Date.now();
  const fresh = await db.runTransaction(async tx => {
    const row = (await tx.get(ledgerRef)).data();
    if (typeof row?.lastAtMillis === "number" && now - row.lastAtMillis < 24 * 60 * 60_000) return false;
    tx.set(ledgerRef, { actorUid, ownerUid, lastAtMillis: now, lastPostId: postId, source: STUDENT_DEMO_SOURCE }, { merge: true });
    return true;
  });
  if (!fresh) return;
  await writeMessage(actorUid, ownerUid, demoMessageId(`${postId}:${actorUid}:opener`), text);
}

async function writeMessage(senderUid: string, recipientUid: string, messageId: string, text: string): Promise<boolean> {
  const threadId = canonicalThreadId(senderUid, recipientUid);
  const threadRef = db.collection("dmThreads").doc(threadId);
  const messageRef = threadRef.collection("messages").doc(messageId);
  const profile = (await db.collection("users").doc(senderUid).get()).data();
  const handle = actorHandle(senderUid, profile);
  return db.runTransaction(async tx => {
    if ((await tx.get(messageRef)).exists) return false;
    tx.set(threadRef, {
      participants: [senderUid, recipientUid].sort(),
      lastMessage: text,
      lastSenderId: senderUid,
      updatedAt: FieldValue.serverTimestamp(),
      unreadBy: { [senderUid]: 0, [recipientUid]: FieldValue.increment(1) },
      participantNames: { [senderUid]: handle },
      syntheticSource: STUDENT_DEMO_SOURCE,
    }, { merge: true });
    tx.set(messageRef, {
      senderId: senderUid, clientMessageId: messageId, text, kind: "text",
      synthetic: true, syntheticSource: STUDENT_DEMO_SOURCE,
      createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/** Run every due step of one plan; returns the number executed. Steps are
 *  marked done one at a time so a crash mid-plan replays only what is left,
 *  and the idempotent ids make even that replay free. */
async function drainPlan(planRef: FirebaseFirestore.DocumentReference, plan: DemoPlan, config: StudentDemoConfig, untilMillis: number): Promise<number> {
  let ran = 0;
  let stopped = false;
  for (const step of plan.steps) {
    if (step.done || step.dueAtMillis > untilMillis) continue;
    if (!stopped) {
      const wait = step.dueAtMillis - Date.now();
      if (wait > 0) await sleep(wait);
      const outcome = await runStep(plan, step, config);
      if (outcome === "stop") stopped = true; else ran++;
    }
    step.done = true;
  }
  if (stopped) for (const step of plan.steps) step.done = true;
  plan.nextDueAtMillis = nextDue(plan.steps);
  await planRef.set({ steps: plan.steps, nextDueAtMillis: plan.nextDueAtMillis, updatedAt: FieldValue.serverTimestamp(), ...(stopped ? { stoppedAt: FieldValue.serverTimestamp() } : {}) }, { merge: true });
  return ran;
}

export const studentDemoOnPost = onDocumentCreated(
  { document: "posts/{postId}", region: REGION, timeoutSeconds: 300, memory: "256MiB" },
  async event => {
    const post = event.data?.data();
    if (!post) return;
    const config = await loadConfig();
    if (!config.enabled) return;
    const { postId } = event.params;
    const ownerUid = postOwnerUid(post);
    if (!ownerUid || !demoEligiblePost(post)) return;
    if (!(await isRealAccount(ownerUid))) return;
    const planRef = db.collection(STUDENT_DEMO_PLANS).doc(postId);
    if ((await planRef.get()).exists) return;
    const pool = await actorPool();
    const plan = buildDemoPlan(postId, ownerUid, pool, config, Date.now());
    if (!plan) { logger.warn("[studentDemo] no synthetic actors available"); return; }
    await planRef.create({ ...plan, createdAt: FieldValue.serverTimestamp() });
    logger.info("[studentDemo] plan created", { postId, ownerUid, steps: plan.steps.length, actors: config.actorsPerPost });
    // The first beats happen here, inline, so the like lands in seconds
    // rather than at the next minute boundary.
    const ran = await drainPlan(planRef, plan, config, Date.now() + config.inlineWindowMs);
    logger.info("[studentDemo] inline beats done", { postId, ran });
  },
);

export const studentDemoTick = onSchedule(
  { schedule: "every 1 minutes", region: REGION, timeoutSeconds: 120, memory: "256MiB" },
  async () => {
    const config = await loadConfig();
    if (!config.enabled) return;
    const now = Date.now();
    const due = await db.collection(STUDENT_DEMO_PLANS).where("nextDueAtMillis", "<=", now + 30_000).limit(40).get();
    let ran = 0;
    for (const doc of due.docs) {
      const plan = doc.data() as DemoPlan;
      if (!plan?.steps?.length) continue;
      ran += await drainPlan(doc.ref, plan, config, now + 30_000);
    }
    if (due.size) logger.info("[studentDemo] tick", { plans: due.size, ran });
  },
);

/** A student wrote to a fake tester: it answers, a few seconds later, with a
 *  line that needs nothing back. Bounded per thread per hour so two
 *  auto-responders can never talk forever. */
export const studentDemoOnMessage = onDocumentCreated(
  { document: "dmThreads/{threadId}/messages/{messageId}", region: REGION, timeoutSeconds: 60, memory: "256MiB" },
  async event => {
    const message = event.data?.data();
    const senderId = typeof message?.senderId === "string" ? message.senderId : "";
    if (!message || !senderId || message.synthetic === true) return;
    const config = await loadConfig();
    if (!config.enabled || !config.replyEnabled) return;
    const { threadId, messageId } = event.params;
    const thread = (await db.collection("dmThreads").doc(threadId).get()).data();
    const participants = Array.isArray(thread?.participants) ? thread.participants.filter((v: unknown): v is string => typeof v === "string") : [];
    const other = participants.find((uid: string) => uid !== senderId);
    if (!other || !isSyntheticAccount(other, null, null)) return;
    if (!(await isRealAccount(senderId))) return;
    // Rate: count cohort replies in this thread over the last hour.
    const since = Date.now() - 60 * 60_000;
    // Newest messages only, filtered here: an equality plus an order on
    // another field would need a composite index for one bounded read.
    const recent = await db.collection("dmThreads").doc(threadId).collection("messages")
      .orderBy("createdAt", "desc").limit(DEMO_REPLIES_PER_HOUR * 3).get();
    const withinHour = recent.docs.filter(d => {
      const row = d.data();
      const at = row.createdAt;
      return row.senderId === other && at && typeof at.toMillis === "function" && at.toMillis() >= since;
    });
    if (withinHour.length >= DEMO_REPLIES_PER_HOUR) return;
    await sleep(DEMO_REPLY_DELAY_MS);
    const sent = await writeMessage(other, senderId, demoMessageId(`${threadId}:${messageId}:reply`), demoReply(`${threadId}:${messageId}`));
    if (sent) logger.info("[studentDemo] replied", { threadId, actor: other });
  },
);
