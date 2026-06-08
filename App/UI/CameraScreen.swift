import CameraCore
import SwiftUI

// OWNER: wt/integration. Phase-0 stub composing the preview, controls, and
// monitoring overlays over the shared `CameraModel`.
struct CameraScreen: View {
    @State private var model: CameraModel

    init(model: CameraModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            CameraMetalView(model: model)
                .ignoresSafeArea()

            VStack {
                if model.levelGuideEnabled {
                    LevelGuideView(
                        rollDegrees: model.rollDegrees,
                        pitchDegrees: model.pitchDegrees,
                        isLevel: model.isLevel
                    )
                }
                Spacer()
                if model.histogramEnabled {
                    HistogramView(histogram: model.histogram)
                }
                ControlsPanel(model: model)
            }
        }
        .onAppear { model.startSession() }
        .onDisappear { model.stopSession() }
    }
}
