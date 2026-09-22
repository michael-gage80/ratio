import SwiftUI

/// Chips and tags — screens/00-design-system/02-components.png, cell 02.
/// Pills classify content (module, "why it matters" topic, skill). Square-cornered
/// tags state a status. Every status tag pairs a colour with a word — colour is never
/// the only signal (Accessibility: "Colour is never alone").
public enum RatioTagStyle {
    case outline               // Bordered, ink text — module chips, "SOON", "RATIO PLUS"
    case filledDark            // Solid ink/oxblood fill, paper text — the active/selected tag
    case tint(Color)           // Tinted background, ink text — "LAW MOVED", "UNDER REVIEW"
}

public struct RatioTag: View {
    private let text: String
    private let icon: String?
    private let style: RatioTagStyle

    public init(_ text: String, icon: String? = nil, style: RatioTagStyle = .outline) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(text)
        }
        .ratioFont(.monoLabel)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
        .overlay {
            if case .outline = style {
                Capsule().strokeBorder(Color.ratioRule, lineWidth: 1)
            }
        }
    }

    private var background: Color {
        switch style {
        case .outline: return .clear
        case .filledDark: return .ratioInk
        case .tint(let c): return c.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch style {
        case .outline: return .ratioInk
        case .filledDark: return .ratioParchment
        case .tint(let c): return c
        }
    }
}
