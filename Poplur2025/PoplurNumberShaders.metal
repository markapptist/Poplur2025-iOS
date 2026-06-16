#include <metal_stdlib>
using namespace metal;

// Adaptive Poplur glow — detects the hue of each text pixel and selects
// the best complementary glow palette automatically.
// Red labels → warm amber-red glow
// Green labels → lime-yellow glow
// Blue labels → electric cyan-purple glow
// White / neutral labels → cool white-blue electric glow
[[ stitchable ]] half4 poplurNumberGlow(float2 position, half4 color, float time, float intensity) {
    if (color.a <= 0.01h) return color;

    // ── Animated time components ──────────────────────────────────────────────
    float shimmer = sin(position.x * 0.08 + position.y * 0.035 + time * 3.4) * 0.5 + 0.5;
    float scan    = sin(position.y * 1.65  + time * 8.0)                      * 0.5 + 0.5;
    float pulse   = sin(time * 2.2)                                            * 0.5 + 0.5;

    // ── Hue detection (RGB → normalised hue 0..1) ────────────────────────────
    float r = float(color.r), g = float(color.g), b = float(color.b);
    float cmax  = max(r, max(g, b));
    float cmin  = min(r, min(g, b));
    float delta = cmax - cmin;

    float hue = 0.0;
    if (delta > 0.001) {
        if      (cmax == r) hue = fmod((g - b) / delta + 6.0, 6.0);
        else if (cmax == g) hue = 2.0 + (b - r) / delta;
        else                hue = 4.0 + (r - g) / delta;
        hue /= 6.0;
    }

    float lum = dot(float3(r, g, b), float3(0.2126, 0.7152, 0.0722));

    // ── Per-hue masks ─────────────────────────────────────────────────────────
    float isRed     = clamp((1.0 - smoothstep(0.0, 0.10, hue)) + smoothstep(0.90, 1.0, hue), 0.0, 1.0);
    float isGreen   = smoothstep(0.25, 0.38, hue) * (1.0 - smoothstep(0.38, 0.50, hue));
    float isBlue    = smoothstep(0.55, 0.65, hue) * (1.0 - smoothstep(0.65, 0.78, hue));
    float isNeutral = smoothstep(0.72, 0.90, lum) * (1.0 - isRed) * (1.0 - isGreen) * (1.0 - isBlue);
    float isOther   = clamp(1.0 - isRed - isGreen - isBlue - isNeutral, 0.0, 1.0);

    // ── Adaptive glow palettes ────────────────────────────────────────────────
    float3 glowA = isRed     * float3(1.00, 0.42, 0.06)   // amber-orange  (primary)
                 + isGreen   * float3(0.65, 1.00, 0.10)    // lime-yellow
                 + isBlue    * float3(0.40, 0.12, 1.00)    // violet
                 + isNeutral * float3(0.82, 0.88, 1.00)    // cool white
                 + isOther   * float3(1.00, 0.62, 0.18);   // default amber

    float3 glowB = isRed     * float3(1.00, 0.10, 0.28)   // hot-red       (shimmer accent)
                 + isGreen   * float3(0.18, 1.00, 0.55)    // electric green
                 + isBlue    * float3(0.12, 0.72, 1.00)    // electric cyan
                 + isNeutral * float3(0.18, 0.75, 1.00)    // electric blue
                 + isOther   * float3(0.18, 0.82, 1.00);   // default cyan

    // ── Apply glow ────────────────────────────────────────────────────────────
    float3 hot     = mix(glowA, glowB, shimmer * 0.55);
    float  heat    = (0.22 + shimmer * 0.38 + scan * 0.10 + pulse * 0.10) * intensity;
    float3 base    = float3(r, g, b);
    float3 boosted = mix(base, max(base, hot * max(lum, 0.42)), heat);
    boosted       += scan * 0.055 * intensity;

    return half4(half3(boosted), color.a);
}
