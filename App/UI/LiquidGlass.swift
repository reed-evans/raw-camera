import SwiftUI

// OWNER: wt/controls-ui. Apple Liquid Glass (iOS 26+) surface helper with a
// material fallback that preserves the pre-glass look on earlier systems.

extension View {
    /// Backs the view with a Liquid Glass surface of the given shape. Before
    /// iOS 26 it falls back to the ultra-thin material + hairline border the
    /// app shipped with, so both paths read as the same design.
    ///
    /// The glass is rendered as a background layer rather than by wrapping the
    /// content in `glassEffect` directly: the effect view swallows touches on
    /// controls inside it, and glass nested inside glass is unsupported.
    /// Glass chrome for a small icon Button: the system glass button style on
    /// iOS 26, the flat tinted-circle chrome the app shipped with before.
    ///
    /// Buttons must get glass from the button style, not from a `liquidGlass`
    /// label background: a glassEffect nested inside another glass surface
    /// (the panel) swallows the button's taps — verified by
    /// ControlsPanelUITests on the iOS 26.5 simulator.
    @ViewBuilder
    func glassIconButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .tint(Color.white.opacity(0.1))
        } else {
            buttonStyle(.plain)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func liquidGlass(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            background(
                Color.clear.glassEffect(
                    interactive ? .regular.interactive() : .regular, in: shape))
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        }
    }
}
