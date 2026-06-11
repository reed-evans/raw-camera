import SwiftUI
import UIKit

// OWNER: wt/integration.
//
// The interface is locked to portrait (Info.plist), so the layout never
// reflows. Individual controls are counter-rotated by the physical device
// orientation so they face the user when the phone is held sideways. The preview
// itself is left unrotated.

enum DeviceOrientationAngle {
    /// Counter-rotation for a control, given the physical device orientation.
    /// Returns nil for face-up/face-down/unknown so the caller keeps the last
    /// valid angle instead of snapping to 0 when the phone lies flat.
    static func angle(for orientation: UIDeviceOrientation) -> Angle? {
        switch orientation {
        case .portrait: return .degrees(0)
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        case .portraitUpsideDown: return .degrees(180)
        default: return nil
        }
    }
}

extension View {
    /// Rotate a control in place so it faces the user while the interface stays
    /// locked to portrait. At 0° this is a no-op (portrait is unchanged).
    func facingUser(_ angle: Angle) -> some View {
        rotationEffect(angle)
            .animation(.easeInOut(duration: 0.25), value: angle)
    }
}
