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
exports.accountRadiusOnPostDeleted = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const accountRadius_1 = require("./accountRadius");
if (admin.apps.length === 0)
    admin.initializeApp();
/**
 * Take a deleted post's earned radius back out of its owner's entitlement.
 *
 * See accountRadius.ts for why: the aggregate the create rule reads has to
 * stay equal to a sum over the posts, and a post that is gone contributes
 * nothing to that sum. The receipt document makes a repeated delivery a no-op,
 * and is the only reason this can use a plain increment.
 */
exports.accountRadiusOnPostDeleted = (0, firestore_2.onDocumentDeleted)({ document: "posts/{postId}", region: "us-central1" }, async (event) => {
    const post = event.data?.data() ?? {};
    const ownerUid = (0, accountRadius_1.postOwnerUid)(post);
    const earned = (0, accountRadius_1.postEarnedRadiusMeters)(post);
    if (!ownerUid || earned <= 0)
        return;
    const db = admin.firestore();
    const receiptRef = db.collection(accountRadius_1.CLAIM_RADIUS_RECEIPTS).doc(event.params.postId);
    await db.runTransaction(async (transaction) => {
        const [receipt, deletion] = await Promise.all([
            transaction.get(receiptRef),
            transaction.get(db.collection("accountDeletions").doc(ownerUid)),
        ]);
        if (deletion.exists)
            return;
        if (receipt.exists)
            return;
        transaction.create(receiptRef, {
            ownerUid,
            earnedRadiusMeters: earned,
            deletedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        transaction.set(db.collection("users").doc(ownerUid), {
            [accountRadius_1.ACCOUNT_CLAIM_RADIUS_FIELD]: firestore_1.FieldValue.increment(-earned),
            claimRadiusUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    });
});
