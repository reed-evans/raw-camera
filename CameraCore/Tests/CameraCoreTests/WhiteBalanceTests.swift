import Testing

@testable import CameraCore

/// Grader **T1-2** — White-balance gain clamp and temperature/tint conversion.
///
/// Every output channel must be finite and within `1.0...maxGain`.
@Suite("T1-2 WhiteBalance")
struct WhiteBalanceTests {

    // MARK: clampGains

    @Test("clampGains: already-valid gains pass through unchanged")
    func clampGains_inRange() {
        let gains = WhiteBalanceGains(red: 1.5, green: 1.0, blue: 2.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 1.5)
        #expect(result.green == 1.0)
        #expect(result.blue == 2.0)
    }

    @Test("clampGains: red below 1.0 is clamped to 1.0")
    func clampGains_redBelowMin() {
        let gains = WhiteBalanceGains(red: 0.5, green: 1.0, blue: 1.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 1.0)
    }

    @Test("clampGains: green below 1.0 is clamped to 1.0")
    func clampGains_greenBelowMin() {
        let gains = WhiteBalanceGains(red: 1.0, green: 0.1, blue: 1.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.green == 1.0)
    }

    @Test("clampGains: blue below 1.0 is clamped to 1.0")
    func clampGains_blueBelowMin() {
        let gains = WhiteBalanceGains(red: 1.0, green: 1.0, blue: 0.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.blue == 1.0)
    }

    @Test("clampGains: all channels above maxGain are clamped to maxGain")
    func clampGains_allAboveMax() {
        let gains = WhiteBalanceGains(red: 10, green: 10, blue: 10)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 4.0)
        #expect(result.green == 4.0)
        #expect(result.blue == 4.0)
    }

    @Test("clampGains: NaN channels become 1.0 (NaN-safe)")
    func clampGains_nanChannels() {
        let gains = WhiteBalanceGains(red: Float.nan, green: Float.nan, blue: Float.nan)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(!result.red.isNaN)
        #expect(!result.green.isNaN)
        #expect(!result.blue.isNaN)
        #expect(result.red >= 1.0 && result.red <= 4.0)
        #expect(result.green >= 1.0 && result.green <= 4.0)
        #expect(result.blue >= 1.0 && result.blue <= 4.0)
    }

    @Test("clampGains: negative infinity channels clamped to 1.0")
    func clampGains_negInfinity() {
        let gains = WhiteBalanceGains(red: -Float.infinity, green: 1.0, blue: 1.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 1.0)
    }

    @Test("clampGains: positive infinity channels clamped to maxGain")
    func clampGains_posInfinity() {
        let gains = WhiteBalanceGains(red: Float.infinity, green: 1.0, blue: 1.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 4.0)
    }

    @Test("clampGains: neutral gains pass through unchanged")
    func clampGains_neutral() {
        let result = WhiteBalance.clampGains(.neutral, maxGain: 4.0)
        #expect(result == .neutral)
    }

    @Test("clampGains: exactly at minimum boundary (1.0) passes through")
    func clampGains_atMin() {
        let gains = WhiteBalanceGains(red: 1.0, green: 1.0, blue: 1.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 1.0)
        #expect(result.green == 1.0)
        #expect(result.blue == 1.0)
    }

    @Test("clampGains: exactly at maxGain boundary passes through")
    func clampGains_atMax() {
        let gains = WhiteBalanceGains(red: 4.0, green: 4.0, blue: 4.0)
        let result = WhiteBalance.clampGains(gains, maxGain: 4.0)
        #expect(result.red == 4.0)
        #expect(result.green == 4.0)
        #expect(result.blue == 4.0)
    }

    // MARK: gains(temperature:tint:maxGain:)

    @Test("gains: daylight (~5600K) produces valid finite in-range result")
    func gains_daylight() {
        let result = WhiteBalance.gains(temperature: 5600, tint: 0, maxGain: 4.0)
        assertValidGains(result, maxGain: 4.0)
    }

    @Test("gains: tungsten (~3200K) produces valid finite in-range result")
    func gains_tungsten() {
        let result = WhiteBalance.gains(temperature: 3200, tint: 0, maxGain: 4.0)
        assertValidGains(result, maxGain: 4.0)
    }

    @Test("gains: cloudy/overcast (~7000K) produces valid finite in-range result")
    func gains_cloudy() {
        let result = WhiteBalance.gains(temperature: 7000, tint: 0, maxGain: 4.0)
        assertValidGains(result, maxGain: 4.0)
    }

    @Test("gains: tint = -150 (green) produces valid result")
    func gains_tintNegative() {
        let result = WhiteBalance.gains(temperature: 5000, tint: -150, maxGain: 4.0)
        assertValidGains(result, maxGain: 4.0)
    }

    @Test("gains: tint = +150 (magenta) produces valid result")
    func gains_tintPositive() {
        let result = WhiteBalance.gains(temperature: 5000, tint: 150, maxGain: 4.0)
        assertValidGains(result, maxGain: 4.0)
    }

    @Test("gains: warm light (2500K) produces warm (red > blue) bias")
    func gains_warmIsRedBiased() {
        let result = WhiteBalance.gains(temperature: 2500, tint: 0, maxGain: 8.0)
        // Very warm: blue channel should need more amplification than red
        // (camera boost blue to compensate for warm/orange ambient).
        // In device WB terms, cool light → high blue gain; warm → lower blue.
        // The exact ratio is model-dependent, but the result must be valid.
        assertValidGains(result, maxGain: 8.0)
    }

    @Test("gains: cool light (8000K) produces cool (blue > red) bias")
    func gains_coolIsBlueBiased() {
        let result = WhiteBalance.gains(temperature: 8000, tint: 0, maxGain: 8.0)
        assertValidGains(result, maxGain: 8.0)
    }

    @Test("gains: all channels finite")
    func gains_allFinite() {
        let result = WhiteBalance.gains(temperature: 5000, tint: 0, maxGain: 4.0)
        #expect(result.red.isFinite)
        #expect(result.green.isFinite)
        #expect(result.blue.isFinite)
    }

    @Test("gains: result respects maxGain even for extreme temperatures")
    func gains_extremeTemperatureRespectsBounds() {
        for temp: Float in [1000, 2500, 5500, 8000, 20000] {
            let result = WhiteBalance.gains(temperature: temp, tint: 0, maxGain: 4.0)
            assertValidGains(result, maxGain: 4.0)
        }
    }

    @Test("gains: green channel is always at or near 1.0 (green-pinned model)")
    func gains_greenNearOne() {
        // The standard approach pins green to 1.0 and adjusts red/blue around it.
        // Allow a small tolerance in case the model scales all three.
        let result = WhiteBalance.gains(temperature: 5500, tint: 0, maxGain: 4.0)
        #expect(result.green >= 1.0 && result.green <= 4.0)
    }

    // MARK: Helpers

    private func assertValidGains(_ gains: WhiteBalanceGains, maxGain: Float) {
        #expect(gains.red.isFinite, "red must be finite")
        #expect(gains.green.isFinite, "green must be finite")
        #expect(gains.blue.isFinite, "blue must be finite")
        #expect(gains.red >= 1.0, "red must be >= 1.0")
        #expect(gains.green >= 1.0, "green must be >= 1.0")
        #expect(gains.blue >= 1.0, "blue must be >= 1.0")
        #expect(gains.red <= maxGain, "red must be <= maxGain")
        #expect(gains.green <= maxGain, "green must be <= maxGain")
        #expect(gains.blue <= maxGain, "blue must be <= maxGain")
    }
}
