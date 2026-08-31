const assert = require("node:assert/strict");
const {
  boundedInlineGeneratedImage,
  buildGoogleInteractionRequest,
  buildVertexImageRequest,
  shouldUseVertexImageFallback,
  supportsVertexImageFallback,
} = require("../lib/vertexImageFallback");

for (const status of [429, 500, 502, 503, 504]) {
  assert.equal(shouldUseVertexImageFallback(status), true, `status ${status} should fall back`);
}
for (const status of [400, 401, 403, 404, 409, 422]) {
  assert.equal(shouldUseVertexImageFallback(status), false, `status ${status} should not fall back`);
}
assert.equal(supportsVertexImageFallback("image"), true);
assert.equal(supportsVertexImageFallback("edit"), true);
assert.equal(supportsVertexImageFallback("video"), false);
assert.equal(supportsVertexImageFallback("voice"), false);

const request = buildVertexImageRequest("Make this cinematic", {
  data: "c291cmNlLWltYWdl",
  mimeType: "image/jpeg",
});
assert.deepEqual(request, {
  contents: [{
    role: "user",
    parts: [
      { text: "Make this cinematic" },
      { inlineData: { mimeType: "image/jpeg", data: "c291cmNlLWltYWdl" } },
    ],
  }],
  generationConfig: { responseModalities: ["TEXT", "IMAGE"] },
});
assert.equal(Object.hasOwn(request, "metadata"), false);

const interactionRequest = buildGoogleInteractionRequest({
  model: "gemini-2.5-flash-image",
  contentType: "edit",
  prompt: "Make this cinematic",
  sourceImage: { data: "c291cmNlLWltYWdl", mimeType: "image/jpeg" },
});
assert.deepEqual(interactionRequest, {
  model: "gemini-2.5-flash-image",
  input: [
    { type: "text", text: "Make this cinematic" },
    { type: "image", mime_type: "image/jpeg", data: "c291cmNlLWltYWdl" },
  ],
  response_format: { type: "image", mime_type: "image/jpeg" },
});
assert.equal(Object.hasOwn(interactionRequest, "metadata"), false);
assert.equal(Object.hasOwn(interactionRequest, "generation_config"), false);

assert.deepEqual(
  boundedInlineGeneratedImage({ bytes: Buffer.from("generated"), mimeType: "image/png" }),
  { data: "Z2VuZXJhdGVk", mimeType: "image/png" }
);
assert.throws(
  () => boundedInlineGeneratedImage({ bytes: Buffer.from("generated"), mimeType: "image/gif" }),
  /unsupported generated image type/
);
assert.throws(
  () => boundedInlineGeneratedImage({ bytes: Buffer.alloc(8 * 1024 * 1024 + 1), mimeType: "image/png" }),
  /exceeds the 8 MiB response limit/
);

console.log("Vertex image fallback policy, payload, and inline response bounds passed.");
