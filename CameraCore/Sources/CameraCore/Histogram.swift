import Foundation

// OWNER: wt/metal — pure histogram normalization (grader T1-3).
//
// `CameraMetalView` runs a compute kernel that accumulates raw integer bin
// counts per channel into an `MTLBuffer`, reads those counts back, casts them to
// `[Int]`, and calls `normalize` here. All normalization math lives in this
// host-testable type — never in the view or the shader. Imports Foundation only;
// no Metal/media frameworks (CameraCore is host-tested).
public enum Histogram {
    /// Normalize raw bin counts into a `HistogramData` (each channel `0...1`).
    ///
    /// The largest bin in a channel maps to `1.0`; the rest scale linearly by
    /// `count / maxCount`. Inputs need not be exactly `binCount` long — they are
    /// resized (truncated or zero-padded) so every output channel is exactly
    /// `HistogramData.binCount`. An all-zero input returns `HistogramData.empty`
    /// (a channel whose max is `0` yields all zeros — no divide-by-zero).
    ///
    /// - Parameters: per-channel raw bin counts (cast from GPU `UInt32` at the
    ///   call site — the `[Int]` signature is frozen by CONTRACTS §7 T1-3).
    public static func normalize(
        red: [Int],
        green: [Int],
        blue: [Int],
        luma: [Int]
    ) -> HistogramData {
        HistogramData(
            red: normalizeChannel(red),
            green: normalizeChannel(green),
            blue: normalizeChannel(blue),
            luma: normalizeChannel(luma)
        )
    }

    /// Normalize a single channel's bin counts to a length-`binCount` `[Float]`.
    private static func normalizeChannel(_ counts: [Int]) -> [Float] {
        let binCount = HistogramData.binCount
        // Resize to exactly binCount: truncate overflow, zero-pad shortfall.
        let sized = sizedToBinCount(counts, binCount: binCount)

        guard let maxCount = sized.max(), maxCount > 0 else {
            // All-zero (or negative) channel: no peak to divide by.
            return Array(repeating: 0, count: binCount)
        }

        let scale = 1.0 / Float(maxCount)
        return sized.map { count in
            // Clamp negatives (defensive — counts are non-negative on device).
            count <= 0 ? 0 : Float(count) * scale
        }
    }

    /// Return `counts` resized to exactly `binCount` elements.
    private static func sizedToBinCount(_ counts: [Int], binCount: Int) -> [Int] {
        if counts.count == binCount {
            return counts
        }
        if counts.count > binCount {
            return Array(counts.prefix(binCount))
        }
        return counts + Array(repeating: 0, count: binCount - counts.count)
    }
}
