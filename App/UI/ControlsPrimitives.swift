import SwiftUI

// OWNER: wt/controls-ui. Leaf widgets and formatters for the camera control
// surface, extracted from ControlsPanel.swift to keep each file focused.

// MARK: - Section scaffold

struct CamSection<C: View>: View {
    let label: String
    @ViewBuilder let content: C

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2).foregroundStyle(Color.white.opacity(0.45))
            content
        }.frame(minWidth: 90, alignment: .center)
    }
}

/// Read-only value shown beneath a section while that axis is in auto mode
/// (the device, not the user, is choosing the value).
struct AutoReadout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
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
            Text(title).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.5))
                .frame(width: 36, height: 26)
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

extension View {
    /// Scales a Slider down so it reads at `height` points tall — matching the
    /// monitor switches (18pt) by default — while staying `width` points wide.
    /// Keeps the drawer compact and the controls visually consistent.
    func compactSlider(width: CGFloat, height: CGFloat = 18) -> some View {
        let natural: CGFloat = 28  // approx intrinsic height of an iOS Slider
        let scale = height / natural
        return
            self
            .frame(width: width / scale)
            .scaleEffect(scale)
            .frame(width: width, height: height)
    }
}

struct MonRow: View {
    let label: String; @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.8)
                .foregroundStyle(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
                .frame(width: 36, alignment: .leading).animation(.easeOut(duration: 0.12), value: isOn)
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
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.8)
                .foregroundStyle(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.4))
                .frame(width: 36, alignment: .leading).animation(.easeOut(duration: 0.12), value: isOn)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(MiniToggleStyle())
        }
    }

    private var sliderReadout: some View {
        // In landscape the readout sits under the switch, so keep its width within
        // the section's 90pt column (slider + spacing + "100%") — otherwise the
        // column grows and widens the whole panel for no visual gain.
        HStack(spacing: 8) {
            Slider(value: $threshold, in: 0...1).tint(Color.white.opacity(0.7))
                .compactSlider(width: stacked ? 50 : 64)
            Text(String(format: "%.0f%%", threshold * 100))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65)).frame(width: 28, alignment: .leading)
        }
    }
}

struct MiniToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ZStack {
            Capsule().fill(on ? Color.white.opacity(0.9) : Color.white.opacity(0.15)).frame(width: 34, height: 18)
            Circle().fill(on ? Color.black : Color.white.opacity(0.6)).frame(width: 14, height: 14).offset(x: on ? 8 : -8)
        }
        .animation(.easeOut(duration: 0.14), value: on)
        .onTapGesture { configuration.isOn.toggle() }
    }
}
