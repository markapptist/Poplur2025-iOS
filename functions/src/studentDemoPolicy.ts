/**
 * Student demo engagement policy — pure, no Firebase.
 *
 * The test build is for students who must understand Poplur the moment they
 * open it: when one of them posts, the synthetic cohort has to react right
 * away, wherever the pop is, and keep reacting at a steady rate — likes,
 * comments, a message — so radius grows, notifications land and the map
 * plays its growth moment. This module decides WHO reacts, WHEN and with WHAT
 * words; studentDemoResponder.ts carries it out through the same production
 * engagement transaction every real tap uses.
 *
 * Everything is deterministic from the post id, so a retried trigger, a
 * second instance or a replayed tick lands on the same plan and the same
 * idempotent engagement ids.
 */

export const STUDENT_DEMO_CONFIG = "testControl/studentDemo";
export const STUDENT_DEMO_PLANS = "testDemoEngagementPlans";
export const STUDENT_DEMO_DM_LEDGER = "testDemoDMLedger";
export const STUDENT_DEMO_EVENT_PREFIX = "demo-";
export const STUDENT_DEMO_SOURCE = "student-demo-responder";

export type DemoKind = "view" | "like" | "comment";

export interface DemoStep {
  /** Position in the plan; also the idempotency suffix. */
  index: number;
  /** Absolute time the step becomes due. */
  dueAtMillis: number;
  actorUid: string;
  kinds: DemoKind[];
  comment?: string;
  /** A first message from this actor to the poster; once per pair per day. */
  dm?: string;
  done: boolean;
}

export interface DemoPlan {
  postId: string;
  ownerUid: string;
  createdAtMillis: number;
  steps: DemoStep[];
  /** Earliest undone step, for the tick's single-field query. */
  nextDueAtMillis: number | null;
  source: typeof STUDENT_DEMO_SOURCE;
}

export interface StudentDemoConfig {
  enabled: boolean;
  /** How long after the post the first reaction lands (default 20 s). */
  firstBeatMs: number;
  /** Cohort members that take part in one post's plan (default 6). */
  actorsPerPost: number;
  /** Whether a fake tester also opens a conversation (default true). */
  dmEnabled: boolean;
  /** Whether the cohort answers a student's message (default true). */
  replyEnabled: boolean;
  /** Steps executed inline by the create trigger before handing to the tick. */
  inlineWindowMs: number;
}

const DEFAULTS: StudentDemoConfig = {
  enabled: false,
  firstBeatMs: 20_000,
  actorsPerPost: 6,
  dmEnabled: true,
  replyEnabled: true,
  inlineWindowMs: 95_000,
};

function num(value: unknown, fallback: number, min: number, max: number): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

export function parseStudentDemoConfig(raw: unknown): StudentDemoConfig {
  const row = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return {
    enabled: row.enabled === true,
    firstBeatMs: num(row.firstBeatMs, DEFAULTS.firstBeatMs, 5_000, 120_000),
    actorsPerPost: Math.round(num(row.actorsPerPost, DEFAULTS.actorsPerPost, 2, 12)),
    dmEnabled: row.dmEnabled !== false,
    replyEnabled: row.replyEnabled !== false,
    inlineWindowMs: num(row.inlineWindowMs, DEFAULTS.inlineWindowMs, 0, 400_000),
  };
}

/** FNV-1a: the same small hash the daily simulation uses, kept local so this
 *  module stays dependency-free. */
export function demoHash(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** Deterministic pick without replacement: a stable shuffle of `pool` keyed
 *  by `seed`, first `count` entries. */
export function pickActors(pool: readonly string[], seed: string, count: number): string[] {
  const scored = pool.map((uid, i) => ({ uid, score: demoHash(`${seed}:${uid}:${i}`) }));
  scored.sort((a, b) => a.score - b.score || a.uid.localeCompare(b.uid));
  return scored.slice(0, Math.max(0, count)).map(s => s.uid);
}

/** Short, warm, and generic enough for any pop. None of them claims to know
 *  what is in the picture; the simulation never pretends to be a person, and
 *  the handle on the row already says it is a tester. */
export const DEMO_COMMENTS: readonly string[] = [
  "love this one",
  "ok this is a vibe",
  "just popped up on my map, nice",
  "this is going in my favourites",
  "saw this from across town, the radius is real",
  "more of this please",
  "the light in this is so good",
  "yep, liked and shared",
  "you're taking over the map today",
  "this made my feed better",
  "big pop energy",
  "new favourite creator, no notes",
  "wait where is this?",
  "came for the pin, stayed for the post",
  "this deserves way more reach",
  "watching your radius climb from here",
  "clean. very clean.",
  "the map needed this",
  "okay you win the neighbourhood",
  "post more like this and you own the block",
  "this is what the feed is for",
  "found you through the radius, staying",
  "instant like",
  "your pin just got bigger on my screen",
];

/** Openers a fake tester sends after the first likes have landed. */
export const DEMO_DM_OPENERS: readonly string[] = [
  "hey, your pop just showed up on my map. is that near you?",
  "saw your post in my feed, that spot looks great. what's the story?",
  "your pin is growing on my screen right now, nice work",
  "just liked your pop. are you posting more from around there?",
  "hi! new here too. your post is the first one that reached me",
];

/** Answers to whatever a student writes back. Never a question that needs
 *  a real answer, never a claim about the world. */
export const DEMO_DM_REPLIES: readonly string[] = [
  "ha, nice. keep posting, your radius is climbing",
  "love that. I'll keep an eye on your pin",
  "for sure. every post grows the circle a bit more",
  "same here. this app makes the map feel alive",
  "okay that's cool. post something from there next",
  "yes! that's the whole idea, reach grows with each pop",
  "good to know. I'm around, message any time",
];

export function demoComment(seed: string): string {
  return DEMO_COMMENTS[demoHash(`c:${seed}`) % DEMO_COMMENTS.length];
}
export function demoOpener(seed: string): string {
  return DEMO_DM_OPENERS[demoHash(`o:${seed}`) % DEMO_DM_OPENERS.length];
}
export function demoReply(seed: string): string {
  return DEMO_DM_REPLIES[demoHash(`r:${seed}`) % DEMO_DM_REPLIES.length];
}

/** The beats after a post, in seconds: quick first reactions so the student
 *  sees the radius move before they leave the screen, then a steady tail over
 *  the hour so the app keeps feeling alive. Each beat names a kind mix. */
const BEATS: ReadonlyArray<{ afterSec: number; kinds: DemoKind[]; dm?: boolean }> = [
  { afterSec: 0, kinds: ["view", "like"] },
  { afterSec: 25, kinds: ["view", "comment"] },
  { afterSec: 70, kinds: ["view", "like"] },
  { afterSec: 180, kinds: ["view"], dm: true },
  { afterSec: 300, kinds: ["view", "like", "comment"] },
  { afterSec: 720, kinds: ["view", "like"] },
  { afterSec: 1_500, kinds: ["view", "comment"] },
  { afterSec: 2_700, kinds: ["view", "like"] },
  { afterSec: 3_600, kinds: ["view", "like", "comment"] },
];

export function buildDemoPlan(
  postId: string,
  ownerUid: string,
  actorPool: readonly string[],
  config: StudentDemoConfig,
  nowMillis: number,
): DemoPlan | null {
  const actors = pickActors(actorPool.filter(uid => uid !== ownerUid), postId, config.actorsPerPost);
  if (!actors.length) return null;
  const steps: DemoStep[] = BEATS.map((beat, index) => {
    const actorUid = actors[index % actors.length];
    const step: DemoStep = {
      index,
      dueAtMillis: nowMillis + config.firstBeatMs + beat.afterSec * 1_000,
      actorUid,
      kinds: [...beat.kinds],
      done: false,
    };
    if (beat.kinds.includes("comment")) step.comment = demoComment(`${postId}:${index}:${actorUid}`);
    if (beat.dm && config.dmEnabled) step.dm = demoOpener(`${postId}:${actorUid}`);
    return step;
  });
  return { postId, ownerUid, createdAtMillis: nowMillis, steps, nextDueAtMillis: steps[0].dueAtMillis, source: STUDENT_DEMO_SOURCE };
}

export function nextDue(steps: readonly DemoStep[]): number | null {
  let next: number | null = null;
  for (const step of steps) if (!step.done && (next === null || step.dueAtMillis < next)) next = step.dueAtMillis;
  return next;
}

/** Idempotent engagement id: same post, step and kind → same id, so a retry
 *  returns the stored result instead of paying radius twice. */
export function demoEventId(postId: string, index: number, kind: DemoKind): string {
  return `${STUDENT_DEMO_EVENT_PREFIX}${demoHash(postId).toString(16)}-${index}-${kind}`;
}

/** A client message id the DM rules accept (`msg-` + 16–96 [A-Za-z0-9-]). */
export function demoMessageId(seed: string): string {
  const a = demoHash(`m1:${seed}`).toString(16).padStart(8, "0");
  const b = demoHash(`m2:${seed}`).toString(16).padStart(8, "0");
  return `msg-demo-${a}-${b}`;
}

export function canonicalThreadId(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

/** Same rule the client uses for a real tap: only a published, public,
 *  non-official post is something a fake tester would react to. */
export function demoEligiblePost(post: Record<string, unknown>): boolean {
  if (post.officialContent === true) return false;
  if (post.audience === "private") return false;
  if (post.status !== undefined && post.status !== "published") return false;
  if (post.processingStatus !== undefined && post.processingStatus !== "ready") return false;
  return true;
}

/** How many replies a thread may draw from the cohort per hour: enough for a
 *  conversation, never a loop with a student's auto-responder. */
export const DEMO_REPLIES_PER_HOUR = 6;
/** The fake tester "reads" before answering. */
export const DEMO_REPLY_DELAY_MS = 9_000;
