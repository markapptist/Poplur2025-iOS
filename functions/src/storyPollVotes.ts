import * as admin from "firebase-admin";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * Maintain poll totals from one vote document per account. A small event
 * receipt makes retries idempotent; changing a vote decrements the old option
 * and increments the new one in the same transaction.
 */
export const tallyStoryPollVote = onDocumentWritten(
  {
    document: "stories/{storyId}/votes/{actorId}",
    region: "us-central1",
  },
  async event => {
    const storyId = event.params.storyId;
    const beforeIndex = event.data?.before.data()?.optionIndex;
    const afterIndex = event.data?.after.data()?.optionIndex;
    if (beforeIndex === afterIndex) return;

    const database = admin.firestore();
    const story = database.collection("stories").doc(storyId);
    const receiptId = event.id.replace(/\//g, "_").slice(0, 500);
    const receipt = database.collection("storyVoteEvents").doc(receiptId);
    await database.runTransaction(async transaction => {
      const [receiptSnapshot, storySnapshot] = await Promise.all([
        transaction.get(receipt),
        transaction.get(story),
      ]);
      if (receiptSnapshot.exists || !storySnapshot.exists) return;
      const poll = storySnapshot.data()?.poll as {
        options?: unknown[];
        counts?: unknown[];
      } | undefined;
      const options = Array.isArray(poll?.options) ? poll.options : [];
      const counts = options.map((_, index) => {
        const count = Number(poll?.counts?.[index]);
        return Number.isFinite(count) ? Math.max(0, Math.round(count)) : 0;
      });
      if (Number.isInteger(beforeIndex) && beforeIndex >= 0 && beforeIndex < counts.length) {
        counts[beforeIndex] = Math.max(0, counts[beforeIndex] - 1);
      }
      if (Number.isInteger(afterIndex) && afterIndex >= 0 && afterIndex < counts.length) {
        counts[afterIndex] += 1;
      }
      transaction.update(story, { "poll.counts": counts });
      transaction.set(receipt, {
        storyId,
        actorId: event.params.actorId,
        handledAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);
