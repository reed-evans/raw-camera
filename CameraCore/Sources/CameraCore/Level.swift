import simd

// OWNER: wt/monitoring-ui — implement test-first (grader T1-4). Phase-0 stub.
//
// Level math: CoreMotion gravity vector -> roll/pitch in degrees, plus an
// `isLevel` threshold check. Kept pure so it tests without CoreMotion.
public enum Level {
    public struct Attitude: Equatable, Sendable {
        public var rollDegrees: Double
        public var pitchDegrees: Double
        public init(rollDegrees: Double, pitchDegrees: Double) {
            self.rollDegrees = rollDegrees
            self.pitchDegrees = pitchDegrees
        }
    }

    /// Convert a gravity vector (device frame, units of g) to roll/pitch degrees.
    public static func attitude(gravity: SIMD3<Double>) -> Attitude {
        // TODO(wt/monitoring-ui): implement + test (T1-4).
        Attitude(rollDegrees: 0, pitchDegrees: 0)
    }

    /// Whether both roll and pitch are within `threshold` degrees of level.
    public static func isLevel(rollDegrees: Double, pitchDegrees: Double, threshold: Double) -> Bool {
        // TODO(wt/monitoring-ui): implement + test (T1-4).
        abs(rollDegrees) <= threshold && abs(pitchDegrees) <= threshold
    }
}
