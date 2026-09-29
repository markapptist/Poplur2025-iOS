"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.POST_WINDOW_LIMIT = exports.POST_WINDOW_MS = exports.POST_COOLDOWN_MS = exports.POST_ADMISSIONS = void 0;
exports.publishingError = publishingError;
exports.nextPostAdmission = nextPostAdmission;
const firestore_1 = require("firebase-admin/firestore");
exports.POST_ADMISSIONS = 'postAdmissions';
exports.POST_COOLDOWN_MS = 60_000;
exports.POST_WINDOW_MS = 86_400_000;
exports.POST_WINDOW_LIMIT = 30;
function publishingError(status, code, message) {
    return Object.assign(new Error(message), { status, code });
}
function finite(value) {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}
/** Admin writers bypass rules and MUST call this inside the same transaction
 * that reads postAdmissions/{uid} and creates the post. Native clients propose
 * this identical transition, independently enforced by firestore.rules. */
function nextPostAdmission(previous, account, postId, nowMillis) {
    const last = previous?.lastPostAt instanceof firestore_1.Timestamp
        ? previous.lastPostAt.toMillis() : finite(account.lastPostAtMillis);
    const start = previous?.windowStartedAt instanceof firestore_1.Timestamp
        ? previous.windowStartedAt : firestore_1.Timestamp.fromMillis(Math.max(0, finite(account.postWindowStartMillis)));
    const count = Math.max(0, finite((previous ?? account).postsInWindow));
    const active = start.toMillis() > 0 && nowMillis - start.toMillis() < exports.POST_WINDOW_MS;
    if (last > 0 && nowMillis - last < exports.POST_COOLDOWN_MS) {
        throw publishingError(429, 'post_cooldown', 'Wait a minute between posts. Your draft is saved.');
    }
    if (active && count >= exports.POST_WINDOW_LIMIT) {
        throw publishingError(429, 'post_daily_limit', "You've reached 30 posts in this 24-hour window. Your draft is saved.");
    }
    return {
        postId, lastPostAt: firestore_1.FieldValue.serverTimestamp(),
        windowStartedAt: active ? start : firestore_1.FieldValue.serverTimestamp(),
        postsInWindow: active ? Math.round(count) + 1 : 1,
    };
}
