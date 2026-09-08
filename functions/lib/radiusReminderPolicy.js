"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.RADIUS_REMINDER_COOLDOWN_MS = void 0;
exports.radiusReminderDue = radiusReminderDue;
exports.RADIUS_REMINDER_COOLDOWN_MS = 24 * 3600_000;
/** Radius history still records every loss; a posting nudge is one daily
 * reminder per person, even when hundreds of their posts decay together. */
function radiusReminderDue(lastReminderAtMillis, nowMillis) {
    return typeof lastReminderAtMillis !== 'number' || !Number.isFinite(lastReminderAtMillis)
        || nowMillis - lastReminderAtMillis >= exports.RADIUS_REMINDER_COOLDOWN_MS;
}
