#include <metal_stdlib>
using namespace metal;

// OWNER: wt/metal.
//
// **FROZEN ABI — must stay byte-identical to `CameraCore.PreviewUniforms`.**
// Grader T1-7 verifies the Swift side; reviewer verifies this side matches.
// stride = 48, alignment = 16. Do not reorder, retype, or drop the padding.
struct PreviewUniforms {
    float4 peakingColor;    // offset 0
    float2 viewSize;        // offset 16
    float  zebraThreshold;  // offset 24
    float  peakingThreshold;// offset 28
    float  rotation;        // offset 32
    uint   zebraEnabled;    // offset 36
    uint   peakingEnabled;  // offset 40
    uint   _pad;            // offset 44 -> stride 48
};

// Compile-time half of grader T1-7: locks the Metal side of the ABI so drift is
// caught at T0-2 (shader compile), not just by the Swift MemoryLayout test.
static_assert(sizeof(PreviewUniforms) == 48, "PreviewUniforms ABI drift: stride must be 48 (see CONTRACTS.md §4)");
static_assert(alignof(PreviewUniforms) == 16, "PreviewUniforms ABI drift: alignment must be 16 (see CONTRACTS.md §4)");

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// Rec. 709 luma — matches the luma channel computed by the histogram kernel.
inline float luma709(float3 rgb) {
    return dot(rgb, float3(0.2126, 0.7152, 0.0722));
}

// Full-screen triangle. `rotation` (radians) is applied to clip-space position
// so the preview matches device orientation; UVs are left unrotated so texture
// sampling stays aligned to the camera texture.
vertex VertexOut preview_vertex(uint vid [[vertex_id]],
                                constant PreviewUniforms &uniforms [[buffer(0)]]) {
    float2 positions[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
    float2 uvs[3]       = { float2(0.0, 2.0),  float2(0.0, 0.0), float2(2.0, 0.0) };
    VertexOut out;
    float c = cos(uniforms.rotation);
    float s = sin(uniforms.rotation);
    float2 p = positions[vid];
    out.position = float4(float2(p.x * c - p.y * s, p.x * s + p.y * c), 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

// Preview fragment with two monitoring overlays driven by `uniforms`:
//   (a) zebra — diagonal stripes where luma >= zebraThreshold (zebraEnabled).
//   (b) focus peaking — peakingColor over high-gradient edges where local edge
//       energy >= peakingThreshold (peakingEnabled).
fragment float4 preview_fragment(VertexOut in [[stage_in]],
                                 constant PreviewUniforms &uniforms [[buffer(0)]],
                                 texture2d<float> frame [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = frame.sample(s, in.uv);

    // --- (b) Focus peaking: Sobel-style edge energy on luma. ---
    if (uniforms.peakingEnabled != 0u) {
        // One-texel step in UV space (guard against a zero viewSize).
        float2 px = max(uniforms.viewSize, float2(1.0, 1.0));
        float2 texel = 1.0 / px;

        float lTL = luma709(frame.sample(s, in.uv + texel * float2(-1.0, -1.0)).rgb);
        float lT  = luma709(frame.sample(s, in.uv + texel * float2( 0.0, -1.0)).rgb);
        float lTR = luma709(frame.sample(s, in.uv + texel * float2( 1.0, -1.0)).rgb);
        float lL  = luma709(frame.sample(s, in.uv + texel * float2(-1.0,  0.0)).rgb);
        float lR  = luma709(frame.sample(s, in.uv + texel * float2( 1.0,  0.0)).rgb);
        float lBL = luma709(frame.sample(s, in.uv + texel * float2(-1.0,  1.0)).rgb);
        float lB  = luma709(frame.sample(s, in.uv + texel * float2( 0.0,  1.0)).rgb);
        float lBR = luma709(frame.sample(s, in.uv + texel * float2( 1.0,  1.0)).rgb);

        float gx = (lTR + 2.0 * lR + lBR) - (lTL + 2.0 * lL + lBL);
        float gy = (lBL + 2.0 * lB + lBR) - (lTL + 2.0 * lT + lTR);
        float edge = length(float2(gx, gy));

        if (edge >= uniforms.peakingThreshold) {
            float a = clamp(uniforms.peakingColor.a, 0.0, 1.0);
            color.rgb = mix(color.rgb, uniforms.peakingColor.rgb, a);
        }
    }

    // --- (a) Zebra: diagonal stripes over blown highlights. ---
    if (uniforms.zebraEnabled != 0u) {
        float y = luma709(color.rgb);
        if (y >= uniforms.zebraThreshold) {
            // Diagonal stripe in drawable-pixel space; period ~10px.
            float2 fragPx = in.position.xy;
            float stripe = fract((fragPx.x + fragPx.y) / 10.0);
            if (stripe < 0.5) {
                color.rgb = float3(0.0);  // dark bar of the zebra pattern
            }
        }
    }

    return color;
}

// ----------------------------------------------------------------------------
// Histogram compute kernel.
//
// Accumulates per-channel + luma bin counts (256 bins each) into a single
// `uint` buffer laid out as 4 contiguous 256-entry sections:
//   [0..255]   red, [256..511] green, [512..767] blue, [768..1023] luma.
// The CPU clears the buffer each frame, dispatches over the texture, reads the
// raw counts back, and feeds them to `CameraCore.Histogram.normalize`.
// Uses atomics so concurrent threads accumulate correctly.
// ----------------------------------------------------------------------------
constant uint kHistogramBins = 256u;

kernel void histogram_accumulate(texture2d<float> frame [[texture(0)]],
                                 device atomic_uint *bins [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]],
                                 uint2 gridSize [[threads_per_grid]]) {
    if (gid.x >= gridSize.x || gid.y >= gridSize.y) {
        return;
    }
    // Map the bounded sampling grid onto the full-resolution frame, so histogram
    // cost is fixed regardless of capture resolution (see encodeHistogram). At
    // most a few hundred-thousand reads/atomics per frame instead of ~12M.
    uint tw = frame.get_width();
    uint th = frame.get_height();
    if (tw == 0u || th == 0u) {
        return;
    }
    uint sx = min(tw - 1u, uint((float(gid.x) + 0.5) / float(gridSize.x) * float(tw)));
    uint sy = min(th - 1u, uint((float(gid.y) + 0.5) / float(gridSize.y) * float(th)));
    float4 c = frame.read(uint2(sx, sy));

    uint r = uint(clamp(c.r, 0.0, 1.0) * 255.0 + 0.5);
    uint g = uint(clamp(c.g, 0.0, 1.0) * 255.0 + 0.5);
    uint b = uint(clamp(c.b, 0.0, 1.0) * 255.0 + 0.5);
    uint y = uint(clamp(luma709(c.rgb), 0.0, 1.0) * 255.0 + 0.5);

    atomic_fetch_add_explicit(&bins[r], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[kHistogramBins + g], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[2u * kHistogramBins + b], 1u, memory_order_relaxed);
    atomic_fetch_add_explicit(&bins[3u * kHistogramBins + y], 1u, memory_order_relaxed);
}
