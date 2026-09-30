import * as admin from "firebase-admin";
import { FieldPath, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { DESK_OWNER_UIDS } from "./syntheticIdentity";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * Who hears about each new report. The owner accounts review reports: the App
 * Store (guideline 1.2) and Google Play's user-generated-content policy both
 * expect reports of people and pops to reach someone who acts on them.
 */
export const REPORT_MODERATOR_UIDS: readonly string[] = DESK_OWNER_UIDS;

/** A second report from the same person inside this window does not push again. */
export const REPORT_PUSH_COOLDOWN_MS = 10 * 60 * 1000;

export interface ReportDocument {
  reporterId?: unknown;
  userId?: unknown;
  username?: unknown;
  reason?: unknown;
  source?: unknown;
  postId?: unknown;
  createdAt?: unknown;
}

const text = (value: unknown): string => (typeof value === "string" ? value.trim() : "");

/** The push a moderator sees. Names the reported account and, for a pop, says so. */
export function reportSummary(report: ReportDocument): { title: string; body: string } {
  const handle = text(report.username).replace(/^@+/, "");
  const who = handle ? `@${handle}` : "An account";
  const subject = text(report.postId) ? `A pop by ${handle ? `@${handle}` : "an account"}` : who;
  const reason = text(report.reason);
  const body = reason ? `${subject} was reported: ${reason}.` : `${subject} was reported.`;
  return { title: "New report on Poplur", body: body.length > 180 ? `${body.slice(0, 177)}…` : body };
}

function millis(value: unknown): number | null {
  if (value && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    return (value as { toMillis: () => number }).toMillis();
  }
  return null;
}

/** True when the same reporter already filed a report inside the cooldown. */
export function withinCooldown(otherReportTimes: Array<number | null>, now: number): boolean {
  return otherReportTimes.some((time) => time !== null && now - time >= 0 && now - time < REPORT_PUSH_COOLDOWN_MS);
}

export const notifyOnReport = onDocumentCreated(
  { document: "reports/{reportId}", region: "us-central1" },
  async (event) => {
    const report = event.data?.data() as ReportDocument | undefined;
    if (!report) return;
    const reportId = event.params.reportId;
    const reporterId = text(report.reporterId);
    const db = admin.firestore();

    // One push per reporter per window, so a burst of reports cannot flood the
    // moderators' phones. Every report is still stored in `reports`.
    if (reporterId) {
      const earlier = await db.collection("reports").where("reporterId", "==", reporterId).limit(25).get();
      const times = earlier.docs.filter((doc) => doc.id !== reportId).map((doc) => millis(doc.get("createdAt")));
      if (withinCooldown(times, Date.now())) {
        logger.info("Report stored; push skipped inside the cooldown", { reportId });
        return;
      }
    }

    const { title, body } = reportSummary(report);
    for (const moderatorUid of REPORT_MODERATOR_UIDS) {
      const userRef = db.collection("users").doc(moderatorUid);
      const tokens = Object.keys((((await userRef.get()).data() ?? {}).fcmTokens ?? {}) as Record<string, unknown>);
      if (tokens.length === 0) continue;
      const response = await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: { kind: "report", reportId },
        apns: { payload: { aps: { sound: "poplur_pop.wav" } } },
      });
      // Drop tokens the messaging service says will never work again.
      const dead = response.responses
        .map((result, index) => ({ result, token: tokens[index] }))
        .filter(({ result }) => !result.success && [
          "messaging/registration-token-not-registered",
          "messaging/invalid-registration-token",
        ].includes(result.error?.code ?? ""))
        .map(({ token }) => token);
      for (const token of dead) {
        await userRef.update(new FieldPath("fcmTokens", token), FieldValue.delete()).catch(() => undefined);
      }
      logger.info("Report push sent", { reportId, moderatorUid, sent: response.successCount, dead: dead.length });
    }
  },
);
