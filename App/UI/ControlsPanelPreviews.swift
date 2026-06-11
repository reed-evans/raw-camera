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

    // Auto mode with the drawer open: exposure / white-balance / focus each show
    // a read-only readout of the device's current values (here, sample values
    // since the preview stub has no live device).
    #Preview("auto values") {
        let model = CameraModel.preview()
        model.showSettings = true
        model.iso = 320
        model.shutterSeconds = 1.0 / 120
        model.whiteBalanceTemperature = 5200
        model.whiteBalanceTint = 4
        model.focusLensPosition = 0.43
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
