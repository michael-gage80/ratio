import SwiftUI

/// Liquid Glass treatment for the tab bar, top bars, the duel scoreboard, sheets,
/// floating buttons, and Today cards (PRD: "Design system, brand and icons" →
/// "Liquid Glass"). Falls back to a solid paper surface automatically when Reduce
/// Transparency is on, and can be forced to solid from a hidden debug toggle so both
/// treatments can be compared on-device — the PRD flags that glass over the paper
/// background "needs legibility testing in both themes" and may need to fall back.
private struct RatioGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("debug.forceGlassOff") private var debugForceSolid = false

    let shape: S
    let tint: Color?

    func body(content: Content) -> some View {
        if reduceTransparency || debugForceSolid {
            content.background(Color.ratioPaper, in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            content.background(Color.ratioPaper, in: shape)
        }
    }
}

public extension View {
    /// Applies the glass treatment in an arbitrary shape.
    func ratioGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(RatioGlassModifier(shape: shape, tint: tint))
    }

    /// Glass treatment for a card — the default shape used on Today.
    func ratioGlassCard(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        ratioGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint)
    }

    /// Glass treatment for pill-shaped controls (tab bar, floating buttons).
    func ratioGlassCapsule(tint: Color? = nil) -> some View {
        ratioGlass(in: Capsule(), tint: tint)
    }
}

/// A debug-only toggle for comparing glass vs. the solid-paper fallback on-device.
/// Not shown in the shipping app; wired into Settings → Appearance once that screen
/// exists (Phase 15), which will drive the same `debug.forceGlassOff` default.
public struct RatioGlassDebugToggle: View {
    @AppStorage("debug.forceGlassOff") private var debugForceSolid = false

    public init() {}

    public var body: some View {
        Toggle("Force solid cards (debug)", isOn: $debugForceSolid)
    }
}
