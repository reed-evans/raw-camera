import SwiftUI

// OWNER: wt/monitoring-ui. Phase-0 stub. Renders the artificial horizon from
// roll/pitch (degrees) and highlights when level. Level math lives in CameraCore.
struct LevelGuideView: View {
    let rollDegrees: Double
    let pitchDegrees: Double
    let isLevel: Bool

    var body: some View {
        Canvas { _, _ in
            // TODO(wt/monitoring-ui): draw the level/horizon indicator.
        }
        .frame(width: 120, height: 120)
    }
}
