import { connect } from "node:http2";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { defineSecret, defineString } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { Request, Response } from "express";

import {
  CARD_ASSET,
  buildCardPass,
  ownsCard,
  profileFor,
} from "./walletPass";

/**
 * Apple's PassKit Web Service, so an installed pass can change after it is
 * added instead of being a snapshot frozen at the moment of the tap.
 *
 * The protocol is five endpoints and one push. A device registers itself and
 * its APNs token against a pass; when the pass content changes we push an EMPTY
 * payload to those tokens; the device then asks us for the pass again and
 * replaces what it holds. Wallet never receives content over push — the push is
 * only a nudge — so nothing sensitive travels through APNs.
 *
 * @see https://developer.apple.com/documentation/walletpasses
 */

const passSignerCert = defineSecret("POPLUR_PASS_SIGNER_CERT");
const passSignerKey = defineSecret("POPLUR_PASS_SIGNER_KEY");
const passSignerKeyPassphrase = defineSecret("POPLUR_PASS_SIGNER_KEY_PASSPHRASE");
const passWWDRCert = defineSecret("POPLUR_PASS_WWDR_CERT");
const passTypeIdentifier = defineString("POPLUR_PASS_TYPE_ID", {
  default: "pass.com.apptist.Poplur2025.card",
});
// Apptist Inc.'s team, read off the developer portal. Not a secret — it is
// printed inside every pass and every provisioning profile — so it ships as a
// default rather than as one more thing to configure before this works.
const passTeamIdentifier = defineString("POPLUR_PASS_TEAM_ID", { default: "VDQS4882Z8" });
const passWebServiceURL = defineString("POPLUR_PASS_WEB_SERVICE_URL", { default: "" });

const PASS_SECRETS = [
  passSignerCert,
  passSignerKey,
  passSignerKeyPassphrase,
  passWWDRCert,
];

/** `{uid}.{cardId}` — the serial minted in walletPass.ts. */
function parseSerial(serialNumber: string): { uid: string; cardID: string } | null {
  const separator = serialNumber.lastIndexOf(".");
  if (separator <= 0) return null;
  const uid = serialNumber.slice(0, separator);
  const cardID = serialNumber.slice(separator + 1);
  if (!uid || !(cardID in CARD_ASSET)) return null;
  return { uid, cardID };
}

/**
 * Every authenticated endpoint carries `Authorization: ApplePass <token>`.
 * Compared against the token stored when the pass was minted — and compared in
 * constant time, because a length-varying compare on a secret handed out inside
 * a shareable file is exactly the kind of oracle worth not building.
 */
async function authorizedFor(request: Request, serialNumber: string): Promise<boolean> {
  const header = request.get("authorization") ?? "";
  const presented = header.startsWith("ApplePass ") ? header.slice("ApplePass ".length) : "";
  if (!presented) return false;
  const snapshot = await admin.firestore().collection("walletPasses").doc(serialNumber).get();
  const expected = snapshot.data()?.authenticationToken;
  if (typeof expected !== "string" || expected.length !== presented.length) return false;
  const { timingSafeEqual } = await import("node:crypto");
  return timingSafeEqual(Buffer.from(expected), Buffer.from(presented));
}

function certificatesConfigured(): boolean {
  return Boolean(
    passSignerCert.value() && passSignerKey.value()
      && passWWDRCert.value() && passTeamIdentifier.value()
  );
}

/** Re-signs the pass from current profile data. */
async function currentPass(uid: string, cardID: string, serialNumber: string) {
  const { handle, displayName } = await profileFor(uid);
  const token = (await admin.firestore().collection("walletPasses").doc(serialNumber).get())
    .data()?.authenticationToken as string | undefined;
  return buildCardPass({
    cardID,
    assetKey: CARD_ASSET[cardID],
    handle,
    displayName,
    serialNumber,
    passTypeIdentifier: passTypeIdentifier.value(),
    teamIdentifier: passTeamIdentifier.value(),
    authenticationToken: token,
    webServiceURL: passWebServiceURL.value() || undefined,
    certificates: {
      wwdr: passWWDRCert.value(),
      signerCert: passSignerCert.value(),
      signerKey: passSignerKey.value(),
      signerKeyPassphrase: passSignerKeyPassphrase.value() || undefined,
    },
  });
}

export const poplurPassWebService = onRequest(
  { secrets: PASS_SECRETS, memory: "512MiB", timeoutSeconds: 60, cors: false },
  async (request: Request, response: Response) => {
    // Firebase strips the function name, so paths arrive as /v1/... regardless
    // of whether this is hosted at the function URL or behind a rewrite.
    const path = request.path.replace(/^\/+/, "");
    const segments = path.split("/").filter(Boolean);

    try {
      // POST /v1/log — Wallet's own diagnostics. Always 200; a failure here
      // must never look like a pass problem.
      if (segments[0] === "v1" && segments[1] === "log") {
        logger.info("Wallet pass log", { logs: request.body?.logs });
        response.status(200).send("");
        return;
      }

      // /v1/devices/{deviceLibraryIdentifier}/registrations/{passTypeId}[/{serial}]
      if (segments[0] === "v1" && segments[1] === "devices" && segments[3] === "registrations") {
        const deviceLibraryIdentifier = segments[2];
        const serialNumber = segments[5];

        // GET without a serial: which of this device's passes changed since TAG.
        if (request.method === "GET" && !serialNumber) {
          const since = typeof request.query.passesUpdatedSince === "string"
            ? Number(request.query.passesUpdatedSince)
            : 0;
          const registrations = await admin.firestore()
            .collection("walletPassRegistrations")
            .where("deviceLibraryIdentifier", "==", deviceLibraryIdentifier)
            .get();
          const serials: string[] = [];
          let lastUpdated = since;
          for (const doc of registrations.docs) {
            const serial = doc.data().serialNumber as string;
            const passDoc = await admin.firestore().collection("walletPasses").doc(serial).get();
            const updatedAt = passDoc.data()?.contentUpdatedAt?.toMillis?.() ?? 0;
            if (updatedAt > since) {
              serials.push(serial);
              lastUpdated = Math.max(lastUpdated, updatedAt);
            }
          }
          if (serials.length === 0) {
            response.status(204).send("");
            return;
          }
          response.status(200).json({ lastUpdated: String(lastUpdated), serialNumbers: serials });
          return;
        }

        if (!serialNumber || !parseSerial(serialNumber)) {
          response.status(404).send("");
          return;
        }
        if (!(await authorizedFor(request, serialNumber))) {
          response.status(401).send("");
          return;
        }
        const registrationID = `${deviceLibraryIdentifier}.${serialNumber}`;
        const registrationRef = admin.firestore()
          .collection("walletPassRegistrations").doc(registrationID);

        if (request.method === "POST") {
          const pushToken = request.body?.pushToken;
          if (typeof pushToken !== "string" || !pushToken) {
            response.status(400).send("");
            return;
          }
          const existing = await registrationRef.get();
          await registrationRef.set({
            deviceLibraryIdentifier,
            serialNumber,
            pushToken,
            updatedAt: FieldValue.serverTimestamp(),
          });
          // 201 the first time, 200 on a repeat — Wallet uses the difference.
          response.status(existing.exists ? 200 : 201).send("");
          return;
        }

        if (request.method === "DELETE") {
          await registrationRef.delete();
          response.status(200).send("");
          return;
        }

        response.status(405).send("");
        return;
      }

      // GET /v1/passes/{passTypeIdentifier}/{serialNumber} — hand back the
      // latest pass. This is what the device calls after a push.
      if (segments[0] === "v1" && segments[1] === "passes" && segments.length >= 4) {
        const serialNumber = segments[3];
        const parsed = parseSerial(serialNumber);
        if (!parsed) {
          response.status(404).send("");
          return;
        }
        if (!(await authorizedFor(request, serialNumber))) {
          response.status(401).send("");
          return;
        }
        if (!certificatesConfigured()) {
          logger.error("Pass update requested before signing was configured");
          response.status(500).send("");
          return;
        }
        // Ownership is re-checked on every re-issue, not just at the first add:
        // a refunded or revoked card should stop updating rather than keep
        // living in a wallet forever.
        if (!(await ownsCard(parsed.uid, parsed.cardID))) {
          response.status(401).send("");
          return;
        }

        const passDoc = await admin.firestore()
          .collection("walletPasses").doc(serialNumber).get();
        const updatedAt: number = passDoc.data()?.contentUpdatedAt?.toMillis?.() ?? 0;
        const ifModifiedSince = Date.parse(request.get("if-modified-since") ?? "");
        // Second granularity: the header carries whole seconds, so comparing
        // against millisecond precision would re-send the pass every time.
        if (
          Number.isFinite(ifModifiedSince)
          && updatedAt > 0
          && Math.floor(updatedAt / 1000) <= Math.floor(ifModifiedSince / 1000)
        ) {
          response.status(304).send("");
          return;
        }

        const pkpass = await currentPass(parsed.uid, parsed.cardID, serialNumber);
        response.status(200);
        response.set("Content-Type", "application/vnd.apple.pkpass");
        response.set("Last-Modified", new Date(updatedAt || Date.now()).toUTCString());
        response.send(pkpass);
        return;
      }

      response.status(404).send("");
    } catch (error) {
      logger.error("Wallet pass web service failed", { error: String(error), path });
      response.status(500).send("");
    }
  }
);

/**
 * The nudge. An empty APNs payload on the pass topic tells every registered
 * device to come back and re-fetch; Wallet then shows the new content.
 *
 * Authenticated with the SAME Pass Type ID certificate that signs the pass —
 * APNs uses it as a client TLS certificate, which is why no separate push key
 * is needed and why this cannot work until the certificate exists.
 */
async function pushPassUpdate(pushTokens: string[]): Promise<void> {
  if (pushTokens.length === 0) return;
  if (!certificatesConfigured()) {
    logger.warn("Skipping pass push — signing certificate is not configured");
    return;
  }

  const client = connect("https://api.push.apple.com", {
    cert: passSignerCert.value(),
    key: passSignerKey.value(),
    passphrase: passSignerKeyPassphrase.value() || undefined,
  });

  try {
    await Promise.all(
      pushTokens.map(
        token =>
          new Promise<void>(resolve => {
            const stream = client.request({
              ":method": "POST",
              ":path": `/3/device/${token}`,
              "apns-topic": passTypeIdentifier.value(),
              "apns-push-type": "background",
              "content-type": "application/json",
            });
            stream.setEncoding("utf8");
            let body = "";
            stream.on("data", chunk => { body += chunk; });
            stream.on("response", headers => {
              const status = headers[":status"];
              if (status !== 200) {
                // A 410 means the device dropped the pass. Logged rather than
                // thrown: one dead token must not stop the rest of the fan-out.
                logger.warn("APNs rejected a pass push", { status, body });
              }
            });
            stream.on("error", error => {
              logger.warn("APNs push failed", { error: String(error) });
              resolve();
            });
            stream.on("end", () => resolve());
            // Wallet ignores the payload entirely; it is the wake-up that counts.
            stream.end("{}");
          })
      )
    );
  } finally {
    client.close();
  }
}

/**
 * What actually changes on a Poplur pass: the holder's name and handle.
 *
 * Deliberately NOT the radius. Radius decays continuously, so pushing on it
 * would wake every device in the fleet constantly to redraw a number that had
 * already moved again — the pass carries identity, which changes rarely and
 * visibly, and that is what is worth a push.
 */
export const poplurPassOnProfileChange = onDocumentUpdated(
  { document: "users/{uid}", secrets: PASS_SECRETS },
  async event => {
    const before = event.data?.before.data() ?? {};
    const after = event.data?.after.data() ?? {};
    const identityChanged =
      before.username !== after.username
      || before.handle !== after.handle
      || before.displayName !== after.displayName;
    if (!identityChanged) return;

    const uid = event.params.uid;
    const db = admin.firestore();
    const passes = await db.collection("walletPasses").where("userId", "==", uid).get();
    if (passes.empty) return;

    const stamped = FieldValue.serverTimestamp();
    const tokens: string[] = [];
    for (const passDoc of passes.docs) {
      await passDoc.ref.set({ contentUpdatedAt: stamped }, { merge: true });
      const registrations = await db.collection("walletPassRegistrations")
        .where("serialNumber", "==", passDoc.id)
        .get();
      for (const registration of registrations.docs) {
        const token = registration.data().pushToken;
        if (typeof token === "string" && token) tokens.push(token);
      }
    }

    logger.info("Pushing wallet pass update", { uid, passes: passes.size, devices: tokens.length });
    await pushPassUpdate([...new Set(tokens)]);
  }
);
