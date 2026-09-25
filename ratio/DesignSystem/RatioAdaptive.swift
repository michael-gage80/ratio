import GameController
import SwiftUI

// iPad layouts follow the *window's* width, never the device: an iPad app in a third of
// the screen gets the iPhone layout, an iPhone never gets the iPad one.

/// How much room a screen has. Compact is the iPhone layout, unchanged.
nonisolated enum RatioWidthClass: Comparable, Sendable {
    case compact   // < 700pt
    case regular   // 700–1100pt: two columns
    case wide      // > 1100pt: two or three columns, a margin in lectures

    init(width: CGFloat) {
        self = width < 700 ? .compact : width < 1100 ? .regular : .wide
    }

    var isCompact: Bool { self == .compact }
}

private struct RatioWidthKey: EnvironmentKey {
    static let defaultValue = RatioWidthClass.compact
}

extension EnvironmentValues {
    /// Set by `.ratioMeasuresWidth()` on each screen's root.
    var ratioWidth: RatioWidthClass {
        get { self[RatioWidthKey.self] }
        set { self[RatioWidthKey.self] = newValue }
    }
}

private struct WidthMeasure: ViewModifier {
    @State private var width = RatioWidthClass.compact

    func body(content: Content) -> some View {
        content
            .environment(\.ratioWidth, width)
            .onGeometryChange(for: RatioWidthClass.self) { RatioWidthClass(width: $0.size.width) } action: { width = $0 }
    }
}

extension View {
    /// Measures the space this screen has and tells everything inside it (`\.ratioWidth`).
    /// Apply at each screen or sheet root.
    func ratioMeasuresWidth() -> some View {
        modifier(WidthMeasure())
    }

    /// Caps reading text at about 65 characters, centred in wide spaces.
    func ratioReadableWidth(_ maxWidth: CGFloat = 680) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

/// Two columns side by side when there's room (leading takes `fraction` of the width),
/// stacked otherwise. Both columns align to the top.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    var fraction: CGFloat = 0.6
    var spacing: CGFloat = RatioSpace.m
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    @Environment(\.ratioWidth) private var width

    var body: some View {
        if width.isCompact {
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                leading
                trailing
            }
        } else {
            ColumnsLayout(fraction: fraction, spacing: spacing) {
                VStack(alignment: .leading, spacing: RatioSpace.s) { leading }
                VStack(alignment: .leading, spacing: RatioSpace.s) { trailing }
            }
        }
    }
}

/// Lays out two subviews as columns: the first gets `fraction` of the width, the second
/// the rest; the height is the taller of the two.
struct ColumnsLayout: Layout {
    var fraction: CGFloat
    var spacing: CGFloat

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let first = ((total - spacing) * fraction).rounded(.down)
        return (first, max(0, total - spacing - first))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 900
        let (a, b) = widths(total)
        let heights = zip(subviews, [a, b]).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        return CGSize(width: total, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (a, b) = widths(bounds.width)
        var x = bounds.minX
        for (subview, width) in zip(subviews, [a, b]) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }
}

// MARK: - Hardware keyboard

/// Whether a hardware keyboard is connected, so key hints only show when they're useful.
@Observable
final class KeyboardMonitor {
    static let shared = KeyboardMonitor()
    private(set) var isConnected = KeyboardMonitor.keyboardPresent
    /// "-noKeyHints" (debug screenshots) hides them even with the Mac's keyboard attached.
    private static var keyboardPresent: Bool {
        GCKeyboard.coalesced != nil && !ProcessInfo.processInfo.arguments.contains("-noKeyHints")
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isConnected = Self.keyboardPresent }
            },
            center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isConnected = Self.keyboardPresent }
            },
        ]
    }
}

/// "⌘↩ LOCK IT IN" — a key cap and what it does, shown only with a hardware keyboard.
struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        if KeyboardMonitor.shared.isConnected {
            HStack(spacing: RatioSpace.xs) {
                Text(keys)
                    .ratioFont(.monoData)
                    .padding(.horizontal, RatioSpace.xs)
                    .padding(.vertical, RatioSpace.xxs)
                    .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.ratioRule) }
                Text(label).ratioFont(.monoLabel)
            }
            .foregroundStyle(Color.ratioInk2)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Context menus

private struct OptionalContextMenu<MenuItems: View>: ViewModifier {
    let enabled: Bool
    @ViewBuilder let items: MenuItems

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { items }
        } else {
            content
        }
    }
}

extension View {
    /// A context menu only where it doesn't clash with a long-press action (iPad, where
    /// iPhone rows use long press for something else).
    func ratioContextMenu(enabled: Bool, @ViewBuilder _ items: () -> some View) -> some View {
        modifier(OptionalContextMenu(enabled: enabled, items: items))
    }
}
