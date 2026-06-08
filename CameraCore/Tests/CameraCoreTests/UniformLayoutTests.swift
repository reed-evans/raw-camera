import Testing
import simd

@testable import CameraCore

/// Grader **T1-7** — Uniform ABI parity.
///
/// Guards `PreviewUniforms` against silent drift from the matching Metal struct
/// in `CameraShaders.metal`. If any of these fail, the Swift and Metal sides
/// disagree and the preview will read garbage uniforms on device.
@Suite("T1-7 PreviewUniforms ABI parity")
struct UniformLayoutTests {
    @Test("stride is frozen at 48 bytes")
    func stride() {
        #expect(MemoryLayout<PreviewUniforms>.stride == 48)
        #expect(MemoryLayout<PreviewUniforms>.stride == PreviewUniforms.Layout.stride)
    }

    @Test("alignment is frozen at 16 bytes")
    func alignment() {
        #expect(MemoryLayout<PreviewUniforms>.alignment == 16)
        #expect(MemoryLayout<PreviewUniforms>.alignment == PreviewUniforms.Layout.alignment)
    }

    @Test("field offsets match the frozen Metal layout")
    func offsets() {
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingColor) == PreviewUniforms.Layout.peakingColorOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.viewSize) == PreviewUniforms.Layout.viewSizeOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.zebraThreshold) == PreviewUniforms.Layout.zebraThresholdOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingThreshold) == PreviewUniforms.Layout.peakingThresholdOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.rotation) == PreviewUniforms.Layout.rotationOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.zebraEnabled) == PreviewUniforms.Layout.zebraEnabledOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingEnabled) == PreviewUniforms.Layout.peakingEnabledOffset)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \._pad) == PreviewUniforms.Layout.padOffset)
    }

    @Test("explicit literal offsets (defense against Layout constant edits)")
    func literalOffsets() {
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingColor) == 0)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.viewSize) == 16)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.zebraThreshold) == 24)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingThreshold) == 28)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.rotation) == 32)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.zebraEnabled) == 36)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \.peakingEnabled) == 40)
        #expect(MemoryLayout<PreviewUniforms>.offset(of: \._pad) == 44)
    }
}
