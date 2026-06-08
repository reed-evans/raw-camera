import CameraCore
import SwiftUI

// OWNER: wt/metal. Phase-0 stub. Becomes the MTKView-backed preview that
// uploads each CVPixelBuffer via CVMetalTextureCache, runs the zebra /
// focus-peaking passes driven by `PreviewUniforms`, and reads back the
// histogram (normalized in CameraCore.Histogram).
struct CameraMetalView: UIViewRepresentable {
    let model: CameraModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
