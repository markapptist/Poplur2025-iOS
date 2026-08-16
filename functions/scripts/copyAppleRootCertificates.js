const { copyFileSync, mkdirSync, rmSync } = require("node:fs");
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
