import Testing

@testable import CameraCore

@Suite("Exposure bracket biases (capture options)")
struct CaptureOptionsTests {
    @Test("3-shot ±2EV bracket is symmetric around 0")
    func threeShotSymmetric() {
        let biases = ExposureBracket.biases(count: 3, stops: 2, minBias: -8, maxBias: 8)
        #expect(biases == [-2, 0, 2])
    }

    @Test("biases clamp into the device range")
    func clampsToDeviceRange() {
        let biases = ExposureBracket.biases(count: 3, stops: 4, minBias: -2, maxBias: 2)
        #expect(biases == [-2, 0, 2])
    }

    @Test("5-shot bracket steps by stops")
    func fiveShot() {
        let biases = ExposureBracket.biases(count: 5, stops: 1, minBias: -8, maxBias: 8)
        #expect(biases == [-2, -1, 0, 1, 2])
    }

    @Test("count below 1 yields a single zero bias")
    func degenerateCount() {
        #expect(ExposureBracket.biases(count: 0, stops: 2, minBias: -8, maxBias: 8) == [0])
        #expect(ExposureBracket.biases(count: -3, stops: 2, minBias: -8, maxBias: 8) == [0])
    }

    @Test("non-finite stops degrade to zero offsets")
    func nonFiniteStops() {
        let biases = ExposureBracket.biases(count: 3, stops: .nan, minBias: -8, maxBias: 8)
        #expect(biases == [0, 0, 0])
    }

    @Test("every bias is finite and in range for asymmetric device limits")
    func asymmetricRange() {
        let biases = ExposureBracket.biases(count: 3, stops: 3, minBias: -1, maxBias: 8)
        #expect(biases == [-1, 0, 3])
        #expect(biases.allSatisfy { $0.isFinite && $0 >= -1 && $0 <= 8 })
    }
}
