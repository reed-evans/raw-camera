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

// Phase-0 passthrough fullscreen-triangle shaders so T0-2 compiles green.
// The metal worker replaces the fragment stage with the real preview + zebra +
// focus-peaking sampling driven by `uniforms`.
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

fragment float4 preview_fragment(VertexOut in [[stage_in]],
                                 constant PreviewUniforms &uniforms [[buffer(0)]],
                                 texture2d<float> frame [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = frame.sample(s, in.uv);
    return color;
}
