export const RADIUS_REMINDER_COOLDOWN_MS = 24 * 3600_000;
/** Radius history still records every loss; a posting nudge is one daily
 * reminder per person, even when hundreds of their posts decay together. */
export function radiusReminderDue(lastReminderAtMillis: unknown, nowMillis: number): boolean {
  return typeof lastReminderAtMillis !== 'number' || !Number.isFinite(lastReminderAtMillis)
    || nowMillis - lastReminderAtMillis >= RADIUS_REMINDER_COOLDOWN_MS;
}
