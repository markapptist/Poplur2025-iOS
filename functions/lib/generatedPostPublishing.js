"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.publishGeneratedPost = publishGeneratedPost;
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
const postAdmission_1 = require("./postAdmission");
const radiusHistory_1 = require("./radiusHistory");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
/** A completed job publishes once. The job receipt, post, private origin and
 * human posting slot commit together; all native and AI writers contend on
 * the same per-account admission document. */
async function publishGeneratedPost(db, uid, jobId, input, chooseChannel) {
    if (!Number.isFinite(input.latitude) || Math.abs(input.latitude) > 90
        || !Number.isFinite(input.longitude) || Math.abs(input.longitude) > 180) {
        throw (0, postAdmission_1.publishingError)(400, 'invalid_location', 'Choose a valid post location.');
    }
    const jobRef = db.collection('aiGenerationJobs').doc(jobId);
    const userRef = db.collection('users').doc(uid);
    const admissionRef = db.collection(postAdmission_1.POST_ADMISSIONS).doc(uid);
    const postRef = db.collection('posts').doc(`post-ai-${(0, node_crypto_1.createHash)('sha256').update(`${uid}\0${jobId}`).digest('hex')}`);
    return db.runTransaction(async (tx) => {
        const job = (await tx.get(jobRef)).data();
        if (!job || job.userId !== uid)
            throw (0, postAdmission_1.publishingError)(404, 'job_not_found', 'AI job not found.');
        if (typeof job.publishedPostId === 'string' && job.publishedPostId) {
            const chosenChannelId = job.publishedChannelId ?? input.channelId;
            const originalChannelId = job.publishedOriginalChannelId ?? input.channelId;
            return { postId: job.publishedPostId, chosenChannelId, originalChannelId, rerouted: chosenChannelId !== originalChannelId };
        }
        if (job.status !== 'completed')
            throw (0, postAdmission_1.publishingError)(409, 'job_not_complete', 'This AI job is not ready to publish yet.');
        const [userSnapshot, admissionSnapshot] = await Promise.all([tx.get(userRef), tx.get(admissionRef)]);
        const account = userSnapshot.data() ?? {};
        const nowMillis = Date.now();
        const admission = /^(sim|synthetic)-/.test(uid) ? null
            : (0, postAdmission_1.nextPostAdmission)(admissionSnapshot.data(), account, postRef.id, nowMillis);
        const chosenChannelId = chooseChannel(input.channelId, job.prompt, job.contentType);
        const hiddenOrigin = account.privateAccount === true || account.ghostMode === true;
        // Match existing native create rules: generation itself is not engagement.
        const earned = Math.max(0, Number(account.earnedClaimMeters) || 0);
        const committed = Math.max(0, Number(account.committedClaimMeters) || 0);
        const allowance = Math.min(6_371_000, Math.max(0, earned - committed) + 5_000);
        const radiusMeters = Math.min(allowance, Math.max(0, Math.round(input.radiusMeters) || 5_000));
        const now = firestore_1.FieldValue.serverTimestamp();
        const post = {
            userId: uid, userID: uid, aiGenerated: true, aiGenerationJobId: jobId,
            assetIds: Array.isArray(job.outputAssetIds) ? job.outputAssetIds : [],
            channelId: chosenChannelId, originalChannelId: input.channelId,
            channelReviewStatus: chosenChannelId === input.channelId ? 'approved' : 'rerouted',
            audience: 'public', locationVisibility: hiddenOrigin ? 'hidden' : 'approximate',
            radius: radiusMeters, radiusMeters, seedRadiusMeters: radiusMeters, organicRadiusMeters: 0,
            viewCount: 0, visibilityStatus: 'published',
            caption: input.caption ?? job.outputText ?? '', createdAt: now, updatedAt: now,
        };
        if (!hiddenOrigin) {
            const latitudeCell = Math.round(input.latitude * 1_000);
            const longitudeCell = Math.round(input.longitude * 1_000);
            Object.assign(post, { latitudeCell, longitudeCell, latitude: latitudeCell / 1_000, longitude: longitudeCell / 1_000 });
        }
        tx.create(postRef, post);
        if (admission)
            tx.set(admissionRef, admission);
        tx.set((0, radiusHistory_1.radiusHistoryRef)(postRef, postEngagementPolicy_1.radiusHistoryEntryId.create()), (0, radiusHistory_1.radiusHistoryDocument)((0, radiusHistory_1.creationHistoryEntry)(post, nowMillis, 'poplurAiApi.publishGeneratedJob')));
        tx.set(userRef.collection('postLocations').doc(postRef.id), {
            latitude: input.latitude, longitude: input.longitude, createdAt: now, source: 'ai-generated-post',
        });
        tx.set(jobRef, { publishedPostId: postRef.id, publishedChannelId: chosenChannelId,
            publishedOriginalChannelId: input.channelId, updatedAt: now }, { merge: true });
        return { postId: postRef.id, chosenChannelId, originalChannelId: input.channelId, rerouted: chosenChannelId !== input.channelId };
    });
}
