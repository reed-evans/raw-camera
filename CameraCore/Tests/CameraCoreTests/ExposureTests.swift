import Testing

@testable import CameraCore

/// Grader **T1-1** — Exposure clamp.
///
/// Verifies that `Exposure.clampISO` and `Exposure.clampShutter` keep values
/// inside the active-format range so that applying them to AVCaptureDevice
/// never throws out-of-range errors at runtime.
@Suite("T1-1 Exposure clamp")
struct ExposureTests {

    // MARK: clampISO

    let limits = ExposureLimits(
        minISO: 50,
        maxISO: 3200,
        minShutterSeconds: 1.0 / 8000.0,
        maxShutterSeconds: 1.0
    )

    @Test("clampISO: in-range value is returned unchanged")
    func clampISO_inRange() {
        #expect(Exposure.clampISO(400, into: limits) == 400)
    }

    @Test("clampISO: value below minimum is clamped to minimum")
    func clampISO_belowMin() {
        #expect(Exposure.clampISO(10, into: limits) == 50)
    }

    @Test("clampISO: value above maximum is clamped to maximum")
    func clampISO_aboveMax() {
        #expect(Exposure.clampISO(6400, into: limits) == 3200)
    }

    @Test("clampISO: exactly at minimum boundary")
    func clampISO_atMin() {
        #expect(Exposure.clampISO(50, into: limits) == 50)
    }

    @Test("clampISO: exactly at maximum boundary")
    func clampISO_atMax() {
        #expect(Exposure.clampISO(3200, into: limits) == 3200)
    }

    @Test("clampISO: NaN input returns minimum (NaN-safe)")
    func clampISO_nan() {
        let result = Exposure.clampISO(Float.nan, into: limits)
        #expect(!result.isNaN)
        #expect(result >= limits.minISO && result <= limits.maxISO)
    }

    @Test("clampISO: negative infinity returns minimum")
    func clampISO_negInfinity() {
        #expect(Exposure.clampISO(-Float.infinity, into: limits) == 50)
    }

    @Test("clampISO: positive infinity returns maximum")
    func clampISO_posInfinity() {
        #expect(Exposure.clampISO(Float.infinity, into: limits) == 3200)
    }

    // MARK: clampShutter

    @Test("clampShutter: in-range value is returned unchanged")
    func clampShutter_inRange() {
        let shutter = 1.0 / 250.0
        #expect(Exposure.clampShutter(shutter, into: limits) == shutter)
    }

    @Test("clampShutter: value below minimum is clamped to minimum")
    func clampShutter_belowMin() {
        let tooFast = 1.0 / 100_000.0
        let result = Exposure.clampShutter(tooFast, into: limits)
        #expect(result == limits.minShutterSeconds)
    }

    @Test("clampShutter: value above maximum is clamped to maximum")
    func clampShutter_aboveMax() {
        let tooSlow = 30.0
        let result = Exposure.clampShutter(tooSlow, into: limits)
        #expect(result == limits.maxShutterSeconds)
    }

    @Test("clampShutter: exactly at minimum boundary")
    func clampShutter_atMin() {
        #expect(Exposure.clampShutter(limits.minShutterSeconds, into: limits) == limits.minShutterSeconds)
    }

    @Test("clampShutter: exactly at maximum boundary")
    func clampShutter_atMax() {
        #expect(Exposure.clampShutter(limits.maxShutterSeconds, into: limits) == limits.maxShutterSeconds)
    }

    @Test("clampShutter: NaN input is NaN-safe and returns in-range value")
    func clampShutter_nan() {
        let result = Exposure.clampShutter(Double.nan, into: limits)
        #expect(!result.isNaN)
        #expect(result >= limits.minShutterSeconds && result <= limits.maxShutterSeconds)
    }

    @Test("clampShutter: negative infinity returns minimum")
    func clampShutter_negInfinity() {
        #expect(Exposure.clampShutter(-Double.infinity, into: limits) == limits.minShutterSeconds)
    }

    @Test("clampShutter: positive infinity returns maximum")
    func clampShutter_posInfinity() {
        #expect(Exposure.clampShutter(Double.infinity, into: limits) == limits.maxShutterSeconds)
    }

    // MARK: unset limits edge case

    @Test("clampISO: unset limits (all zero) returns zero (boundary = 0)")
    func clampISO_unsetLimits() {
        // ExposureLimits.unset has min=max=0; clamp of any value returns 0
        let result = Exposure.clampISO(400, into: .unset)
        #expect(result == 0)
    }

    @Test("clampShutter: unset limits (all zero) returns zero")
    func clampShutter_unsetLimits() {
        let result = Exposure.clampShutter(0.01, into: .unset)
        #expect(result == 0)
    }
}
