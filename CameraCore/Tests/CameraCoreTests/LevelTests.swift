import Foundation
import Testing

@testable import CameraCore

/// Grader **T1-4** — Level attitude and isLevel.
///
/// All vectors are in the device reference frame used by CoreMotion:
///   x = right, y = up, z = toward user.
/// Gravity points toward Earth, so a face-up flat device reports (0, -1, 0).
///
/// Roll  = rotation around z-axis  → atan2(gx, -gy) in degrees
/// Pitch = rotation around x-axis  → atan2(gz, -gy) in degrees
@Suite("T1-4 Level attitude and isLevel")
struct LevelTests {
    private static let tolerance = 0.001  // degrees

    // MARK: - attitude(gravity:)

    @Test("flat face-up device → ~0° roll and ~0° pitch")
    func flatFaceUp() {
        let attitude = Level.attitude(gravity: .init(0, -1, 0))
        #expect(abs(attitude.rollDegrees) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees) < Self.tolerance)
    }

    @Test("gravity straight down along y → zero roll, zero pitch")
    func gravityNegativeY() {
        // Same as flat face-up but with unit length confirmed.
        let attitude = Level.attitude(gravity: .init(0, -1, 0))
        #expect(abs(attitude.rollDegrees) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees) < Self.tolerance)
    }

    @Test("device rolled 45° right → roll ≈ +45°, pitch ≈ 0°")
    func rolledRight45() {
        // gx = sin(45°) ≈ 0.70711, gy = -cos(45°) ≈ -0.70711, gz = 0
        // roll = atan2(gx, -gy) = atan2(0.70711, 0.70711) = 45°
        let s45 = 0.5.squareRoot()  // √0.5
        let attitude = Level.attitude(gravity: .init(s45, -s45, 0))
        #expect(abs(attitude.rollDegrees - 45.0) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees) < Self.tolerance)
    }

    @Test("device rolled 45° left → roll ≈ -45°, pitch ≈ 0°")
    func rolledLeft45() {
        let s45 = 0.5.squareRoot()
        let attitude = Level.attitude(gravity: .init(-s45, -s45, 0))
        #expect(abs(attitude.rollDegrees - (-45.0)) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees) < Self.tolerance)
    }

    @Test("device tilted forward 45° → pitch ≈ +45°, roll ≈ 0°")
    func tiltedForward45() {
        // gy = -cos(45°), gz = sin(45°)  → pitch = atan2(gz, -gy) = 45°
        let s45 = 0.5.squareRoot()
        let attitude = Level.attitude(gravity: .init(0, -s45, s45))
        #expect(abs(attitude.rollDegrees) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees - 45.0) < Self.tolerance)
    }

    @Test("device tilted backward 45° → pitch ≈ -45°, roll ≈ 0°")
    func tiltedBackward45() {
        let s45 = 0.5.squareRoot()
        let attitude = Level.attitude(gravity: .init(0, -s45, -s45))
        #expect(abs(attitude.rollDegrees) < Self.tolerance)
        #expect(abs(attitude.pitchDegrees - (-45.0)) < Self.tolerance)
    }

    @Test("device rolled 90° → roll ≈ +90°")
    func rolled90() {
        // Fully on its right side with a tiny y to avoid atan2(0,-0) ambiguity.
        // In practice CoreMotion never delivers exact (1,0,0).
        let attitude = Level.attitude(gravity: .init(1, -1e-9, 0))
        #expect(abs(attitude.rollDegrees - 90.0) < 0.01)
        #expect(abs(attitude.pitchDegrees) < 0.01)
    }

    @Test("roll and pitch are independently derivable from gravity")
    func rollAndPitchCombined() {
        // Construct gravity for 30° roll by tilting around z:
        //   gx = sin(30°), gy = -cos(30°), gz = 0   → roll = 30°, pitch = 0°
        let r = 30.0 * Double.pi / 180.0
        let rollOnly = Level.attitude(gravity: .init(sin(r), -cos(r), 0))
        #expect(abs(rollOnly.rollDegrees - 30.0) < 0.001)
        #expect(abs(rollOnly.pitchDegrees) < 0.001)

        // Construct gravity for 20° pitch by tilting around x:
        //   gx = 0, gy = -cos(20°), gz = sin(20°)  → roll = 0°, pitch = 20°
        let p = 20.0 * Double.pi / 180.0
        let pitchOnly = Level.attitude(gravity: .init(0, -cos(p), sin(p)))
        #expect(abs(pitchOnly.rollDegrees) < 0.001)
        #expect(abs(pitchOnly.pitchDegrees - 20.0) < 0.001)
    }

    // MARK: - isLevel(rollDegrees:pitchDegrees:threshold:)

    @Test("exactly level (0°,0°) with any positive threshold → true")
    func exactlyLevel() {
        #expect(Level.isLevel(rollDegrees: 0, pitchDegrees: 0, threshold: 1.0))
        #expect(Level.isLevel(rollDegrees: 0, pitchDegrees: 0, threshold: 0.0))
    }

    @Test("within threshold → true")
    func withinThreshold() {
        #expect(Level.isLevel(rollDegrees: 1.0, pitchDegrees: -0.5, threshold: 2.0))
        #expect(Level.isLevel(rollDegrees: -2.0, pitchDegrees: 2.0, threshold: 2.0))
    }

    @Test("roll exactly at threshold boundary → true (inclusive)")
    func atThresholdBoundary() {
        #expect(Level.isLevel(rollDegrees: 2.0, pitchDegrees: 0.0, threshold: 2.0))
        #expect(Level.isLevel(rollDegrees: -2.0, pitchDegrees: 0.0, threshold: 2.0))
    }

    @Test("roll just over threshold → false")
    func justOverThreshold() {
        #expect(!Level.isLevel(rollDegrees: 2.001, pitchDegrees: 0.0, threshold: 2.0))
        #expect(!Level.isLevel(rollDegrees: -2.001, pitchDegrees: 0.0, threshold: 2.0))
    }

    @Test("pitch is ignored: level roll with large pitch → true (roll-only)")
    func pitchIsIgnored() {
        #expect(Level.isLevel(rollDegrees: 1.0, pitchDegrees: 5.0, threshold: 2.0))
        #expect(Level.isLevel(rollDegrees: 0.0, pitchDegrees: -45.0, threshold: 2.0))
    }

    @Test("roll outside threshold → false regardless of pitch")
    func rollOutsideThreshold() {
        #expect(!Level.isLevel(rollDegrees: -5.0, pitchDegrees: 1.0, threshold: 2.0))
    }

    @Test("negative angles within threshold → true")
    func negativeAnglesWithinThreshold() {
        #expect(Level.isLevel(rollDegrees: -1.5, pitchDegrees: -1.5, threshold: 2.0))
    }
}
