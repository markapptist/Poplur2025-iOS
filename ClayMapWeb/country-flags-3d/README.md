# World Country Flags — Pole-Free GLB Pack

This pack contains **195 core sovereign-state flags** and **5 optional recognition/association extras**, for **200 individual GLB files** total.

## Model specification

- One flag per `.glb`; no pole, base, camera, light, or animation
- Lightly rippled static cloth mesh
- Rectangular flags use a consistent 4:3 display shape: 1.3333 m wide × 1.0000 m high
- Nepal uses actual non-rectangular silhouette geometry and preserves its native visual proportion
- Centered pivot/origin; +X right, +Y up, +Z depth
- Embedded PNG texture; no external image dependencies
- Double-sided, unlit material for predictable app rendering
- Standard rectangular model: 273 vertices / 480 triangles
- GLB 2.0; dimensions are expressed in meters

## Folders

- `flags/`: 195 core flags (193 UN members + Holy See + Palestine)
- `extras/`: Taiwan, Kosovo, Western Sahara, Cook Islands, and Niue
- `manifest.json` and `manifest.csv`: filenames, codes, names, geometry counts, sizes, and model metadata
- `previews/`: contact sheet and sample 3D renders
- `licenses/`: texture-art attribution

## Design conventions

The pack standardizes rectangular models to 4:3 for consistent placement in a mobile 3D interface. This means the mesh display ratio is not the official legal ratio of every national flag. Artwork is mapped cleanly across that common surface.

The Syria and Kyrgyzstan textures are redrawn to reflect newer national designs not present in the bundled emoji font. Afghanistan uses the familiar black-red-green tricolour convention used by common international flag/emoji datasets; applications requiring a de-facto-government variant should substitute their chosen texture.

## Usage

Use the ISO alpha-2 code at the start of every filename for lookup, for example:

- `CA_Canada.glb`
- `JP_Japan.glb`
- `ZA_South_Africa.glb`

The models are suitable for mobile/web viewers, SceneKit/RealityKit, Unity, Godot, Three.js, Babylon.js, and other GLB-compatible runtimes.
