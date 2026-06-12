import CameraCore
import SwiftUI

// OWNER: wt/integration. Optional vertical zoom slider overlay. Pinch-to-zoom
// works regardless; this is the settings-configurable on-screen control.
struct ZoomSlider: View {
    @Bindable var model: CameraModel

    var body: some View {
        let lo = model.minZoom
        let hi = max(lo + 0.1, model.maxZoom)  // guard against a zero-width range
        VStack(spacing: 10) {
            Text(String(format: "%.1f×", model.zoomFactor))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 44)
            Slider(
                value: Binding(get: { model.zoomFactor }, set: { model.setZoom($0) }),
                in: lo...hi
            )
            .tint(.white)
            .frame(width: 170)
            .rotationEffect(.degrees(-90))  // bottom = min, top = max
            .frame(width: 40, height: 170)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .liquidGlass(in: Capsule())
    }
}

#if DEBUG
    #Preview {
        ZoomSlider(model: .preview())
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .preferredColorScheme(.dark)
    }
#endif
