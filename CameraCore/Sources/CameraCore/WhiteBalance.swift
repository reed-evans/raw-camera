import Foundation

// OWNER: wt/capture — implement test-first (grader T1-2). Phase-0 stub.
//
// Pure white-balance math: clamp device gains and convert temperature/tint to
// per-channel gains. Results must be finite and within `1.0...maxGain`.
public enum WhiteBalance {
    /// Clamp every channel into `1.0...maxGain`.
    public static func clampGains(_ gains: WhiteBalanceGains, maxGain: Float) -> WhiteBalanceGains {
        // TODO(wt/capture): implement + test (T1-2).
        gains
    }

    /// Convert a temperature (Kelvin) + tint to clamped per-channel gains.
    public static func gains(temperature: Float, tint: Float, maxGain: Float) -> WhiteBalanceGains {
        // TODO(wt/capture): implement + test (T1-2).
        .neutral
    }
}
