import simd

// OWNER: wt/monitoring-ui — T1-4.
//
// Pure simd math: CoreMotion gravity vector (device frame, units of g) →
// roll/pitch in degrees. No Apple media/motion frameworks — builds headless.
//
// Coordinate convention (CoreMotion device frame):
//   x = right,  y = up,  z = toward user
// Gravity points toward Earth, so a flat face-up device reports (0, -1, 0).
//
// Roll  = atan2(gx,  -gy)   — positive = tilted right
// Pitch = atan2(gz,  -gy)   — positive = tilted forward (top away from user)
public enum Level {

    // MARK: - Types

    public struct Attitude: Equatable, Sendable {
        public var rollDegrees: Double
        public var pitchDegrees: Double

        public init(rollDegrees: Double, pitchDegrees: Double) {
            self.rollDegrees = rollDegrees
            self.pitchDegrees = pitchDegrees
        }
    }

    // MARK: - Public API

    /// Convert a gravity vector (device frame, units of g) to roll/pitch degrees.
    /// - Parameter gravity: raw CMDeviceMotion.gravity cast to SIMD3<Double>.
    /// - Returns: Attitude with roll and pitch in degrees.
    public static func attitude(gravity: SIMD3<Double>) -> Attitude {
        let negY = -gravity.y
        let rollRad = atan2(gravity.x, negY)
        let pitchRad = atan2(gravity.z, negY)
        return Attitude(
            rollDegrees: rollRad * (180.0 / Double.pi),
            pitchDegrees: pitchRad * (180.0 / Double.pi)
        )
    }

    /// Whether both roll and pitch are within `threshold` degrees of level.
    /// Level is defined as the closed interval [−threshold, +threshold].
    /// - Parameters:
    ///   - rollDegrees: current roll in degrees.
    ///   - pitchDegrees: current pitch in degrees.
    ///   - threshold: maximum allowed deviation in degrees (inclusive).
    /// - Returns: `true` iff |roll| ≤ threshold AND |pitch| ≤ threshold.
    public static func isLevel(
        rollDegrees: Double,
        pitchDegrees: Double,
        threshold: Double
    ) -> Bool {
        abs(rollDegrees) <= threshold && abs(pitchDegrees) <= threshold
    }
}
