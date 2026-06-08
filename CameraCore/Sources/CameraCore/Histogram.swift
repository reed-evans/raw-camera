import Foundation

// OWNER: wt/metal — implement test-first (grader T1-3). Phase-0 stub.
//
// Histogram normalization: raw per-channel bin counts -> normalized 0...1.
// The max bin maps to 1.0; an empty frame must not divide by zero.
public enum Histogram {
    /// Normalize raw bin counts (each array length `HistogramData.binCount`).
    /// An all-zero input returns `.empty` (no divide-by-zero).
    public static func normalize(
        red: [Int],
        green: [Int],
        blue: [Int],
        luma: [Int]
    ) -> HistogramData {
        // TODO(wt/metal): implement + test (T1-3).
        .empty
    }
}
