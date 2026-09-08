"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.notifyOnRadiusLoss = void 0;
exports.radiusLossNotification = radiusLossNotification;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const accountRadius_1 = require("./accountRadius");
if (!admin.apps.length)
    admin.initializeApp();
function radiusLossNotification(entry) {
    const delta = entry.delta;
    if (entry.cause !== 'decay' || typeof delta !== 'number' || !Number.isFinite(delta) || delta >= 0)
        return null;
    return { delta, title: 'Your radius is going down',
        body: `Radius decreased ${Number((Math.abs(delta) / 1000).toFixed(3))} km. ${entry.radiusMeters === 0 ? 'This post has expired. ' : ''}Post again to grow your reach.` };
}
/** History is committed with the actual account debit, so failed/no-op decay
 * cannot create an alert. The history ID also deduplicates trigger redelivery. */
exports.notifyOnRadiusLoss = (0, firestore_2.onDocumentCreated)({ document: 'posts/{postId}/radiusHistory/{historyId}', region: 'us-central1' }, async (event) => {
    const notification = radiusLossNotification(event.data?.data() || {});
    if (!notification)
        return;
    const db = admin.firestore(), { postId, historyId } = event.params;
    const post = await db.doc(`posts/${postId}`).get();
    if (!post.exists)
        return;
    const uid = (0, accountRadius_1.postOwnerUid)(post.data() || {});
    if (!uid)
        return;
    const userRef = db.doc(`users/${uid}`);
    const notificationId = `radius-loss:${postId}:${historyId}`;
    const created = await userRef.collection('notifications').doc(notificationId).create({
        id: notificationId, kind: 'decrease', title: notification.title, detail: notification.body,
        actorUid: '', actorHandle: '', radiusDeltaMeters: notification.delta,
        createdAt: firestore_1.FieldValue.serverTimestamp(), isUnread: true, isDismissed: false, postId, historyId,
    }).then(() => true).catch((error) => {
        if (error.code !== 6)
            throw error;
        return false;
    });
    if (!created)
        return;
    const tokens = Object.keys((await userRef.get()).data()?.fcmTokens || {});
    for (let offset = 0; offset < tokens.length; offset += 500) {
        const batch = tokens.slice(offset, offset + 500);
        const result = await admin.messaging().sendEachForMulticast({
            tokens: batch, notification: { title: notification.title, body: notification.body },
            data: { postId, historyId, notificationId, kind: 'decrease', radiusDeltaMeters: String(notification.delta) },
            apns: { payload: { aps: { 'thread-id': postId, sound: 'default' } } },
            android: { priority: 'high', notification: { channelId: 'poplur_alerts', tag: postId } },
        });
        for (let i = 0; i < result.responses.length; i++) {
            if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.responses[i].error?.code || '')) {
                await userRef.update(new firestore_1.FieldPath('fcmTokens', batch[i]), firestore_1.FieldValue.delete());
            }
        }
    }
});
