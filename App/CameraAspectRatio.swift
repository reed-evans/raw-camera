import Foundation

// OWNER: wt/integration.
//
// Preview framing aspect ratios. NOTE: the RAW/ProRAW DNG always captures the
// full sensor frame — this only frames the live preview for composition; crop in
// post. The value is the long:short ratio (>= 1); the shader orients it to the
// camera frame (portrait vs landscape).
enum CameraAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case oneOne = "1:1"

    var id: String { rawValue }
    var label: String { rawValue }

    /// Long-side / short-side ratio (>= 1).
    var ratio: Float {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenNine: return 16.0 / 9.0
        case .oneOne: return 1.0
        }
    }
}
