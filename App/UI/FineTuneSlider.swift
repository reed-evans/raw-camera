import SwiftUI

// OWNER: wt/controls-ui. A compact slider that, when its knob is grabbed,
// drives a full-width fine-tuning overlay: the same value range is spread over
// a much longer finger travel, so dragging tunes the value ~3x more finely.
// The finger stays on the inline knob; the overlay is read-only feedback.

// MARK: - Shared session

/// The currently-tuning slider, or nil. A `FineSlider` publishes to this on
/// grab; `CameraScreen` renders the overlay from it; the slider clears it on
/// release.
@Observable
final class FineTuneSession {
    struct Active {
        let label: String
        let range: ClosedRange<Double>
        let format: (Double) -> String
        var value: Double

        /// 0...1 position of `value` within `range`.
        var fraction: Double {
            let span = range.upperBound - range.lowerBound
            return span > 0 ? (value - range.lowerBound) / span : 0
        }
    }

    var active: Active?

    func begin(_ a: Active) { active = a }
    func update(_ value: Double) { active?.value = value }
    func end() { active = nil }
}

// MARK: - Inline slider

struct FineSlider: View {
    let label: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    let format: (Double) -> String

    @Environment(FineTuneSession.self) private var session

    /// Fixed row width. The label row contains a Spacer, so the row MUST be
    /// width-pinned: the landscape drawer's transposed reservation frame
    /// proposes the panel's long dimension as width, and an unpinned row
    /// expands to fill it (blowing the panel up to the screen).
    static let rowWidth: CGFloat = 120
    private let trackHeight: CGFloat = 18
    // Knob is a horizontal capsule (wider than tall) to match the native
    // slider thumb the zoom/zebra sliders still use.
    private let knobWidth: CGFloat = 22
    private let knobHeight: CGFloat = 14
    /// Finger travel (points) that spans the full value range while tuning.
    /// ~3x the resting track width, so each drag is ~3x finer.
    private let fineTravel: CGFloat = 360

    @State private var dragStartValue: Double?

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text(format(value))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            track
        }
        .frame(width: Self.rowWidth)
    }

    private var track: some View {
        GeometryReader { geo in
            let usable = geo.size.width - knobWidth
            let x = knobWidth / 2 + fraction * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: 3)
                Capsule().fill(Color.white.opacity(0.85))
                    .frame(width: max(knobWidth / 2, x), height: 3)
                Capsule().fill(Color.white).frame(width: knobWidth, height: knobHeight)
                    .position(x: x, y: geo.size.height / 2)
            }
        }
        .frame(width: Self.rowWidth, height: trackHeight)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 100
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let start: Double
                if let s = dragStartValue {
                    start = s
                } else {
                    start = value
                    dragStartValue = value
                    session.begin(
                        .init(label: label, range: range, format: format, value: value))
                }
                let span = range.upperBound - range.lowerBound
                let delta = Double(g.translation.width / fineTravel) * span
                let next = min(max(start + delta, range.lowerBound), range.upperBound)
                value = next
                session.update(next)
            }
            .onEnded { _ in
                dragStartValue = nil
                session.end()
            }
    }
}

// MARK: - Full-width overlay

/// The big readout + wide track shown above the panel while a value is being
/// fine-tuned. Display-only: the finger drives the inline slider.
struct FineTuneOverlay: View {
    let tuning: FineTuneSession.Active

    var body: some View {
        VStack(spacing: 8) {
            Text(tuning.format(tuning.value))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .monospacedDigit()
            wideTrack
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 4)
    }

    private var wideTrack: some View {
        GeometryReader { geo in
            let knobWidth: CGFloat = 24
            let knobHeight: CGFloat = 14
            let usable = geo.size.width - knobWidth
            let x = knobWidth / 2 + CGFloat(tuning.fraction) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: 4)
                Capsule().fill(Color.white).frame(width: max(knobWidth / 2, x), height: 4)
                Capsule().fill(Color.white).frame(width: knobWidth, height: knobHeight)
                    .position(x: x, y: geo.size.height / 2)
            }
        }
        .frame(height: 18)
    }
}
