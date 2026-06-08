import CameraCore
import simd

// OWNER: wt/integration.
//
// Glue that binds the Phase-1 producers to `CameraModel` on the main actor.
// `CameraModel` owns one `MonitoringHub`; the hub holds the shared frame conduit
// (FramePump), the histogram producer, and the CoreMotion producer so that:
//
//   • capture's `onVideoFrame` (background queue) → `framePump.submit` → the
//     Metal renderer's registered uploader (preview upload + histogram compute).
//   • the renderer's `HistogramProducer` (delivers on main) → `model.histogram`.
//   • `MotionManager.onAttitude` (background motion queue) → hop to @MainActor →
//     `model.rollDegrees / pitchDegrees / isLevel`.
//
// The hub exposes the *same* `framePump`/`histogramProducer` instances the
// `CameraMetalView` consumes, so a single conduit fans a frame out to both the
// preview and the histogram path. CONTRACTS §6 writer ownership: only this node
// (via the model) writes the monitoring-data properties.

/// Degrees of deviation within which the level guide reads "level".
private let levelThresholdDegrees = 1.0

final class MonitoringHub {
    /// Frame conduit shared with `CameraMetalView`. Capture feeds it; the
    /// renderer registers its off-main uploader into it.
    let framePump = FramePump()
    /// Histogram producer shared with `CameraMetalView`. Delivers on main.
    let histogramProducer = HistogramProducer()
    /// CoreMotion producer (monitoring-owned). Lifecycle tied to the session.
    private let motionManager = MotionManager()

    /// RGBA focus-peaking overlay color, surfaced through `PreviewUniforms`.
    let peakingColor = SIMD4<Float>(1, 0.1, 0.1, 1)
    /// Preview rotation in radians. The capture connection already applies a
    /// `videoRotationAngle`, so the texture arrives upright — no extra rotation.
    let rotation: Float = 0

    /// Wire the producers into the model. Called once from `CameraModel.init`,
    /// already on the main actor. Closures hop to the main actor before writing.
    @MainActor
    func bind(to model: CameraModel) {
        histogramProducer.onHistogram = { [weak model] data in
            // HistogramProducer already delivers on the main thread.
            model?.histogram = data
        }
        motionManager.onAttitude = { [weak model] attitude in
            Task { @MainActor in
                guard let model else { return }
                model.rollDegrees = attitude.rollDegrees
                model.pitchDegrees = attitude.pitchDegrees
                model.isLevel = Level.isLevel(
                    rollDegrees: attitude.rollDegrees,
                    pitchDegrees: attitude.pitchDegrees,
                    threshold: levelThresholdDegrees
                )
            }
        }
    }

    /// Start CoreMotion updates (tied to session start).
    func startMotion() { motionManager.start() }

    /// Stop CoreMotion updates (tied to session stop).
    func stopMotion() { motionManager.stop() }
}
