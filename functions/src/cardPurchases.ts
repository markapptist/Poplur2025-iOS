import { createHash } from "crypto";
import { readFileSync } from "fs";
import { join } from "path";
import {
  Environment,
  JWSTransactionDecodedPayload,
  SignedDataVerifier,
  Type,
} from "@apple/app-store-server-library";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { google } from "googleapis";

const protectedRegion = "us-central1";
const iosBundleID = "com.apptist.Poplur2025";
const androidPackageName = "com.apptists.poplur2025";
const appleAppID = defineString("APPLE_APP_ID", {
  default: "",
  description: "The numeric App Store Connect Apple ID for com.apptist.Poplur2025.",
});

type CardProduct = {
  cardID: string;
  iosProductID: string;
  androidProductID: string;
  credits: number;
};

const cards: CardProduct[] = [
  {
    cardID: "inverted",
    iosProductID: "com.apptist.Poplur2025.card.inverted",
    androidProductID: "com.apptists.poplur2025.card.inverted",
    credits: 300,
  },
  {
    cardID: "lens",
    iosProductID: "com.apptist.Poplur2025.card.lens",
    androidProductID: "com.apptists.poplur2025.card.lens",
    credits: 550,
  },
  {
    cardID: "splitDiamond",
    iosProductID: "com.apptist.Poplur2025.card.splitdiamond",
    androidProductID: "com.apptists.poplur2025.card.splitdiamond",
    credits: 800,
  },
  {
    cardID: "swoosh",
    iosProductID: "com.apptist.Poplur2025.card.swoosh",
    androidProductID: "com.apptists.poplur2025.card.swoosh",
    credits: 1_200,
  },
];

const cardProducts = new Map<string, CardProduct>(
  cards.flatMap(card => [
    [card.iosProductID, card] as const,
    [card.androidProductID, card] as const,
  ])
);

type VerifiedCardPurchase = {
  platform: "ios" | "android";
  product: CardProduct;
  receiptID: string;
  accountBinding: string;
  purchasedAt: Date;
  environment: string;
  orderID?: string;
};

type GrantResult = {
  alreadyGranted: boolean;
  availableCredits: number;
};

/**
 * Verifies a StoreKit or Google Play transaction with the store, then grants
 * Poplur credits in one idempotent Admin SDK transaction. Clients never send
 * a credit amount and never write the protected balance or ledger themselves.
 */
export const verifyCardPurchase = onCall(
  {
    region: protectedRegion,
    enforceAppCheck: true,
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in before purchasing Poplur credits.");
    }

    const platform = requiredString(request.data?.platform, "platform", 16);
    const claimedProductID = requiredString(request.data?.productId, "productId", 160);
    const product = cardProducts.get(claimedProductID);
    if (!product) {
      throw new HttpsError("invalid-argument", "This Poplur card product is not supported.");
    }

    try {
      const verified = platform === "ios"
        ? await verifyApplePurchase(uid, product, request.data)
        : platform === "android"
          ? await verifyGooglePlayPurchase(uid, product, request.data)
          : null;

      if (!verified) {
        throw new HttpsError("invalid-argument", "platform must be ios or android.");
      }

      const grant = await grantVerifiedPurchase(uid, verified);
      return {
        verified: true,
        alreadyGranted: grant.alreadyGranted,
        productId: platform === "ios" ? product.iosProductID : product.androidProductID,
        cardId: product.cardID,
        credits: product.credits,
        creditsAdded: grant.alreadyGranted ? 0 : product.credits,
        availableCredits: grant.availableCredits,
      };
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error("card_purchase_verification_failed", {
        platform,
        productID: claimedProductID,
        uidSuffix: uid.slice(-6),
        error: error instanceof Error ? error.message.slice(0, 240) : "unknown",
      });
      throw new HttpsError(
        "failed-precondition",
        "The store could not verify this purchase. You have not been charged again; retry from your bag."
      );
    }
  }
);

async function verifyApplePurchase(
  uid: string,
  product: CardProduct,
  data: unknown
): Promise<VerifiedCardPurchase> {
  const body = objectValue(data);
  const signedTransaction = requiredString(body.signedTransaction, "signedTransaction", 30_000);
  const transaction = await decodeVerifiedAppleTransaction(signedTransaction);

  if (
    transaction.bundleId !== iosBundleID ||
    transaction.productId !== product.iosProductID ||
    transaction.type !== Type.CONSUMABLE ||
    (transaction.quantity ?? 1) !== 1 ||
    !transaction.transactionId ||
    !transaction.purchaseDate ||
    transaction.revocationDate !== undefined
  ) {
    throw new HttpsError("failed-precondition", "The App Store transaction does not match this card.");
  }

  const expectedToken = storeKitAccountToken(uid);
  if (transaction.appAccountToken?.toLowerCase() !== expectedToken) {
    throw new HttpsError("permission-denied", "This purchase belongs to a different Poplur account.");
  }

  return {
    platform: "ios",
    product,
    receiptID: transaction.transactionId,
    accountBinding: expectedToken,
    purchasedAt: new Date(transaction.purchaseDate),
    environment: String(transaction.environment ?? "unknown"),
  };
}

async function decodeVerifiedAppleTransaction(
  signedTransaction: string
): Promise<JWSTransactionDecodedPayload> {
  const roots = appleRootCertificates();
  const sandboxVerifier = new SignedDataVerifier(
    roots,
    true,
    Environment.SANDBOX,
    iosBundleID
  );

  try {
    return await sandboxVerifier.verifyAndDecodeTransaction(signedTransaction);
  } catch (sandboxError) {
    const configuredAppID = Number.parseInt(appleAppID.value(), 10);
    if (!Number.isSafeInteger(configuredAppID) || configuredAppID <= 0) {
      logger.warn("apple_production_verifier_not_configured", {
        sandboxError: sandboxError instanceof Error ? sandboxError.message : "verification failed",
      });
      throw new HttpsError(
        "failed-precondition",
        "Production purchase verification is not configured yet."
      );
    }
    const productionVerifier = new SignedDataVerifier(
      roots,
      true,
      Environment.PRODUCTION,
      iosBundleID,
      configuredAppID
    );
    return productionVerifier.verifyAndDecodeTransaction(signedTransaction);
  }
}

async function verifyGooglePlayPurchase(
  uid: string,
  product: CardProduct,
  data: unknown
): Promise<VerifiedCardPurchase> {
  const body = objectValue(data);
  const purchaseToken = requiredString(body.purchaseToken, "purchaseToken", 4_096);
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const publisher = google.androidpublisher({ version: "v3", auth });
  const response = await publisher.purchases.products.get({
    packageName: androidPackageName,
    productId: product.androidProductID,
    token: purchaseToken,
  });
  const purchase = response.data;
  const expectedBinding = googlePlayAccountBinding(uid);
  const purchasedAtMillis = Number(purchase.purchaseTimeMillis);

  if (
    purchase.purchaseState !== 0 ||
    !Number.isFinite(purchasedAtMillis) ||
    purchasedAtMillis <= 0 ||
    (purchase.productId !== undefined && purchase.productId !== product.androidProductID) ||
    (purchase.quantity ?? 1) !== 1 ||
    (purchase.refundableQuantity ?? 1) < 1 ||
    purchase.obfuscatedExternalAccountId?.toLowerCase() !== expectedBinding
  ) {
    throw new HttpsError("failed-precondition", "The Google Play purchase does not match this card.");
  }

  return {
    platform: "android",
    product,
    receiptID: purchaseToken,
    orderID: purchase.orderId ?? undefined,
    accountBinding: expectedBinding,
    purchasedAt: new Date(purchasedAtMillis),
    environment: purchase.purchaseType === 0 ? "test" : "production",
  };
}

async function grantVerifiedPurchase(
  uid: string,
  purchase: VerifiedCardPurchase
): Promise<GrantResult> {
  const db = admin.firestore();
  const receiptFingerprint = sha256(`${purchase.platform}:${purchase.receiptID}`);
  const purchaseRef = db.collection("verifiedStorePurchases").doc(receiptFingerprint);
  const balanceRef = db.collection("creatorCreditBalances").doc(uid);
  const ledgerRef = db.collection("creatorCreditTransactions").doc(`store_${receiptFingerprint}`);

  return db.runTransaction(async transaction => {
    const [purchaseSnapshot, balanceSnapshot] = await Promise.all([
      transaction.get(purchaseRef),
      transaction.get(balanceRef),
    ]);
    const balance = balanceSnapshot.data() ?? {};
    const availableCredits = nonNegativeInteger(balance.availableCredits);

    if (purchaseSnapshot.exists) {
      const previous = purchaseSnapshot.data() ?? {};
      const platformProductID = purchase.platform === "ios"
        ? purchase.product.iosProductID
        : purchase.product.androidProductID;
      if (previous.userId !== uid || previous.productId !== platformProductID) {
        throw new HttpsError("permission-denied", "This store transaction was already claimed.");
      }
      return { alreadyGranted: true, availableCredits };
    }

    const newBalance = availableCredits + purchase.product.credits;
    transaction.set(balanceRef, {
      availableCredits: newBalance,
      lifetimeEarned: nonNegativeInteger(balance.lifetimeEarned) + purchase.product.credits,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    transaction.create(purchaseRef, {
      userId: uid,
      platform: purchase.platform,
      productId: purchase.platform === "ios"
        ? purchase.product.iosProductID
        : purchase.product.androidProductID,
      cardId: purchase.product.cardID,
      credits: purchase.product.credits,
      receiptFingerprint,
      orderId: purchase.orderID ?? null,
      accountBinding: purchase.accountBinding,
      environment: purchase.environment,
      purchasedAt: admin.firestore.Timestamp.fromDate(purchase.purchasedAt),
      grantedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(ledgerRef, {
      userId: uid,
      amount: purchase.product.credits,
      type: "store_card_purchase",
      platform: purchase.platform,
      productId: purchase.platform === "ios"
        ? purchase.product.iosProductID
        : purchase.product.androidProductID,
      cardId: purchase.product.cardID,
      verifiedPurchaseId: purchaseRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { alreadyGranted: false, availableCredits: newBalance };
  });
}

function appleRootCertificates(): Buffer[] {
  return ["AppleIncRootCertificate.cer", "AppleRootCA-G2.cer", "AppleRootCA-G3.cer"].map(file =>
    readFileSync(join(__dirname, "apple-root-certificates", file))
  );
}

function storeKitAccountToken(uid: string): string {
  const bytes = Buffer.from(createHash("sha256").update(uid, "utf8").digest().subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function googlePlayAccountBinding(uid: string): string {
  return sha256(uid);
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function requiredString(value: unknown, name: string, maxLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${name} is required.`);
  }
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return trimmed;
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Purchase data must be an object.");
  }
  return value as Record<string, unknown>;
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}
