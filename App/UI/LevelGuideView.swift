import SwiftUI

// OWNER: wt/monitoring-ui.
//
// Artificial-horizon level indicator (roll-only).
// • The horizon bar rotates with roll (transform — compositor-friendly).
// • Color snaps to the "level" state when isLevel = true.
// • No layout-thrashing properties animated (width/height/padding are static).
struct LevelGuideView: View {

    let rollDegrees: Double
    let isLevel: Bool

    // MARK: - Design tokens

    private enum Style {
        static let size: CGFloat = 120
        static let horizonWidth: CGFloat = 80
        static let horizonHeight: CGFloat = 1
        static let crosshairArmLength: CGFloat = 10
        static let crosshairArmThick: CGFloat = 1

        // Horizon-bar tint: muted white off-level, snapping to red when level.
        static let horizonOffColor = Color.white.opacity(0.70)
        static let horizonOnColor = Color(red: 1.0, green: 0.0, blue: 0.0)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Fixed crosshair reticle (static; tells user where level is)
            crosshair

            // Horizon bar rotates with roll
            horizonBar
                .rotationEffect(.degrees(rollDegrees))
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
            .animation(.easeOut(duration: 0.15), value: isLevel)
    }
}

#if DEBUG
    #Preview {
        HStack(spacing: 40) {
            LevelGuideView(rollDegrees: 0, isLevel: true)
            LevelGuideView(rollDegrees: 12, isLevel: false)
        }
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
#endif
