import SwiftUI

// OWNER: wt/integration. App entry point. Composes the capture service and the
// shared model, then shows the camera screen.
@main
struct RAWCameraApp: App {
    @State private var model = CameraModel(service: CaptureService())

    var body: some Scene {
        WindowGroup {
            CameraScreen(model: model)
        }
    }
}
