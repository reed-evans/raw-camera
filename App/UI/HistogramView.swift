import CameraCore
import SwiftUI

// OWNER: wt/monitoring-ui. Phase-0 stub. Draws the normalized `HistogramData`
// (RGB + luma) with SwiftUI Canvas. Normalization itself lives in CameraCore.
struct HistogramView: View {
    let histogram: HistogramData

    var body: some View {
        Canvas { _, _ in
            // TODO(wt/monitoring-ui): draw RGB + luma curves from `histogram`.
        }
        .frame(height: 80)
    }
}
