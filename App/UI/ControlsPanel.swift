import CameraCore
import SwiftUI

// OWNER: wt/controls-ui. Dark-luxury editorial camera control surface.

// MARK: - ControlsPanel

/// Compact, collapsible camera control surface. A slim command bar (status ·
/// shutter · settings toggle) stays docked at the bottom while shooting; the full
/// settings slide up on demand and tuck away again, keeping the preview clear.
struct ControlsPanel: View {
    @Bindable var model: CameraModel
    /// Physical-orientation rotation applied to the controls (0° in portrait).
    var angle: Angle = .zero

    var body: some View {
        VStack(spacing: 0) {
            if model.showSettings {
                settingsDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            commandBar
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: -4)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: model.showSettings)
    }

    /// Slim, always-docked bar: status (left) · shutter (center) · settings toggle (right).
    private var commandBar: some View {
        HStack(spacing: 14) {
            statusChip.facingUser(angle).frame(maxWidth: .infinity, alignment: .leading)
            ShutterButton(isRunning: model.isSessionRunning, action: model.capturePhoto)
            settingsToggle.facingUser(angle).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var statusChip: some View {
        if let err = model.lastCaptureError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.red).lineLimit(1)
                .transition(.opacity.combined(with: .move(edge: .leading)))
        } else {
            Text(model.preferProRAW && model.isProRAWAvailable ? "ProRAW" : "RAW")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private var settingsToggle: some View {
        Button {
            model.showSettings.toggle()
        } label: {
            Image(systemName: model.showSettings ? "chevron.down" : "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.showSettings ? "Hide settings" : "Show settings")
    }

    /// Settings drawer: one horizontal row of compact sections that sizes to its
    /// content (no full-height fills), shown only when expanded.
    private var settingsDrawer: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    Group {
                        ExposureSection(model: model)
                        WhiteBalanceSection(model: model)
                        FocusSection(model: model)
                        AspectSection(model: model)
                        MonitoringSection(model: model)
                        FormatSection(model: model)
                        CaptureSection(model: model)
                    }
                    .facingUser(angle)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            Divider().overlay(Color.white.opacity(0.12))
        }
    }
}

private struct ShutterButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 3).frame(width: 52, height: 52)
                Circle().fill(isRunning ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 42, height: 42)
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!isRunning).opacity(isRunning ? 1.0 : 0.45)
    }
}

private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ExposureSection: View {
    @Bindable var model: CameraModel

    private var isoRange: ClosedRange<Float> {
        let lo = model.exposureLimits.minISO, hi = model.exposureLimits.maxISO
        return hi > lo ? lo...hi : 50...3200
    }
    private var shutterRange: ClosedRange<Double> {
        let lo = model.exposureLimits.minShutterSeconds, hi = model.exposureLimits.maxShutterSeconds
        return hi > lo ? lo...hi : (1.0 / 8000)...(30.0)
    }

    var body: some View {
        CamSection(label: "EXPOSURE") {
            ModeSegment(
                isManual: $model.isManualExposure,
                onDisable: model.enableAutoExposure,
                onEnable: { model.setManualExposure(iso: model.iso, shutterSeconds: model.shutterSeconds) }
            )
            if model.isManualExposure {
                VStack(spacing: 8) {
                    FSlider(
                        label: "ISO", range: isoRange,
                        value: Binding(
                            get: { model.iso },
                            set: { model.setManualExposure(iso: $0, shutterSeconds: model.shutterSeconds) }),
                        display: "ISO \(Int(model.iso.rounded()))")
                    DSlider(
                        label: "SS", range: shutterRange,
                        value: Binding(
                            get: { model.shutterSeconds },
                            set: { model.setManualExposure(iso: model.iso, shutterSeconds: $0) }),
                        display: model.shutterSeconds >= 1
                            ? String(format: "%.1fs", model.shutterSeconds)
                            : "1/\(Int((1.0 / model.shutterSeconds).rounded()))")
                }.transition(.opacity.combined(with: .offset(y: 4)))
            }
        }.animation(.easeInOut(duration: 0.18), value: model.isManualExposure)
    }
}

private struct WhiteBalanceSection: View {
    @Bindable var model: CameraModel

    var body: some View {
        CamSection(label: "WHITE BAL") {
            ModeSegment(
                isManual: $model.isManualWhiteBalance,
                onDisable: model.enableAutoWhiteBalance,
                onEnable: { model.setWhiteBalance(temperature: model.whiteBalanceTemperature, tint: model.whiteBalanceTint) }
            )
            if model.isManualWhiteBalance {
                VStack(spacing: 8) {
                    FSlider(
                        label: "K", range: CameraModel.temperatureRange,
                        value: Binding(
                            get: { model.whiteBalanceTemperature },
                            set: { model.setWhiteBalance(temperature: $0, tint: model.whiteBalanceTint) }),
                        display: "\(Int(model.whiteBalanceTemperature.rounded()))K")
                    FSlider(
                        label: "TINT", range: CameraModel.tintRange,
                        value: Binding(
                            get: { model.whiteBalanceTint },
                            set: { model.setWhiteBalance(temperature: model.whiteBalanceTemperature, tint: $0) }),
                        display: {
                            let i = Int(model.whiteBalanceTint.rounded()); return i >= 0 ? "+\(i)" : "\(i)"
                        }())
                }.transition(.opacity.combined(with: .offset(y: 4)))
            }
        }.animation(.easeInOut(duration: 0.18), value: model.isManualWhiteBalance)
    }
}

private struct FocusSection: View {
    @Bindable var model: CameraModel

    var body: some View {
        CamSection(label: "FOCUS") {
            ModeSegment(
                isManual: $model.isManualFocus,
                onDisable: model.enableAutoFocus,
                onEnable: { model.setFocus(lensPosition: model.focusLensPosition) }
            )
            if model.isManualFocus {
                FSlider(
                    label: "MF", range: CameraModel.lensPositionRange,
                    value: Binding(get: { model.focusLensPosition }, set: { model.setFocus(lensPosition: $0) }),
                    display: String(format: "%.2f", model.focusLensPosition)
                )
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }.animation(.easeInOut(duration: 0.18), value: model.isManualFocus)
    }
}

private struct MonitoringSection: View {
    @Bindable var model: CameraModel

    var body: some View {
        CamSection(label: "MONITOR") {
            VStack(spacing: 8) {
                MonRow(label: "ZEBRA", isOn: $model.zebraEnabled)
                if model.zebraEnabled {
                    ThreshRow(value: $model.zebraThreshold).transition(.opacity.combined(with: .offset(y: 4)))
                }
                MonRow(label: "PEAK", isOn: $model.focusPeakingEnabled)
                if model.focusPeakingEnabled {
                    ThreshRow(value: $model.focusPeakingThreshold).transition(.opacity.combined(with: .offset(y: 4)))
                }
                MonRow(label: "HIST", isOn: $model.histogramEnabled)
                MonRow(label: "LEVEL", isOn: $model.levelGuideEnabled)
                MonRow(label: "ZOOM", isOn: $model.showZoomSlider)
            }
            .animation(.easeInOut(duration: 0.18), value: model.zebraEnabled)
            .animation(.easeInOut(duration: 0.18), value: model.focusPeakingEnabled)
        }
    }
}

private struct FormatSection: View {
    @Bindable var model: CameraModel
    private var proRawActive: Bool { model.preferProRAW && model.isProRAWAvailable }

    var body: some View {
        CamSection(label: "FORMAT") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("ProRAW")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(proRawActive ? Color.black : Color.white.opacity(0.5))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(proRawActive ? Color.white : Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .animation(.easeOut(duration: 0.15), value: proRawActive)
                    Toggle("", isOn: Binding(get: { model.preferProRAW }, set: { model.setPreferProRAW($0) }))
                        .labelsHidden().toggleStyle(MiniToggleStyle())
                        .disabled(!model.isProRAWAvailable).opacity(model.isProRAWAvailable ? 1.0 : 0.35)
                }
                Text(model.isProRAWAvailable ? "available" : "unavailable")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.isProRAWAvailable ? Color.green.opacity(0.8) : Color.white.opacity(0.35))
            }
        }
    }
}

private struct CaptureSection: View {
    @Bindable var model: CameraModel

    var body: some View {
        CamSection(label: "CAPTURE") {
            VStack(spacing: 8) {
                optionRow("48MP", value: $model.highRes48MP, available: model.is48MPAvailable)
                optionRow("BRKT", value: $model.rawBracketing, available: model.isRAWBracketingAvailable)
                optionRow("10BIT", value: $model.hdr10Bit, available: model.is10BitHDRAvailable)
                optionRow("MAX Q", value: $model.maxQuality, available: true)
            }
        }
    }

    /// A MonRow that pushes the combined capture options on change and dims
    /// when the device doesn't support the option.
    private func optionRow(_ label: String, value: Binding<Bool>, available: Bool) -> some View {
        MonRow(
            label: label,
            isOn: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    model.pushCaptureOptions()
                }
            )
        )
        .disabled(!available)
        .opacity(available ? 1.0 : 0.35)
    }
}

private struct AspectSection: View {
    @Bindable var model: CameraModel

    var body: some View {
        CamSection(label: "RATIO") {
            HStack(spacing: 4) {
                ForEach(CameraAspectRatio.allCases) { ratio in
                    Button {
                        model.aspectRatio = ratio
                    } label: {
                        Text(ratio.label)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(model.aspectRatio == ratio ? .black : .white.opacity(0.5))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(
                                model.aspectRatio == ratio ? Color.white : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Primitives

private struct CamSection<C: View>: View {
    let label: String
    @ViewBuilder let content: C

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2).foregroundStyle(Color.white.opacity(0.45))
            content
        }.frame(minWidth: 90, alignment: .leading)
    }
}

private struct ModeSegment: View {
    @Binding var isManual: Bool
    let onDisable: () -> Void
    let onEnable: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segBtn("A", active: !isManual) { if isManual { onDisable(); isManual = false } }
            segBtn("M", active: isManual) { if !isManual { isManual = true; onEnable() } }
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private func segBtn(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.5))
                .frame(width: 28, height: 20)
                .background(active ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }.buttonStyle(.plain).animation(.easeOut(duration: 0.12), value: active)
    }
}

private struct FSlider: View {
    let label: String; let range: ClosedRange<Float>; @Binding var value: Float; let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text(display).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.85))
            }
            Slider(value: $value, in: range).tint(.white).frame(width: 120)
        }
    }
}

private struct DSlider: View {
    let label: String; let range: ClosedRange<Double>; @Binding var value: Double; let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text(display).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color.white.opacity(0.85))
            }
            Slider(value: $value, in: range).tint(.white).frame(width: 120)
        }
    }
}

private struct MonRow: View {
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

private struct ThreshRow: View {
    @Binding var value: Float

    var body: some View {
        HStack(spacing: 6) {
            Text("THR").font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35)).frame(width: 24, alignment: .leading)
            Slider(value: $value, in: 0...1).tint(Color.white.opacity(0.7)).frame(width: 80)
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.65)).frame(width: 28, alignment: .trailing)
        }
    }
}

private struct MiniToggleStyle: ToggleStyle {
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

// Previews live in ControlsPanelPreviews.swift (keeps this file under the length cap).
