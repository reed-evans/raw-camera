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
    @State var size: CGSize = .zero

    private var isLandscape: Bool { abs(angle.degrees) == 90 }

    /// Panel corner radius. Sized to read as concentric with the phone's
    /// screen corner (~55pt) given the 12pt inset the panel sits at — the
    /// rounded corner then runs parallel to, and safely inside, the display's
    /// curve instead of being clipped by it (matches the system dock).
    static let cornerRadius: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            if model.showSettings {
                settingsDrawer
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            commandBar
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .liquidGlass(in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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
                .font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
                .transition(.opacity.combined(with: .move(edge: .leading)))
        } else {
            Text(model.preferProRAW && model.isProRAWAvailable ? "ProRAW" : "RAW")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
        }
        .glassIconButton()
        .accessibilityLabel(model.showSettings ? "Hide settings" : "Show settings")
    }

    /// Settings drawer: one horizontal row of compact sections that sizes to its
    /// content (no full-height fills), shown only when expanded.
    private var settingsDrawer: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                if isLandscape {
                    // Rotated stack: measure the unrotated size, then transpose
                    // the frame so the rotated column occupies the right bounds.
                    // Padding sits inside the rotation, so after the 90° turn the
                    // vertical inset becomes the row-end buffer and the horizontal
                    // inset pads the drawer's thickness edges.
                    VStack(spacing: 20) {
                        drawerSections
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .facingUser(angle)
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: {
                        size = $0
                    }
                    .frame(width: size.height, height: size.width)
                } else {
                    // Portrait: natural-width sections in a padded, scrollable row.
                    HStack(alignment: .top, spacing: 24) {
                        drawerSections
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                }
            }
            Divider().overlay(Color.white.opacity(0.12))
        }
    }

    @ViewBuilder private var drawerSections: some View {
        Group {
            ExposureSection(model: model)
            WhiteBalanceSection(model: model)
            FocusSection(model: model)
            AspectSection(model: model)
            MonitoringSection(model: model, isLandscape: isLandscape)
            FormatSection(model: model)
            CaptureSection(model: model)
        }
    }
}

private struct ShutterButton: View {
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        // Glass must come from the button style, never a label background —
        // a glassEffect nested inside the panel's glass swallows the tap
        // (see glassIconButton in LiquidGlass.swift).
        if #available(iOS 26.0, *) {
            Button(action: action) { disc.padding(0) }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Color.white.opacity(0.15))
                .clipShape(Circle())
                .disabled(!isRunning).opacity(isRunning ? 1.0 : 0.45)
        } else {
            Button(action: action) {
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 3)
                        .frame(width: 52, height: 52)
                    disc
                }
            }
            .buttonStyle(ShutterButtonStyle())
            .disabled(!isRunning).opacity(isRunning ? 1.0 : 0.45)
        }
    }

    /// The white capture disc inside the ring.
    private var disc: some View {
        Circle().fill(isRunning ? Color.white : Color.white.opacity(0.25))
            .frame(width: 42, height: 42)
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
                VStack(spacing: 6) {
                    FSlider(
                        label: "ISO", range: isoRange,
                        value: Binding(
                            get: { model.iso },
                            set: { model.setManualExposure(iso: $0, shutterSeconds: model.shutterSeconds) }),
                        format: { "ISO \(Int($0.rounded()))" })
                    DSlider(
                        label: "SS", range: shutterRange,
                        value: Binding(
                            get: { model.shutterSeconds },
                            set: { model.setManualExposure(iso: model.iso, shutterSeconds: $0) }),
                        format: { shutterLabel($0) })
                }.transition(.opacity.combined(with: .offset(y: 4)))
            } else {
                AutoReadout(text: "ISO \(Int(model.iso.rounded())) · \(shutterLabel(model.shutterSeconds))")
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
                VStack(spacing: 6) {
                    FSlider(
                        label: "K", range: CameraModel.temperatureRange,
                        value: Binding(
                            get: { model.whiteBalanceTemperature },
                            set: { model.setWhiteBalance(temperature: $0, tint: model.whiteBalanceTint) }),
                        format: { "\(Int($0.rounded()))K" })
                    FSlider(
                        label: "TINT", range: CameraModel.tintRange,
                        value: Binding(
                            get: { model.whiteBalanceTint },
                            set: { model.setWhiteBalance(temperature: model.whiteBalanceTemperature, tint: $0) }),
                        format: { tintLabel($0) })
                }.transition(.opacity.combined(with: .offset(y: 4)))
            } else {
                AutoReadout(text: "\(Int(model.whiteBalanceTemperature.rounded()))K \(tintLabel(model.whiteBalanceTint))")
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
                    format: { String(format: "%.2f", $0) }
                )
                .transition(.opacity.combined(with: .offset(y: 4)))
            } else {
                AutoReadout(text: "AF \(String(format: "%.2f", model.focusLensPosition))")
            }
        }.animation(.easeInOut(duration: 0.18), value: model.isManualFocus)
    }
}

private struct MonitoringSection: View {
    @Bindable var model: CameraModel
    var isLandscape = false

    var body: some View {
        CamSection(label: "MONITOR") {
            VStack(alignment: .leading, spacing: 8) {
                MonRow(label: "HIST", isOn: $model.histogramEnabled)
                MonRow(label: "LEVEL", isOn: $model.levelGuideEnabled)
                MonRow(label: "ZOOM", isOn: $model.showZoomSlider)
                // ZEBRA/PEAK sit at the bottom; their threshold slider reveals
                // beside the switch in portrait, stacked beneath it in landscape.
                ThreshToggleRow(
                    label: "ZEBRA", isOn: $model.zebraEnabled, threshold: $model.zebraThreshold,
                    stacked: isLandscape)
                ThreshToggleRow(
                    label: "PEAK", isOn: $model.focusPeakingEnabled, threshold: $model.focusPeakingThreshold,
                    stacked: isLandscape)
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
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(proRawActive ? Color.black : Color.white.opacity(0.5))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(proRawActive ? Color.white : Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .animation(.easeOut(duration: 0.15), value: proRawActive)
                    Toggle("", isOn: Binding(get: { model.preferProRAW }, set: { model.setPreferProRAW($0) }))
                        .labelsHidden().toggleStyle(MiniToggleStyle())
                        .disabled(!model.isProRAWAvailable).opacity(model.isProRAWAvailable ? 1.0 : 0.35)
                }
                Text(model.isProRAWAvailable ? "available" : "unavailable")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
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

    /// The aspect ratios split into rows of two for a 2×2 grid. Plain nested
    /// stacks (not LazyVGrid) so the landscape drawer's measure/transpose pass
    /// stays predictable.
    private var rows: [[CameraAspectRatio]] {
        let all = CameraAspectRatio.allCases
        return stride(from: 0, to: all.count, by: 2).map { Array(all[$0..<min($0 + 2, all.count)]) }
    }

    var body: some View {
        CamSection(label: "RATIO") {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(rows[row]) { ratio in
                            ratioButton(ratio)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ratioButton(_ ratio: CameraAspectRatio) -> some View {
        let active = model.aspectRatio == ratio
        Button {
            model.aspectRatio = ratio
        } label: {
            Text(ratio.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? .black : .white.opacity(0.5))
                .frame(width: 42, height: 24)
                .background(
                    active ? Color.white : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// Previews live in ControlsPanelPreviews.swift (keeps this file under the length cap).
