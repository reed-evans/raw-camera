import CameraCore
import SwiftUI

// OWNER: wt/controls-ui. Xcode previews for ControlsPanel (DEBUG only).

#if DEBUG
    #Preview("collapsed") {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                ControlsPanel(model: .preview())
                    .padding(.horizontal, 12)
            }
        }.preferredColorScheme(.dark)
    }

    #Preview("manual") {
        let model = CameraModel.preview()
        model.isManualExposure = true
        model.isManualWhiteBalance = true
        model.isManualFocus = true
        model.zebraEnabled = true
        model.focusPeakingEnabled = true
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                ControlsPanel(model: model)
                    .padding(.horizontal, 12)
            }
        }.preferredColorScheme(.dark)
    }
#endif
