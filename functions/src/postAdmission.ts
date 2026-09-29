import { FieldValue, Timestamp } from 'firebase-admin/firestore';

export const POST_ADMISSIONS = 'postAdmissions';
export const POST_COOLDOWN_MS = 60_000;
export const POST_WINDOW_MS = 86_400_000;
export const POST_WINDOW_LIMIT = 30;

export function publishingError(status: number, code: string, message: string): Error & { status: number; code: string } {
  return Object.assign(new Error(message), { status, code });
}

function finite(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** Admin writers bypass rules and MUST call this inside the same transaction
 * that reads postAdmissions/{uid} and creates the post. Native clients propose
 * this identical transition, independently enforced by firestore.rules. */
export function nextPostAdmission(
  previous: Record<string, unknown> | undefined,
  account: Record<string, unknown>,
  postId: string,
  nowMillis: number,
): Record<string, unknown> {
  const last = previous?.lastPostAt instanceof Timestamp
    ? previous.lastPostAt.toMillis() : finite(account.lastPostAtMillis);
  const start = previous?.windowStartedAt instanceof Timestamp
    ? previous.windowStartedAt : Timestamp.fromMillis(Math.max(0, finite(account.postWindowStartMillis)));
  const count = Math.max(0, finite((previous ?? account).postsInWindow));
  const active = start.toMillis() > 0 && nowMillis - start.toMillis() < POST_WINDOW_MS;
  if (last > 0 && nowMillis - last < POST_COOLDOWN_MS) {
    throw publishingError(429, 'post_cooldown', 'Wait a minute between posts. Your draft is saved.');
  }
  if (active && count >= POST_WINDOW_LIMIT) {
    throw publishingError(429, 'post_daily_limit', "You've reached 30 posts in this 24-hour window. Your draft is saved.");
  }
  return {
    postId, lastPostAt: FieldValue.serverTimestamp(),
    windowStartedAt: active ? start : FieldValue.serverTimestamp(),
    postsInWindow: active ? Math.round(count) + 1 : 1,
  };
}
