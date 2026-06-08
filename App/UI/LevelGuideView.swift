import SwiftUI

// OWNER: wt/monitoring-ui.
//
// Artificial-horizon level indicator.
// • The horizon bar rotates with roll (transform — compositor-friendly).
// • The centre-dot shifts vertically with pitch (transform).
// • Color and snap snap to the "level" state when isLevel = true.
// • No layout-thrashing properties animated (width/height/padding are static).
struct LevelGuideView: View {

    let rollDegrees: Double
    let pitchDegrees: Double
    let isLevel: Bool

    // MARK: - Design tokens

    private enum Style {
        static let size: CGFloat = 120
        static let horizonWidth: CGFloat = 80
        static let horizonHeight: CGFloat = 2.5
        static let centerDotSize: CGFloat = 7
        static let crosshairArmLength: CGFloat = 10
        static let crosshairArmThick: CGFloat = 1.5
        static let pitchScalePx: CGFloat = 18  // px per degree of pitch shift

        // Off-level tints
        static let horizonOffColor = Color.white.opacity(0.70)
        static let dotOffColor = Color.white.opacity(0.55)
        // On-level tints (snap to vivid green)
        static let horizonOnColor = Color(red: 0.30, green: 1.0, blue: 0.45)
        static let dotOnColor = Color(red: 0.30, green: 1.0, blue: 0.45)

        static let shadowRadius: CGFloat = 3
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Fixed crosshair reticle (static; tells user where level is)
            crosshair

            // Horizon bar rotates with roll and shifts with pitch
            horizonBar
                .rotationEffect(.degrees(rollDegrees))
                .offset(y: pitchOffset)

            // Centre dot marks the gravity centre
            centerDot
        }
        .frame(width: Style.size, height: Style.size)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var crosshair: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let arm = Style.crosshairArmLength
            let t = Style.crosshairArmThick

            var path = Path()
            // Left arm
            path.move(to: CGPoint(x: cx - arm - arm * 0.5, y: cy))
            path.addLine(to: CGPoint(x: cx - arm * 0.5, y: cy))
            // Right arm
            path.move(to: CGPoint(x: cx + arm * 0.5, y: cy))
            path.addLine(to: CGPoint(x: cx + arm + arm * 0.5, y: cy))
            // Top arm
            path.move(to: CGPoint(x: cx, y: cy - arm - arm * 0.5))
            path.addLine(to: CGPoint(x: cx, y: cy - arm * 0.5))
            // Bottom arm
            path.move(to: CGPoint(x: cx, y: cy + arm * 0.5))
            path.addLine(to: CGPoint(x: cx, y: cy + arm + arm * 0.5))

            ctx.stroke(path, with: .color(.white.opacity(0.30)), lineWidth: t)
        }
    }

    private var horizonBar: some View {
        Capsule()
            .fill(isLevel ? Style.horizonOnColor : Style.horizonOffColor)
            .frame(width: Style.horizonWidth, height: Style.horizonHeight)
            .shadow(
                color: isLevel ? Style.horizonOnColor.opacity(0.6) : .clear,
                radius: Style.shadowRadius
            )
            .animation(.easeOut(duration: 0.15), value: isLevel)
    }

    private var centerDot: some View {
        Circle()
            .fill(isLevel ? Style.dotOnColor : Style.dotOffColor)
            .frame(width: Style.centerDotSize, height: Style.centerDotSize)
            .shadow(
                color: isLevel ? Style.dotOnColor.opacity(0.8) : .clear,
                radius: Style.shadowRadius
            )
            .animation(.easeOut(duration: 0.15), value: isLevel)
    }

    // MARK: - Computed geometry

    /// Vertical pixel offset driven by pitch. Clamped so the dot stays within the frame.
    private var pitchOffset: CGFloat {
        let raw = -CGFloat(pitchDegrees) * Style.pitchScalePx / 10.0
        let limit = Style.size / 2 - Style.horizonHeight * 4
        return max(-limit, min(limit, raw))
    }
}
