#!/usr/bin/env node
// Prepare the original models for offline thumbnail rendering. The web assets
// stay unchanged; no geometric simplification or texture resizing is applied.
// Usage: node scripts/prepare-native-prelogin-models.mjs TOOLS_DIR ANDROID_ASSETS OUTPUT_DIR
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
const [tools, assets, output] = process.argv.slice(2);
if (!tools || !assets || !output) throw new Error('Expected TOOLS_DIR ANDROID_ASSETS OUTPUT_DIR');
const require = createRequire(path.resolve(tools, 'package.json'));
const {NodeIO} = require('@gltf-transform/core');
const {ALL_EXTENSIONS} = require('@gltf-transform/extensions');
const draco = require('draco3dgltf');
const sharp = require('sharp');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({'draco3d.decoder': await draco.createDecoderModule()});
await fs.mkdir(output, {recursive: true});
const models = [
  ['MarkHead_TalkingRig', 'Poplur2025-iOS/Poplur2025/MarkHead_TalkingRig.glb'],
  ['zoom_buildings', 'signup/zoom_buildings.glb'],
  ['poplur_mark_head_navigator', 'claymap/poplur_mark_head_navigator.glb'],
  ['poplur_female_head_navigator', 'claymap/poplur_female_head_navigator.glb'],
];
const manifest = [];
for (const [name, relative] of models) {
  const source = path.resolve(assets, relative);
  const document = await io.read(source);
  for (const texture of document.getRoot().listTextures()) {
    if (texture.getMimeType() === 'image/webp') {
      const original = texture.getImage();
      const png = await sharp(original).png({compressionLevel: 6}).toBuffer();
      const before = await sharp(original).ensureAlpha().raw().toBuffer();
      const after = await sharp(png).ensureAlpha().raw().toBuffer();
      if (!before.equals(after)) throw new Error(`Texture pixels changed: ${name}`);
      texture.setImage(png).setMimeType('image/png');
      texture.setURI('');
    }
  }
  // Decoding happens during read. Removing these extensions writes ordinary
  // geometry/PNG textures suitable for native importers and offline renderers.
  for (const extension of document.getRoot().listExtensionsUsed()) {
    if (['KHR_draco_mesh_compression', 'EXT_texture_webp'].includes(extension.extensionName)) extension.dispose();
  }
  for (const animation of document.getRoot().listAnimations()) animation.dispose();
  const prepared = path.resolve(output, `${name}.glb`);
  await io.write(prepared, document);
  const buffer = await fs.readFile(prepared);
  const json = JSON.parse(buffer.subarray(20, 20 + buffer.readUInt32LE(12)).toString());
  if ((json.extensionsUsed || []).some(x => ['KHR_draco_mesh_compression', 'EXT_texture_webp'].includes(x))) throw new Error(`Unsupported extension remains: ${name}`);
  manifest.push({name, source, sourceSHA256: createHash('sha256').update(await fs.readFile(source)).digest('hex'), prepared, rotationY: name === 'zoom_buildings' ? -0.55 : 0.2});
  console.log(`${name}: ${buffer.length} bytes; native geometry and textures prepared`);
}
await fs.writeFile(path.resolve(output, 'models.json'), JSON.stringify(manifest, null, 2) + '\n');
