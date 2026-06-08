import Testing

@testable import CameraCore

/// Grader **T1-3** — Histogram normalization.
///
/// `Histogram.normalize` takes raw per-channel bin counts (as `[Int]`, cast from
/// GPU `UInt32` at the call site) and maps them to `0...1` floats: the largest
/// bin in a channel becomes `1.0`, everything else scales linearly. All-zero
/// input must return `HistogramData.empty` (no divide-by-zero), and every output
/// array must be exactly `HistogramData.binCount` (256) long.
@Suite("T1-3 Histogram normalization")
struct HistogramTests {
    /// Builds a length-256 bin array, all zero except the given (index, value) pairs.
    private func bins(_ pairs: [(Int, Int)]) -> [Int] {
        var out = Array(repeating: 0, count: HistogramData.binCount)
        for (index, value) in pairs {
            out[index] = value
        }
        return out
    }

    @Test("a single saturated bin normalizes to 1.0")
    func singleSaturatedBin() {
        // Arrange: one bin carries all the count for each channel.
        let red = bins([(255, 1000)])
        let green = bins([(128, 42)])
        let blue = bins([(0, 7)])
        let luma = bins([(200, 99)])

        // Act
        let result = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)

        // Assert: the lone non-zero bin is the max ⇒ exactly 1.0 in each channel.
        #expect(result.red[255] == 1.0)
        #expect(result.green[128] == 1.0)
        #expect(result.blue[0] == 1.0)
        #expect(result.luma[200] == 1.0)
    }

    @Test("all-zero counts return HistogramData.empty (no divide-by-zero)")
    func allZeroReturnsEmpty() {
        // Arrange
        let zeros = Array(repeating: 0, count: HistogramData.binCount)

        // Act
        let result = Histogram.normalize(red: zeros, green: zeros, blue: zeros, luma: zeros)

        // Assert: exactly the frozen empty value — all bins 0, no NaN/Inf.
        #expect(result == HistogramData.empty)
        #expect(result.red.allSatisfy { $0 == 0 })
        #expect(result.green.allSatisfy { $0 == 0 })
        #expect(result.blue.allSatisfy { $0 == 0 })
        #expect(result.luma.allSatisfy { $0 == 0 })
        #expect(result.red.allSatisfy { $0.isFinite })
    }

    @Test("each output channel has exactly 256 bins")
    func outputLengthIs256() {
        // Arrange: ragged/short inputs must still produce 256-length outputs.
        let red = bins([(10, 5)])
        let green = [Int]()  // empty — undersized input
        let blue = Array(repeating: 1, count: 300)  // oversized input
        let luma = bins([(255, 3)])

        // Act
        let result = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)

        // Assert
        #expect(result.red.count == HistogramData.binCount)
        #expect(result.green.count == HistogramData.binCount)
        #expect(result.blue.count == HistogramData.binCount)
        #expect(result.luma.count == HistogramData.binCount)
    }

    @Test("a known distribution normalizes to expected ratios")
    func knownDistributionRatios() {
        // Arrange: max bin is 200, others are fractions of it.
        let red = bins([(0, 50), (1, 100), (2, 200)])
        let green = bins([(0, 200)])
        let blue = bins([(0, 200)])
        let luma = bins([(0, 200)])

        // Act
        let result = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)

        // Assert: each bin = count / maxCount.
        #expect(abs(result.red[0] - 0.25) < 1e-6)
        #expect(abs(result.red[1] - 0.5) < 1e-6)
        #expect(result.red[2] == 1.0)
        // Bins with no count stay at 0.
        #expect(result.red[3] == 0.0)
    }

    @Test("every output value stays within 0...1")
    func outputsAreInUnitRange() {
        // Arrange
        let red = bins([(5, 12), (6, 34), (7, 8), (255, 1)])
        let green = bins([(100, 7)])
        let blue = bins([(0, 1), (255, 9)])
        let luma = bins([(50, 5), (51, 5)])

        // Act
        let result = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)

        // Assert
        for channel in [result.red, result.green, result.blue, result.luma] {
            #expect(channel.allSatisfy { $0 >= 0 && $0 <= 1 })
            #expect(channel.contains(1.0))  // the channel max maps to 1.0
        }
    }

    @Test("an independently-zero channel stays empty without affecting others")
    func perChannelIndependence() {
        // Arrange: blue is all zero; the rest carry data.
        let red = bins([(10, 80)])
        let green = bins([(20, 40)])
        let blue = Array(repeating: 0, count: HistogramData.binCount)
        let luma = bins([(30, 5)])

        // Act
        let result = Histogram.normalize(red: red, green: green, blue: blue, luma: luma)

        // Assert: blue is all zero (its own max is 0 ⇒ no divide-by-zero),
        // others normalize their own max to 1.0.
        #expect(result.blue.allSatisfy { $0 == 0 })
        #expect(result.red[10] == 1.0)
        #expect(result.green[20] == 1.0)
        #expect(result.luma[30] == 1.0)
    }
}
