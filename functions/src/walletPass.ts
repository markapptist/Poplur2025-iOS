import { readFileSync } from "node:fs";
import { join } from "node:path";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { PKPass } from "passkit-generator";

/**
 * Issues an Apple Wallet pass for a Poplur card the caller actually owns.
 *
 * A Wallet pass is STATIC 2D — images, text fields and a barcode. The cards are
 * SceneKit models that turn, and none of that survives, so the pass carries the
 * flat poster that already ships in the app rather than a render of the model.
 * No new artwork is produced here; `pass-assets/` holds resized copies of the
 * posters and the app icon and nothing else.
 *
 * It is deliberately a `generic` pass and not a `storeCard`. Apple expects a
 * pass to DO something — a purely decorative collectible reads as off-label at
 * review — so this is issued as an identity card: the holder's handle, the card
 * they own, and a QR that resolves to their profile. That also makes it useful
 * in Poplur's own terms, since a scanned card is another way to be found.
 * `generic` is also the style whose thumbnail is square (90/180/270), which is
 * exactly the posters' native 720x720 — a `storeCard` strip is a wide banner and
 * would have meant cropping the art.
 */

/** PEM, from the Pass Type ID certificate issued in the Apple Developer portal. */
const passSignerCert = defineSecret("POPLUR_PASS_SIGNER_CERT");
/** PEM private key for the above. Encrypted keys need the passphrase secret. */
const passSignerKey = defineSecret("POPLUR_PASS_SIGNER_KEY");
const passSignerKeyPassphrase = defineSecret("POPLUR_PASS_SIGNER_KEY_PASSPHRASE");
/** Apple WWDR intermediate, PEM. Public, but kept beside the rest for one setup path. */
const passWWDRCert = defineSecret("POPLUR_PASS_WWDR_CERT");

/** Not secrets — they are printed on the pass and visible to anyone holding it. */
const passTypeIdentifier = defineString("POPLUR_PASS_TYPE_ID", {
  default: "pass.com.apptist.Poplur2025.card",
});
const passTeamIdentifier = defineString("POPLUR_PASS_TEAM_ID", { default: "" });

/** The four purchasable cards, keyed exactly as cardPurchases.ts records them. */
const CARD_NAMES: Record<string, string> = {
  inverted: "Inverted",
  lens: "Lens",
  splitDiamond: "Split Diamond",
  swoosh: "Swoosh",
};

/** cardID -> the poster basename in pass-assets. Only these ids are issuable. */
const CARD_ASSET: Record<string, string> = {
  inverted: "inverted",
  lens: "lens",
  splitDiamond: "split_diamond",
  swoosh: "swoosh",
};

// The card posters are product shots on a LIGHT backdrop (they double as store
// tiles), and the generic pass shows that thumbnail large. On Poplur's usual
// dark ground it read as a bright white tile stuck to a black card, so the pass
// takes the poster's side instead: light ground, dark ink, and the darker pink
// the app already uses for pink-on-light (NewsPaper's #c81d5e), not the neon
// that only works on black.
const PASS_BACKGROUND = "rgb(244, 244, 246)";
const PASS_INK = "rgb(22, 6, 15)";
const PASS_LABEL_PINK = "rgb(200, 29, 94)";

function assetPath(name: string): string {
  return join(__dirname, "pass-assets", name);
}

function readAsset(name: string): Buffer {
  return readFileSync(assetPath(name));
}

/**
 * Ownership comes from the same record the purchase verifier writes, so a pass
 * cannot be minted for a card the caller never bought. `verifiedStorePurchases`
 * is keyed by receipt fingerprint and carries `{userId, cardId}`; one matching
 * document is proof.
 */
async function ownsCard(uid: string, cardID: string): Promise<boolean> {
  const snapshot = await admin
    .firestore()
    .collection("verifiedStorePurchases")
    .where("userId", "==", uid)
    .where("cardId", "==", cardID)
    .limit(1)
    .get();
  return !snapshot.empty;
}

type ProfileSummary = { handle: string; displayName: string };

async function profileFor(uid: string): Promise<ProfileSummary> {
  const snapshot = await admin.firestore().collection("users").doc(uid).get();
  const data = snapshot.data() ?? {};
  const handleRaw = typeof data.username === "string" && data.username.trim()
    ? data.username.trim()
    : typeof data.handle === "string" && data.handle.trim()
      ? data.handle.trim()
      : uid.slice(0, 8);
  const handle = handleRaw.startsWith("@") ? handleRaw : `@${handleRaw}`;
  const displayName = typeof data.displayName === "string" && data.displayName.trim()
    ? data.displayName.trim()
    : handle;
  return { handle, displayName };
}

export const poplurWalletPass = onCall(
  {
    secrets: [passSignerCert, passSignerKey, passSignerKeyPassphrase, passWWDRCert],
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async request => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in to add a card to Wallet.");
    }

    const cardID = typeof request.data?.cardId === "string" ? request.data.cardId : "";
    const assetKey = CARD_ASSET[cardID];
    if (!assetKey) {
      throw new HttpsError("invalid-argument", `Unknown card "${cardID}".`);
    }

    const teamIdentifier = passTeamIdentifier.value();
    const signerCert = passSignerCert.value();
    const signerKey = passSignerKey.value();
    const wwdr = passWWDRCert.value();
    // Fail with the actual reason. Until the Pass Type ID certificate exists in
    // the Apple Developer portal there is nothing to sign with, and a generic
    // "internal" here would send someone hunting through the client.
    if (!signerCert || !signerKey || !wwdr || !teamIdentifier) {
      const missing = [
        !signerCert && "POPLUR_PASS_SIGNER_CERT",
        !signerKey && "POPLUR_PASS_SIGNER_KEY",
        !wwdr && "POPLUR_PASS_WWDR_CERT",
        !teamIdentifier && "POPLUR_PASS_TEAM_ID",
      ].filter(Boolean).join(", ");
      logger.error("Wallet pass signing is not configured", { missing });
      throw new HttpsError(
        "failed-precondition",
        `Wallet passes are not configured yet (missing: ${missing}).`
      );
    }

    if (!(await ownsCard(uid, cardID))) {
      throw new HttpsError("permission-denied", "You do not own that card.");
    }

    const { handle, displayName } = await profileFor(uid);

    // The serial is stable per user+card, so re-adding replaces the existing
    // pass in Wallet instead of stacking duplicates every time the button is
    // tapped. authenticationToken/webServiceURL are deliberately absent: this
    // is a snapshot, and advertising an update service we do not run would
    // leave Wallet retrying against nothing.
    const serialNumber = `${uid}.${cardID}`;

    try {
      const pkpass = buildCardPass({
        cardID,
        assetKey,
        handle,
        displayName,
        serialNumber,
        passTypeIdentifier: passTypeIdentifier.value(),
        teamIdentifier,
        certificates: {
          wwdr,
          signerCert,
          signerKey,
          signerKeyPassphrase: passSignerKeyPassphrase.value() || undefined,
        },
      });
      return { pkpass: pkpass.toString("base64"), serialNumber };
    } catch (error) {
      // A signing failure here is almost always a certificate mismatch: the
      // Pass Type ID inside the certificate must equal passTypeIdentifier, and
      // the team must match. Say which, rather than a bare "internal".
      logger.error("Could not sign the pass", {
        error: String(error),
        passTypeIdentifier: passTypeIdentifier.value(),
      });
      throw new HttpsError(
        "internal",
        "Could not sign the pass — check that the certificate matches "
          + `${passTypeIdentifier.value()} and team ${teamIdentifier}.`
      );
    }
  }
);

export type CardPassCertificates = {
  wwdr: string | Buffer;
  signerCert: string | Buffer;
  signerKey: string | Buffer;
  signerKeyPassphrase?: string;
};

export type CardPassRequest = {
  cardID: string;
  assetKey: string;
  handle: string;
  displayName: string;
  serialNumber: string;
  passTypeIdentifier: string;
  teamIdentifier: string;
  certificates: CardPassCertificates;
};

/**
 * Builds and signs the .pkpass. Deliberately separate from the callable above
 * and free of auth, Firestore and secrets, so the pass itself — assets, fields,
 * barcode, manifest, signature — can be exercised directly in a test with a
 * throwaway certificate instead of only in production.
 */
export function buildCardPass(request: CardPassRequest): Buffer {
  const profileURL = `https://poplur.com/u/${request.handle.replace(/^@/, "")}`;

  const pass = new PKPass({}, request.certificates, {
    passTypeIdentifier: request.passTypeIdentifier,
    teamIdentifier: request.teamIdentifier,
    serialNumber: request.serialNumber,
    organizationName: "Poplur",
    description: `Poplur card — ${CARD_NAMES[request.cardID] ?? request.cardID}`,
    foregroundColor: PASS_INK,
    backgroundColor: PASS_BACKGROUND,
    labelColor: PASS_LABEL_PINK,
  });

  pass.type = "generic";

  pass.addBuffer("icon.png", readAsset("icon.png"));
  pass.addBuffer("icon@2x.png", readAsset("icon@2x.png"));
  pass.addBuffer("icon@3x.png", readAsset("icon@3x.png"));
  pass.addBuffer("logo.png", readAsset("logo.png"));
  pass.addBuffer("logo@2x.png", readAsset("logo@2x.png"));
  pass.addBuffer("thumbnail.png", readAsset(`thumbnail-${request.assetKey}.png`));
  pass.addBuffer("thumbnail@2x.png", readAsset(`thumbnail-${request.assetKey}@2x.png`));
  pass.addBuffer("thumbnail@3x.png", readAsset(`thumbnail-${request.assetKey}@3x.png`));

  pass.primaryFields.push({ key: "holder", label: "POPLUR", value: request.displayName });
  pass.secondaryFields.push({ key: "handle", label: "HANDLE", value: request.handle });
  pass.auxiliaryFields.push({
    key: "card",
    label: "CARD",
    value: CARD_NAMES[request.cardID] ?? request.cardID,
  });
  pass.backFields.push(
    {
      key: "about",
      label: "About",
      value:
        "Your Poplur card. Scan the code to open this profile in Poplur — "
        + "everything you post reaches the people inside your radius.",
    },
    { key: "profile", label: "Profile", value: profileURL }
  );

  // The QR is what makes this a card that DOES something rather than a picture
  // in a wallet: someone scans it and lands on the holder's profile.
  pass.setBarcodes({
    message: profileURL,
    format: "PKBarcodeFormatQR",
    messageEncoding: "iso-8859-1",
    altText: request.handle,
  });

  return pass.getAsBuffer();
}
