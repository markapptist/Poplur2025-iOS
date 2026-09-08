#!/usr/bin/env node
// Copy the reviewed renders to the native libraries, without touching Good Copy.
// Usage: node scripts/install-native-prelogin-thumbnails.mjs RENDERS_DIR IOS_REPO ANDROID_REPO
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
const [renders, ios, android] = process.argv.slice(2);
if (!renders || !ios || !android) throw new Error('Expected RENDERS_DIR IOS_REPO ANDROID_REPO');
const models = JSON.parse(await fs.readFile(path.join(renders, 'models.json'), 'utf8'));
const evidence = [];
for (const {name, sourceSHA256} of models) {
  const png = await fs.readFile(path.join(renders, `${name}.png`));
  if (!png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error(`Not a PNG: ${name}`);
  const imageset = path.join(ios, 'Poplur2025/Assets.xcassets', `NativePrelogin-${name}.imageset`);
  const androidDirectory = path.join(android, 'app/src/main/assets/native-prelogin');
  await fs.mkdir(imageset, {recursive: true});
  await fs.mkdir(androidDirectory, {recursive: true});
  await fs.writeFile(path.join(imageset, `${name}.png`), png);
  await fs.writeFile(path.join(imageset, 'Contents.json'), JSON.stringify({images: [{idiom: 'universal', filename: `${name}.png`}], info: {author: 'xcode', version: 1}}, null, 2) + '\n');
  await fs.writeFile(path.join(androidDirectory, `${name}.png`), png);
  evidence.push({name, sourceSHA256, renderedSHA256: createHash('sha256').update(png).digest('hex'), width: png.readUInt32BE(16), height: png.readUInt32BE(20)});
}
await fs.writeFile(path.join(renders, 'native-thumbnail-provenance.json'), JSON.stringify(evidence, null, 2) + '\n');
console.log(`Installed ${models.length} original-model thumbnails in both native libraries.`);
