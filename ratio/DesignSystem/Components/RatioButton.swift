import SwiftUI

/// Buttons — screens/00-design-system/02-components.png, cell 01.
/// 56pt tall, 18pt corner radius. One commit per screen (the plan never shows two
/// primary buttons at once). Secondary flips from ink-on-light to paper-fill on dark.
public enum RatioButtonStyle {
    case primary     // Oxblood fill, paper text — the one commit action ("Begin — R v Woollin")
    case secondary   // Ink fill (flips to paper fill on dark), paper/ink text
    case tertiary    // Paper fill, rule-coloured border, ink text ("Review my one miss")
    case link        // No fill, oxblood text with a trailing arrow ("Read the full report →")
}

public struct RatioButton: View {
    private let title: String
    private let style: RatioButtonStyle
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, style: RatioButtonStyle = .primary, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if style == .link {
                    Image(systemName: "arrow.right")
                }
            }
            .ratioFont(.h3)
            .frame(maxWidth: style == .link ? nil : .infinity)
            .frame(height: style == .link ? nil : 56)
            .foregroundStyle(foreground)
        }
        .background {
            if style != .link {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
                    .overlay {
                        if style == .tertiary {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.ratioRule, lineWidth: 1)
                        }
                    }
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
        .accessibilityAddTraits(.isButton)
    }

    private var background: Color {
        switch style {
        case .primary: return .ratioCommitFill
        case .secondary: return .ratioInk
        case .tertiary: return .ratioPaper
        case .link: return .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: return .ratioOnInk
        case .secondary: return .ratioParchment
        case .tertiary: return .ratioInk
        case .link: return .ratioOxblood
        }
    }
}
