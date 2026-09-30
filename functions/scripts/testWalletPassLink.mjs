/**
 * The link on a Wallet pass (lib/walletPass.js): the QR and the "Website" line
 * on the back must open the live poplur.ca landing page with the holder's
 * handle as ?u= — never poplur.com, which has no DNS — and the back's text
 * must say that is where the code goes.
 *
 *   npm run build && node scripts/testWalletPassLink.mjs
 *
 * Signs a real .pkpass with a throwaway self-signed certificate and reads
 * pass.json back out of it, so no secrets, Firestore or network are involved.
 */
import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const forge = require("node-forge");
const { buildCardPass, passProfileURL } = require("../lib/walletPass.js");

let passed = 0;
async function check(name, body) {
  await body();
  passed += 1;
  console.log(`ok - ${name}`);
}

function throwawayCertificate() {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  });
  const key = forge.pki.privateKeyFromPem(privateKey);
  const cert = forge.pki.createCertificate();
  cert.publicKey = forge.pki.publicKeyFromPem(publicKey);
  cert.serialNumber = "01";
  cert.validity.notBefore = new Date(Date.now() - 60_000);
  cert.validity.notAfter = new Date(Date.now() + 60 * 60_000);
  const name = [{ name: "commonName", value: "Poplur pass link test" }];
  cert.setSubject(name);
  cert.setIssuer(name);
  cert.sign(key, forge.md.sha256.create());
  return { cert: forge.pki.certificateToPem(cert), key: forge.pki.privateKeyToPem(key) };
}

function passJSON(pkpass) {
  const dir = mkdtempSync(join(tmpdir(), "poplur-pass-"));
  try {
    const file = join(dir, "card.pkpass");
    writeFileSync(file, pkpass);
    return JSON.parse(execFileSync("unzip", ["-p", file, "pass.json"], { encoding: "utf8" }));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

await check("the link is the poplur.ca landing page with the handle as ?u=", async () => {
  assert.equal(passProfileURL("@mark"), "https://www.poplur.ca/?u=mark");
  assert.equal(passProfileURL("mark"), "https://www.poplur.ca/?u=mark");
});

await check("the handle is escaped the way the shells escape a pop id", async () => {
  assert.equal(passProfileURL("@a b&c#d"), `https://www.poplur.ca/?u=${encodeURIComponent("a b&c#d")}`);
  // The QR is encoded as iso-8859-1, so the message must stay plain ASCII.
  assert.equal(passProfileURL("@café"), "https://www.poplur.ca/?u=caf%C3%A9");
});

await check("a signed pass carries that link in its QR and on its back", async () => {
  const { cert, key } = throwawayCertificate();
  const pkpass = await buildCardPass({
    cardID: "lens",
    assetKey: "lens",
    handle: "@mark",
    displayName: "Mark",
    serialNumber: "test-uid.lens",
    passTypeIdentifier: "pass.com.apptist.Poplur2025.card",
    teamIdentifier: "VDQS4882Z8",
    certificates: { wwdr: cert, signerCert: cert, signerKey: key },
  });
  const pass = passJSON(pkpass);
  const expected = "https://www.poplur.ca/?u=mark";

  assert.ok(pass.barcodes.length > 0, "the pass has no barcode");
  for (const barcode of pass.barcodes) {
    assert.equal(barcode.message, expected);
    assert.equal(barcode.format, "PKBarcodeFormatQR");
  }
  const profile = pass.generic.backFields.find(field => field.key === "profile");
  assert.equal(profile?.value, expected);
  assert.equal(profile?.label, "Website");
  // The words on the back describe where the code goes, not a profile page the site does not have.
  const about = pass.generic.backFields.find(field => field.key === "about");
  assert.match(about?.value ?? "", /Scanning the code opens poplur\.ca/);
  assert.ok(!JSON.stringify(pass).includes("poplur.com"), "the pass still names poplur.com");
});

console.log(`${passed} wallet pass link checks passed`);
