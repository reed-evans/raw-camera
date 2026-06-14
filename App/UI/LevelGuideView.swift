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

        // Reference tick ring: 8 marks at 45°, starting at the horizon-bar ends.
        // Cardinal (horizontal/vertical) ticks run longer than the diagonals.
        static let tickCount = 8
        static let tickLengthCardinal: CGFloat = 11
        static let tickLengthDiagonal: CGFloat = 6
        static let tickThick: CGFloat = 1
        static let tickColor = Color.white.opacity(0.45)

        // Horizon-bar tint: muted white off-level, snapping to red when level.
        static let horizonOffColor = Color.white.opacity(0.70)
        static let horizonOnColor = Color(red: 1.0, green: 0.0, blue: 0.0)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Fixed crosshair reticle (static; tells user where level is)
            crosshair

            // Fixed reference tick ring (static)
            tickRing

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

    /// Eight radial ticks at 45° intervals. Each tick's inner end sits at the
    /// horizon-bar radius, so the horizontal pair lines up with the level
    /// line's ends. Even indices are the cardinal (horizontal + vertical) ticks
    /// that snap to red when level, matching the horizon bar; odd indices are
    /// the diagonals, which stay muted.
    private var tickRing: some View {
        ZStack {
            ForEach(0..<Style.tickCount, id: \.self) { i in
                let length = tickLength(forIndex: i)
                Rectangle()
                    .fill(tickColor(forIndex: i))
                    .frame(width: Style.tickThick, height: length)
                    .position(
                        x: Style.size / 2,
                        y: Style.size / 2 - Style.horizonWidth / 2 - length / 2
                    )
                    .frame(width: Style.size, height: Style.size)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .animation(.easeOut(duration: 0.15), value: isLevel)
    }

    private func isCardinal(_ i: Int) -> Bool { i % 2 == 0 }

    /// Cardinal ticks (even index: up/right/down/left) run longer than the
    /// diagonals; their inner ends still sit at the horizon-bar radius.
    private func tickLength(forIndex i: Int) -> CGFloat {
        isCardinal(i) ? Style.tickLengthCardinal : Style.tickLengthDiagonal
    }

    /// Cardinal ticks turn red when level; diagonals stay muted.
    private func tickColor(forIndex i: Int) -> Color {
        (isCardinal(i) && isLevel) ? Style.horizonOnColor : Style.tickColor
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
