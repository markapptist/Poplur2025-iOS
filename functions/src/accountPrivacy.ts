import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();
const region = "us-central1";
const MIGRATION_CHUNK = 200;
const PRIVACY_SCHEMA_VERSION = 1;

function finiteCoordinate(value: unknown, limit: number): number | null {
  const numberValue = typeof value === "number" ? value : Number(value);
  return Number.isFinite(numberValue) && Math.abs(numberValue) <= limit ? numberValue : null;
}

function publicCell(value: number): number {
  return Math.round(value * 1_000);
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

/**
 * Account privacy changes also migrate existing posts. Firestore cannot hide
 * selected fields from a publicly readable document, so coordinates are
 * physically moved into the owner's protected postLocations collection.
 */
export const setAccountLocationPrivacy = onCall(
  { region, timeoutSeconds: 120, memory: "256MiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to change privacy.");
    if (typeof request.data?.privateAccount !== "boolean"
      || typeof request.data?.ghostMode !== "boolean") {
      throw new HttpsError("invalid-argument", "Private Account and Ghost Mode must be true or false.");
    }

    const privateAccount = request.data.privateAccount as boolean;
    const ghostMode = request.data.ghostMode as boolean;
    const hideOrigin = privateAccount || ghostMode;
    const userRef = db.collection("users").doc(uid);
    const currentAccount = (await userRef.get()).data();
    if (currentAccount?.locationPrivacySchemaVersion === PRIVACY_SCHEMA_VERSION
      && currentAccount?.privateAccount === privateAccount
      && currentAccount?.ghostMode === ghostMode) {
      return { privateAccount, ghostMode, migratedPosts: 0 };
    }

    // Setting the hiding flags first makes every new publisher choose the
    // hidden contract while legacy rows are being migrated.
    if (hideOrigin) {
      await userRef.set({
        privateAccount,
        ghostMode,
        accountPrivacyUpdatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    const [canonical, legacy] = await Promise.all([
      db.collection("posts").where("userID", "==", uid).get(),
      db.collection("posts").where("userId", "==", uid).get(),
    ]);
    const posts = new Map<string, admin.firestore.QueryDocumentSnapshot>();
    canonical.docs.forEach((document) => posts.set(document.id, document));
    legacy.docs.forEach((document) => posts.set(document.id, document));
    const documents = [...posts.values()];

    if (hideOrigin) {
      for (const group of chunks(documents, MIGRATION_CHUNK)) {
        const batch = db.batch();
        for (const document of group) {
          const data = document.data();
          const latitude = finiteCoordinate(data.latitude, 90);
          const longitude = finiteCoordinate(data.longitude, 180);
          if (latitude != null && longitude != null) {
            batch.set(userRef.collection("postLocations").doc(document.id), {
              latitude,
              longitude,
              updatedAt: FieldValue.serverTimestamp(),
              source: "legacy-public-migration",
            }, { merge: true });
          }
          batch.update(document.ref, {
            latitude: FieldValue.delete(),
            longitude: FieldValue.delete(),
            latitudeCell: FieldValue.delete(),
            longitudeCell: FieldValue.delete(),
            locationVisibility: "hidden",
            originHiddenByPrivateAccount: privateAccount,
            originHiddenByGhostMode: ghostMode,
          });
        }
        await batch.commit();
      }
    } else {
      for (const group of chunks(documents, MIGRATION_CHUNK)) {
        const locationRefs = group.map((document) => userRef.collection("postLocations").doc(document.id));
        const locations = locationRefs.length > 0 ? await db.getAll(...locationRefs) : [];
        const batch = db.batch();
        let writes = 0;
        group.forEach((document, index) => {
          const location = locations[index]?.data();
          const post = document.data();
          const latitude = finiteCoordinate(location?.latitude ?? post.latitude, 90);
          const longitude = finiteCoordinate(location?.longitude ?? post.longitude, 180);
          if (latitude == null || longitude == null) return;
          const latitudeCell = publicCell(latitude);
          const longitudeCell = publicCell(longitude);
          if (!location) {
            batch.set(locationRefs[index], {
              latitude,
              longitude,
              updatedAt: FieldValue.serverTimestamp(),
              source: "legacy-public-migration",
            }, { merge: true });
            writes += 1;
          }
          batch.update(document.ref, {
            latitude: latitudeCell / 1_000,
            longitude: longitudeCell / 1_000,
            latitudeCell,
            longitudeCell,
            locationVisibility: "approximate",
            originHiddenByPrivateAccount: FieldValue.delete(),
            originHiddenByGhostMode: FieldValue.delete(),
          });
          writes += 1;
        });
        if (writes > 0) await batch.commit();
      }
      await userRef.set({
        privateAccount: false,
        ghostMode: false,
        accountPrivacyUpdatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }

    await userRef.set({ locationPrivacySchemaVersion: PRIVACY_SCHEMA_VERSION }, { merge: true });

    return { privateAccount, ghostMode, migratedPosts: documents.length };
  }
);
