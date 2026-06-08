import CameraCore
import SwiftUI

// OWNER: wt/monitoring-ui.
//
// Draws normalized HistogramData (R/G/B + luma) with SwiftUI Canvas.
// Each channel is an area fill + stroke, layered as a graticule.
// All values arrive pre-normalized to 0...1 from CameraCore.Histogram.normalize.
// Canvas redraws only when `histogram` changes — no per-frame allocations.
struct HistogramView: View {

    let histogram: HistogramData

    // MARK: - Design tokens

    private enum Style {
        static let height: CGFloat = 88
        static let cornerRadius: CGFloat = 6
        static let gridLines = 4  // horizontal graticule divisions
        static let gridColor = Color.white.opacity(0.10)
        static let borderColor = Color.white.opacity(0.18)
        static let backgroundColor = Color.black.opacity(0.55)

        // Channel colors — saturated, semi-transparent for layering
        static let red = Color(red: 1, green: 0.22, blue: 0.22, opacity: 0.55)
        static let green = Color(red: 0.22, green: 1, blue: 0.22, opacity: 0.45)
        static let blue = Color(red: 0.30, green: 0.55, blue: 1.0, opacity: 0.55)
        static let luma = Color.white.opacity(0.70)

        // Fill alpha is lighter than stroke
        static let fillOpacity = 0.18
        static let strokeWidth: CGFloat = 1.0
    }

    var body: some View {
        Canvas { ctx, size in
            drawBackground(ctx, size: size)
            drawGraticule(ctx, size: size)
            drawChannel(ctx, size: size, bins: histogram.luma, color: Style.luma)
            drawChannel(ctx, size: size, bins: histogram.red, color: Style.red)
            drawChannel(ctx, size: size, bins: histogram.green, color: Style.green)
            drawChannel(ctx, size: size, bins: histogram.blue, color: Style.blue)
            drawBorder(ctx, size: size)
        }
        .frame(height: Style.height)
        .clipShape(RoundedRectangle(cornerRadius: Style.cornerRadius, style: .continuous))
    }

    // MARK: - Canvas drawing helpers

    private func drawBackground(_ ctx: GraphicsContext, size: CGSize) {
        ctx.fill(
            Path(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: Style.cornerRadius,
                style: .continuous),
            with: .color(Style.backgroundColor)
        )
    }

    private func drawGraticule(_ ctx: GraphicsContext, size: CGSize) {
        for i in 1...Style.gridLines {
            let y = size.height * CGFloat(i) / CGFloat(Style.gridLines + 1)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(Style.gridColor), lineWidth: 0.5)
        }
        // Vertical quarter-stop markers at 25%, 50%, 75%
        for i in 1...3 {
            let x = size.width * CGFloat(i) / 4.0
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(Style.gridColor), lineWidth: 0.5)
        }
    }

    private func drawChannel(
        _ ctx: GraphicsContext,
        size: CGSize,
        bins: [Float],
        color: Color
    ) {
        guard bins.count == HistogramData.binCount else { return }
        let binCount = CGFloat(HistogramData.binCount)
        let binWidth = size.width / binCount

        // Build the filled area path
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: size.height))
        for i in 0..<HistogramData.binCount {
            let x = CGFloat(i) * binWidth
            let y = size.height * (1.0 - CGFloat(bins[i]))
            if i == 0 {
                fillPath.addLine(to: CGPoint(x: x, y: y))
            } else {
                fillPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
        fillPath.closeSubpath()

        ctx.fill(fillPath, with: .color(color.opacity(Style.fillOpacity)))

        // Build the stroke path (top edge only)
        var strokePath = Path()
        for i in 0..<HistogramData.binCount {
            let x = CGFloat(i) * binWidth + binWidth * 0.5
            let y = size.height * (1.0 - CGFloat(bins[i]))
            if i == 0 {
                strokePath.move(to: CGPoint(x: x, y: y))
            } else {
                strokePath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(strokePath, with: .color(color), lineWidth: Style.strokeWidth)
    }

    private func drawBorder(_ ctx: GraphicsContext, size: CGSize) {
        ctx.stroke(
            Path(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: Style.cornerRadius,
                style: .continuous),
            with: .color(Style.borderColor),
            lineWidth: 0.5
        )
    }
}
