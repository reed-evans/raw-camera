import SwiftUI

// OWNER: wt/monitoring-ui.
//
// Instrument-style artificial-horizon level indicator (roll-only):
// • A full-width green horizon line rotates with roll (transform only — the
//   line is longer than the screen so its ends never show).
// • A fixed graduated bezel ring frames the center.
// • A center reference segment lights green when level.
struct LevelGuideView: View {

    let rollDegrees: Double
    let isLevel: Bool

    // MARK: - Design tokens

    private enum Style {
        static let frame: CGFloat = 150

        // Graduated bezel ring: minor ticks every `minorStep`, longer majors.
        static let ringOuterRadius: CGFloat = 64
        static let minorStepDegrees = 6
        static let majorEveryDegrees = 30
        static let minorTickLength: CGFloat = 5
        static let majorTickLength: CGFloat = 10
        static let minorTickColor = Color.white.opacity(0.45)
        static let majorTickColor = Color.white.opacity(0.85)

        // Horizon line: two segments running from the center-reference ends out
        // to the screen edges (the middle is left to the center segment). Each
        // is longer than the screen so its outer end never shows at any roll.
        // Green only when level; muted white otherwise.
        static let segmentLength: CGFloat = 1000
        static let lineThickness: CGFloat = 1
        static let lineColor = Color(red: 0.40, green: 1.0, blue: 0.35)
        static let lineOffColor = Color.white.opacity(0.75)

        // Center reference cross. The bars are filled opaque and the
        // transparency is applied to the flattened cross (compositing group),
        // so the bars don't double up and brighten where they overlap.
        static let centerWidth: CGFloat = 26
        static let centerHeight: CGFloat = 2
        static let centerColor = Color.white
        static let centerOpacity: Double = 0.6
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            bezelRing
            horizonLine
                .rotationEffect(.degrees(rollDegrees))
            centerCross
        }
        .frame(width: Style.frame, height: Style.frame)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var bezelRing: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = Style.ringOuterRadius
            var deg = 0
            while deg < 360 {
                let isMajor = deg % Style.majorEveryDegrees == 0
                let length = isMajor ? Style.majorTickLength : Style.minorTickLength
                let inner = outer - length
                let radians = Double(deg) * .pi / 180
                let dx = cos(radians)
                let dy = sin(radians)
                var path = Path()
                path.move(to: CGPoint(x: center.x + dx * inner, y: center.y + dy * inner))
                path.addLine(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
                ctx.stroke(
                    path,
                    with: .color(isMajor ? Style.majorTickColor : Style.minorTickColor),
                    lineWidth: isMajor ? 1.5 : 1)
                deg += Style.minorStepDegrees
            }
        }
        .frame(width: Style.frame, height: Style.frame)
    }

    private var horizonLine: some View {
        // Each segment's inner end sits at a center-reference end; both extend
        // outward past the screen edge. Symmetric offsets keep them centered on
        // the rotation anchor.
        let color = isLevel ? Style.lineColor : Style.lineOffColor
        let inset = Style.centerWidth / 2 + Style.segmentLength / 2
        return ZStack {
            segment(color: color).offset(x: -inset)
            segment(color: color).offset(x: inset)
        }
        .animation(.easeOut(duration: 0.15), value: isLevel)
    }

    private func segment(color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: Style.segmentLength, height: Style.lineThickness)
    }

    /// Horizontal + vertical reference bars. Flattened opaque (compositingGroup)
    /// before the shared opacity is applied, so the overlap doesn't brighten.
    private var centerCross: some View {
        ZStack {
            Capsule()
                .fill(Style.centerColor)
                .frame(width: Style.centerWidth, height: Style.centerHeight)
            Capsule()
                .fill(Style.centerColor)
                .frame(width: Style.centerHeight, height: Style.centerWidth)
        }
        .compositingGroup()
        .opacity(Style.centerOpacity)
    }
}

#if DEBUG
    #Preview {
        VStack(spacing: 40) {
            LevelGuideView(rollDegrees: 0, isLevel: true)
            LevelGuideView(rollDegrees: 12, isLevel: false)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
#endif
