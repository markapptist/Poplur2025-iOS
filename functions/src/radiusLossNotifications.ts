import * as admin from 'firebase-admin';
import { FieldPath, FieldValue } from 'firebase-admin/firestore';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { postOwnerUid } from './accountRadius';
import { radiusReminderDue } from './radiusReminderPolicy';
import { prefsFromUser, pushAllowed } from './notificationPrefs';

if (!admin.apps.length) admin.initializeApp();

export function radiusLossNotification(entry: Record<string, unknown>) {
  const delta = entry.delta;
  if (entry.cause !== 'decay' || typeof delta !== 'number' || !Number.isFinite(delta) || delta >= 0) return null;
  return { delta, title: 'Your radius is going down',
    body: `Radius decreased ${Number((Math.abs(delta) / 1000).toFixed(3))} km. ${entry.radiusMeters === 0 ? 'This post has expired. ' : ''}Post again to grow your reach.` };
}

/** History is committed with the actual account debit, so failed/no-op decay
 * cannot create an alert. The history ID also deduplicates trigger redelivery. */
export const notifyOnRadiusLoss = onDocumentCreated(
  { document: 'posts/{postId}/radiusHistory/{historyId}', region: 'us-central1' },
  async event => {
    const notification = radiusLossNotification(event.data?.data() || {});
    if (!notification) return;
    const db = admin.firestore(), { postId, historyId } = event.params;
    const post = await db.doc(`posts/${postId}`).get();
    if (!post.exists) return;
    const uid = postOwnerUid(post.data() || {});
    if (!uid) return;
    const userRef = db.doc(`users/${uid}`);
    const notificationId = `radius-loss:${postId}:${historyId}`;
    const notificationRef = userRef.collection('notifications').doc(notificationId);
    const tokens = await db.runTransaction(async tx => {
      const [existing, user] = await tx.getAll(notificationRef, userRef);
      if (existing.exists) return [] as string[];
      tx.create(notificationRef, {
      id: notificationId, kind: 'decrease', title: notification.title, detail: notification.body,
      actorUid: '', actorHandle: '', radiusDeltaMeters: notification.delta,
      createdAt: FieldValue.serverTimestamp(), isUnread: true, isDismissed: false, postId, historyId,
      });
      const data = user.data() || {};
      const registered = Object.keys(data.fcmTokens || {});
      // Muted radius news never reserves the daily slot either — otherwise
      // turning it back on could find the day already spent on a push nobody
      // was sent.
      if (!pushAllowed(prefsFromUser(data), 'radius')) return [] as string[];
      if (!registered.length || !radiusReminderDue(data.radiusReminderAtMillis, Date.now())) return [] as string[];
      // One atomic reservation across all posts prevents simultaneous decay
      // triggers from turning a daily reminder into a burst of pushes.
      tx.set(userRef, { radiusReminderAtMillis: Date.now() }, { merge: true });
      return registered;
    });
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
          await userRef.update(new FieldPath('fcmTokens', batch[i]), FieldValue.delete());
        }
      }
    }
  },
);
