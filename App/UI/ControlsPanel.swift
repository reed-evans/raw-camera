import CameraCore
import SwiftUI

// OWNER: wt/controls-ui. Phase-0 stub. Binds sliders/toggles to the frozen
// `CameraModel` surface only — no capture logic lives here.
struct ControlsPanel: View {
    @Bindable var model: CameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Controls")
                .font(.headline)
            // TODO(wt/controls-ui): shutter, ISO, WB, focus controls + auto/manual toggles.
        }
        .padding()
    }
}
