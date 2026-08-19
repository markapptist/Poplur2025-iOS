const { copyFileSync, mkdirSync, readdirSync, rmSync } = require("node:fs");
const { join } = require("node:path");

const source = join(__dirname, "..", "src", "apple-root-certificates");
const destination = join(__dirname, "..", "lib", "apple-root-certificates");
const certificates = [
  "AppleIncRootCertificate.cer",
  "AppleRootCA-G2.cer",
  "AppleRootCA-G3.cer",
];

mkdirSync(destination, { recursive: true });
for (const certificate of certificates) {
  copyFileSync(join(source, certificate), join(destination, certificate));
}

// `cp -R source existing-destination` created this nested generated directory
// on every build after the first. Remove only that known generated duplicate.
rmSync(join(destination, "apple-root-certificates"), { recursive: true, force: true });

// Wallet pass artwork rides along the same way: tsc emits only JS, so the pass
// images have to be copied into lib/ or the deployed function reads an empty
// directory and every pass request fails at addBuffer.
const passAssetSource = join(__dirname, "..", "src", "pass-assets");
const passAssetDestination = join(__dirname, "..", "lib", "pass-assets");
mkdirSync(passAssetDestination, { recursive: true });
for (const asset of readdirSync(passAssetSource)) {
  if (!asset.endsWith(".png")) continue;
  copyFileSync(join(passAssetSource, asset), join(passAssetDestination, asset));
}
