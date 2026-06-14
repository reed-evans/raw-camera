import SwiftUI

// OWNER: wt/controls-ui. Leaf widgets and formatters for the camera control
// surface, extracted from ControlsPanel.swift to keep each file focused.

// MARK: - Shared knob geometry

/// One thumb size shared by every switch and slider in the control panel so the
/// knobs read at a single consistent dimension. A wide capsule (wider than tall).
enum ControlThumb {
    static let width: CGFloat = 28
    static let height: CGFloat = 20
    /// Track line thickness behind a slider knob.
    static let trackLine: CGFloat = 4
    /// Slider row height (vertical room around the knob).
    static let sliderHeight: CGFloat = 24
}

/// Blue-fill slider track with the shared capsule knob positioned at `fraction`
/// (0...1). Visual only — callers wrap it in a sized frame and attach the drag
/// gesture that drives `fraction`. Used by `FineSlider` and `CompactCapsuleSlider`
/// so both knobs are identical.
struct CapsuleSliderTrack: View {
    let fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - ControlThumb.width
            let x = ControlThumb.width / 2 + fraction * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(height: ControlThumb.trackLine)
                Capsule().fill(Color(.systemBlue))
                    .frame(width: max(ControlThumb.width / 2, x), height: ControlThumb.trackLine)
                Capsule().fill(Color.white)
                    .frame(width: ControlThumb.width, height: ControlThumb.height)
                    .position(x: x, y: geo.size.height / 2)
            }
        }
    }
}

// MARK: - Section scaffold

struct CamSection<C: View>: View {
    let label: String
    @ViewBuilder let content: C

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2).foregroundStyle(Color.white.opacity(0.45))
            content
        }.frame(minWidth: 96, alignment: .center)
    }
}

/// Read-only value shown beneath a section while that axis is in auto mode
/// (the device, not the user, is choosing the value).
struct AutoReadout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(1)
            .transition(.opacity)
    }
}

// MARK: - Value formatters

/// Compact shutter-speed label, e.g. `1/120` or `0.5s`.
func shutterLabel(_ seconds: Double) -> String {
    guard seconds > 0 else { return "—" }
    return seconds >= 1
        ? String(format: "%.1fs", seconds)
        : "1/\(Int((1.0 / seconds).rounded()))"
}

/// Signed tint label, e.g. `+4` or `-3`.
func tintLabel(_ tint: Float) -> String {
    let i = Int(tint.rounded())
    return i >= 0 ? "+\(i)" : "\(i)"
}

// MARK: - Controls

struct ModeSegment: View {
    @Binding var isManual: Bool
    let onDisable: () -> Void
    let onEnable: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segBtn("A", active: !isManual) { if isManual { onDisable(); isManual = false } }
            segBtn("M", active: isManual) { if !isManual { isManual = true; onEnable() } }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private func segBtn(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.5))
                .frame(width: 34, height: 24)
                .background(active ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }.buttonStyle(.plain).animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Float-typed manual-control slider. A thin adapter over `FineSlider` (the
/// grab-to-fine-tune slider); bridges Float values/ranges to its Double core.
struct FSlider: View {
    let label: String
    let range: ClosedRange<Float>
    @Binding var value: Float
    let format: (Float) -> String

    var body: some View {
        FineSlider(
            label: label,
            range: Double(range.lowerBound)...Double(range.upperBound),
            value: Binding(get: { Double(value) }, set: { value = Float($0) }),
            format: { format(Float($0)) }
        )
    }
}

/// Double-typed manual-control slider (e.g. shutter seconds). Adapter over
/// `FineSlider`.
struct DSlider: View {
    let label: String
    let range: ClosedRange<Double>
    @Binding var value: Double
    let format: (Double) -> String

    var body: some View {
        FineSlider(label: label, range: range, value: $value, format: format)
    }
}

/// A plain capsule-knob slider (no label, no fine-tune) for inline 0...1 values
/// like the zebra/peak thresholds. Shares `CapsuleSliderTrack`, so its knob
/// matches the switches and manual sliders exactly. Drag/tap sets the value at
/// the touch position.
struct CompactCapsuleSlider: View {
    @Binding var value: Float
    let width: CGFloat
    var range: ClosedRange<Float> = 0...1

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? CGFloat((value - range.lowerBound) / span) : 0
    }

    var body: some View {
        CapsuleSliderTrack(fraction: fraction)
            .frame(width: width, height: ControlThumb.sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let usable = max(width - ControlThumb.width, 1)
                    let raw = (g.location.x - ControlThumb.width / 2) / usable
                    let span = range.upperBound - range.lowerBound
                    value = range.lowerBound + min(max(Float(raw), 0), 1) * span
                }
            )
            .accessibilityElement()
            .accessibilityValue(String(format: "%.0f%%", value * 100))
            .accessibilityAdjustableAction { direction in
                let step = (range.upperBound - range.lowerBound) / 20
                switch direction {
                case .increment: value = min(value + step, range.upperBound)
                case .decrement: value = max(value - step, range.lowerBound)
                default: break
                }
            }
    }
}

struct MonRow: View {
    let label: String; @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.8)
                .foregroundStyle(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
                .frame(width: 46, alignment: .leading).animation(.easeOut(duration: 0.12), value: isOn)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(MiniToggleStyle())
        }
    }
}

/// A monitor toggle whose threshold slider reveals next to the switch
/// (ZEBRA/PEAK). Beside it in portrait; stacked beneath it in landscape so the
/// rotated row of switches keeps a tidy line with the sliders under them.
struct ThreshToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    @Binding var threshold: Float
    var stacked = false

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    switchRow
                    if isOn { sliderReadout }
                }
            } else {
                HStack(spacing: 8) {
                    switchRow
                    if isOn { sliderReadout }
                }
            }
        }
        .transition(.opacity)
    }

    private var switchRow: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.8)
                .foregroundStyle(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
                .frame(width: 46, alignment: .leading).animation(.easeOut(duration: 0.12), value: isOn)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(MiniToggleStyle())
        }
    }

    private var sliderReadout: some View {
        // In landscape the readout sits under the switch, so keep its width within
        // the section's 90pt column (slider + spacing + "100%") — otherwise the
        // column grows and widens the whole panel for no visual gain.
        HStack(spacing: 8) {
            CompactCapsuleSlider(value: $threshold, width: stacked ? 50 : 64)
            Text(String(format: "%.0f%%", threshold * 100))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65)).frame(width: 32, alignment: .leading)
        }
    }
}

struct MiniToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ZStack {
            // System-switch look: green track when on, gray when off, with the
            // shared capsule thumb kept at an even 2pt inset on every side —
            // (24-20)/2 vertically, and 42/2 - 14 - 5 = 2 at the active end.
            Capsule()
                .fill(on ? Color(.systemGreen) : Color.white.opacity(0.2))
                .frame(width: 42, height: 24)
            Capsule()
                .fill(Color.white)
                .frame(width: ControlThumb.width, height: ControlThumb.height)
                .offset(x: on ? 5 : -5)
        }
        .animation(.easeOut(duration: 0.16), value: on)
        .onTapGesture { configuration.isOn.toggle() }
    }
}
