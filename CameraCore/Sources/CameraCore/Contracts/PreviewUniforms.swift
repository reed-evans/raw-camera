import simd

/// **FROZEN ABI — orchestrator-mediated only.**
///
/// Shared byte-for-byte with the `PreviewUniforms` struct in
/// `App/Monitoring/CameraShaders.metal`. Grader **T1-7** asserts this layout.
/// Field order, types, and padding are frozen in Phase 0. Any change is a
/// contract amendment and must update both sides + CONTRACTS.md simultaneously.
///
/// Layout (stride = 48, alignment = 16):
///
/// | field            | type         | offset | size |
/// | ---------------- | ------------ | ------ | ---- |
/// | peakingColor     | SIMD4<Float> | 0      | 16   |
/// | viewSize         | SIMD2<Float> | 16     | 8    |
/// | zebraThreshold   | Float        | 24     | 4    |
/// | peakingThreshold | Float        | 28     | 4    |
/// | rotation         | Float        | 32     | 4    |
/// | zebraEnabled     | UInt32       | 36     | 4    |
/// | peakingEnabled   | UInt32       | 40     | 4    |
/// | _pad             | UInt32       | 44     | 4    |
///
/// Matching Metal declaration:
/// ```metal
/// struct PreviewUniforms {
///     float4 peakingColor;
///     float2 viewSize;
///     float  zebraThreshold;
///     float  peakingThreshold;
///     float  rotation;
///     uint   zebraEnabled;
///     uint   peakingEnabled;
///     uint   _pad;
/// };
/// ```
public struct PreviewUniforms: Equatable, Sendable {
    /// RGBA color drawn over in-focus edges by the focus-peaking pass.
    public var peakingColor: SIMD4<Float>
    /// Drawable size in pixels (width, height).
    public var viewSize: SIMD2<Float>
    /// Luma threshold in `0...1`; pixels at/above get zebra striping.
    public var zebraThreshold: Float
    /// Edge-energy threshold in `0...1` for focus peaking.
    public var peakingThreshold: Float
    /// Preview rotation in radians applied in the vertex stage.
    public var rotation: Float
    /// `0`/`1` toggle for the zebra pass.
    public var zebraEnabled: UInt32
    /// `0`/`1` toggle for the focus-peaking pass.
    public var peakingEnabled: UInt32
    /// Explicit tail padding to lock stride at 48 across Swift/Metal.
    public var _pad: UInt32

    public init(
        peakingColor: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 1),
        viewSize: SIMD2<Float> = SIMD2<Float>(0, 0),
        zebraThreshold: Float = 0.95,
        peakingThreshold: Float = 0.15,
        rotation: Float = 0,
        zebraEnabled: UInt32 = 0,
        peakingEnabled: UInt32 = 0,
        _pad: UInt32 = 0
    ) {
        self.peakingColor = peakingColor
        self.viewSize = viewSize
        self.zebraThreshold = zebraThreshold
        self.peakingThreshold = peakingThreshold
        self.rotation = rotation
        self.zebraEnabled = zebraEnabled
        self.peakingEnabled = peakingEnabled
        self._pad = _pad
    }
}

extension PreviewUniforms {
    /// The frozen memory layout, asserted by grader T1-7 and the Metal side.
    public enum Layout {
        public static let stride = 48
        public static let alignment = 16
        public static let peakingColorOffset = 0
        public static let viewSizeOffset = 16
        public static let zebraThresholdOffset = 24
        public static let peakingThresholdOffset = 28
        public static let rotationOffset = 32
        public static let zebraEnabledOffset = 36
        public static let peakingEnabledOffset = 40
        public static let padOffset = 44
    }
}
