import CameraCore
import Foundation

// OWNER: wt/monitoring-ui. Phase-0 stub. Wraps CMMotionManager and maps the
// gravity vector to roll/pitch via `CameraCore.Level`, publishing to the model.
@MainActor
final class MotionManager {
    var onAttitude: ((Level.Attitude) -> Void)?

    func start() {}
    func stop() {}
}
