import Network
import SwiftUI

// The layout rules every screen follows (Phase 17 polish):
// - Spacing on an 8pt grid (4 for hairline nudges only).
// - Three corner radii, all continuous.
// - Solid paper for content; Liquid Glass only for floating chrome.
// - One page header, one empty state, one error state, one skeleton treatment.

/// Spacing on an 8pt grid. Screen margins are `m`; cards pad by `m`; gaps between cards
/// are `s`; gaps inside a card are `xs` or `s`.
enum RatioSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 16
    static let m: CGFloat = 24
    static let l: CGFloat = 32
    static let xl: CGFloat = 48
}

/// Corner radii: cards and blocks, inner panels and buttons, chips and small tiles.
enum RatioRadius {
    static let card: CGFloat = 24
    static let panel: CGFloat = 16
    static let chip: CGFloat = 10
}

/// One set of durations: quick for taps and toggles, gentle for things arriving.
enum RatioMotion {
    static let tap = Animation.snappy(duration: 0.2)
    static let reveal = Animation.easeInOut(duration: 0.35)
}

extension View {
    /// A solid content card: paper, a hairline rule, 24pt corners.
    func ratioCard(_ fill: Color = .ratioPaper, padding: CGFloat = RatioSpace.m, bordered: Bool = true) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous).strokeBorder(Color.ratioRule)
                }
            }
    }

    /// An inner panel (inside a card or a page section): sunk fill, 16pt corners.
    func ratioPanel(_ fill: Color = .ratioSunk, padding: CGFloat = RatioSpace.s) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
    }

    /// The parchment page every screen sits on.
    func ratioPage() -> some View {
        background(Color.ratioParchment.ignoresSafeArea())
            .foregroundStyle(Color.ratioInk)
    }

    /// Placeholder content shaped like the real thing while it loads, gently pulsing
    /// (still with Reduce Motion).
    func ratioSkeleton(_ active: Bool = true) -> some View {
        modifier(SkeletonModifier(active: active))
    }
}

private struct SkeletonModifier: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        if active {
            content
                .redacted(reason: .placeholder)
                .opacity(dim ? 0.45 : 0.8)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading")
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true }
                }
        } else {
            content
        }
    }
}

/// Feedback when a card or row is pressed: a slight dip (just a fade with Reduce Motion).
struct RatioPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(RatioMotion.tap, value: configuration.isPressed)
            // A pointer (trackpad or mouse on iPad) highlights it too.
            .hoverEffect(.highlight)
    }
}

extension ButtonStyle where Self == RatioPressStyle {
    static var ratioPress: RatioPressStyle { RatioPressStyle() }
}

/// The page header on every tab and full-screen page: an optional mono eyebrow, the
/// serif title with its oxblood full stop, an optional line under it, and icon buttons
/// on the title's first line.
struct RatioPageHeader<Trailing: View>: View {
    var eyebrow: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            if let eyebrow {
                Text(eyebrow).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                // A one-word display title shrinks to fit rather than break mid-word.
                Text("\(title)\(Text(".").foregroundStyle(Color.ratioOxblood))")
                    .ratioFont(.display)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(title)
                Spacer(minLength: 0)
                HStack(spacing: RatioSpace.xxs) { trailing }
            }
            if let subtitle {
                Text(subtitle).ratioFont(.small).foregroundStyle(Color.ratioInk2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, RatioSpace.xs)
    }
}

extension RatioPageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A 44pt icon button for page headers and toolbars.
struct RatioIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.ratioPress)
        .accessibilityLabel(label)
    }
}

/// Nothing here yet: a small engraving, one quiet sentence, and an action when there's
/// something to do about it.
struct RatioEmptyState: View {
    var art: RatioSpotArt = .openBook
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: RatioSpace.s) {
            art.view
                .frame(width: 88)
                .foregroundStyle(Color.ratioInk2)
                .accessibilityHidden(true)
            Text(message)
                .ratioFont(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                RatioButton(actionTitle, style: .link, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RatioSpace.l)
    }
}

/// Something failed to load: what happened, in plain words, and a way to try again.
struct RatioErrorState: View {
    var message = "That didn't load. Check your connection and try again."
    let retry: () -> Void

    var body: some View {
        VStack(spacing: RatioSpace.s) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(Color.ratioInk2)
                .accessibilityHidden(true)
            Text(message)
                .ratioFont(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: 320)
            RatioButton("Try again", style: .tertiary, action: retry)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, RatioSpace.l)
    }
}

/// Whether the phone has a connection, for the offline banner.
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "ratio.network"))
    }

    deinit { monitor.cancel() }
}

/// A slim banner while offline, saying what still works.
struct OfflineBanner: View {
    var body: some View {
        Label("Offline. Lessons still work; duels and boards need a connection.", systemImage: "wifi.slash")
            .ratioFont(.small)
            .padding(.horizontal, RatioSpace.s)
            .padding(.vertical, RatioSpace.xs)
            .ratioGlassCapsule()
            .overlay(Capsule().strokeBorder(Color.ratioRule))
            .padding(.horizontal, RatioSpace.s)
            .accessibilityAddTraits(.isStaticText)
    }
}
