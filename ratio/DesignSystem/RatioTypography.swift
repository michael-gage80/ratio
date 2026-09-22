import SwiftUI

/// Ratio's three type families, mapped to Dynamic Type. See
/// screens/00-design-system/01-foundations.png ("Typography") for the source scale.
///
/// - Serif (Newsreader): reading and headings. Its italic cut is used for emphasis and
///   case names. Registered as two static optical-size cuts — "Text" (opsz 16, for
///   everything up to headings) and "Display" (opsz 72, for the largest headline and
///   law-report sizes) — rather than the raw variable font, so sizing is exact without
///   depending on automatic-optical-size font matching.
/// - Mono (IBM Plex Mono): metadata, labels, citations and timers. Always used
///   uppercase with wide tracking for labels ("CRIME · MENS REA").
/// - Display accent (Newsreader Display, italic): case titles on law-report pages and
///   statute headers only — never for ordinary headings.
///
/// Dyslexia-friendly mode (PRD, Accessibility) swaps families 1 and 3 for Atkinson
/// Hyperlegible, with wider tracking and a shorter line length; family 2 (mono) is
/// unchanged. Call sites don't choose this — `.ratioFont(_:)` reads it from the
/// environment (`\.ratioDyslexiaFriendly`).
public enum RatioTextStyle: CaseIterable {
    case display        // Greeting-sized headline, e.g. "Good morning, Amara."
    case h1              // Lesson/section titles
    case h2               // Sub-section headings
    case h3                // Card/list headings
    case body               // Reading text
    case bodyEmphasis        // Inline emphasis within body text (case names, key terms)
    case small                // Secondary text, e.g. "Updated 4 lessons ago."
    case caption                // Fine print
    case monoLabel                // Uppercase tag/status labels, wide tracking
    case monoData                   // Citations, ratings, timers
    case displayAccent               // Law-report case titles / statute headers only
}

private struct RatioFontSpec {
    let size: CGFloat
    let lineHeightMultiple: CGFloat
    let trackingEm: CGFloat
    let weight: RatioFontWeight
    let italic: Bool
    let dynamicTypeAnchor: Font.TextStyle
    let uppercase: Bool
    let mono: Bool
}

/// Weights available across the two Newsreader optical cuts we ship (Text and
/// Display both have Regular + SemiBold; only Text also has Medium).
public enum RatioFontWeight {
    case regular, medium, semibold
}

public enum RatioTypography {
    /// The optical-size threshold above which headings switch from the Text cut
    /// (opsz 16) to the Display cut (opsz 72), matching Newsreader's own two stops.
    private static let displayCutThreshold: CGFloat = 24

    private static func spec(for style: RatioTextStyle) -> RatioFontSpec {
        switch style {
        case .display:
            return RatioFontSpec(size: 44, lineHeightMultiple: 1.05, trackingEm: -0.04, weight: .regular, italic: false, dynamicTypeAnchor: .largeTitle, uppercase: false, mono: false)
        case .h1:
            return RatioFontSpec(size: 34, lineHeightMultiple: 1.1, trackingEm: -0.03, weight: .regular, italic: false, dynamicTypeAnchor: .title, uppercase: false, mono: false)
        case .h2:
            return RatioFontSpec(size: 26, lineHeightMultiple: 1.15, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .title2, uppercase: false, mono: false)
        case .h3:
            return RatioFontSpec(size: 20, lineHeightMultiple: 1.3, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .title3, uppercase: false, mono: false)
        case .body:
            return RatioFontSpec(size: 17, lineHeightMultiple: 1.5, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .body, uppercase: false, mono: false)
        case .bodyEmphasis:
            return RatioFontSpec(size: 17, lineHeightMultiple: 1.5, trackingEm: 0, weight: .regular, italic: true, dynamicTypeAnchor: .body, uppercase: false, mono: false)
        case .small:
            return RatioFontSpec(size: 15, lineHeightMultiple: 1.4, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .subheadline, uppercase: false, mono: false)
        case .caption:
            return RatioFontSpec(size: 12, lineHeightMultiple: 1.3, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .caption, uppercase: false, mono: false)
        case .monoLabel:
            return RatioFontSpec(size: 11, lineHeightMultiple: 1.3, trackingEm: 0.14, weight: .medium, italic: false, dynamicTypeAnchor: .caption2, uppercase: true, mono: true)
        case .monoData:
            return RatioFontSpec(size: 12, lineHeightMultiple: 1.3, trackingEm: 0, weight: .regular, italic: false, dynamicTypeAnchor: .footnote, uppercase: false, mono: true)
        case .displayAccent:
            return RatioFontSpec(size: 40, lineHeightMultiple: 1.1, trackingEm: -0.02, weight: .regular, italic: true, dynamicTypeAnchor: .largeTitle, uppercase: false, mono: false)
        }
    }

    /// The font for a given style. `dyslexiaFriendly` swaps the serif/display families
    /// for Atkinson Hyperlegible; mono is unaffected.
    static func font(for style: RatioTextStyle, dyslexiaFriendly: Bool) -> Font {
        let spec = spec(for: style)
        let name = fontName(spec: spec, dyslexiaFriendly: dyslexiaFriendly)
        return .custom(name, size: spec.size, relativeTo: spec.dynamicTypeAnchor)
    }

    static func tracking(for style: RatioTextStyle) -> CGFloat {
        spec(for: style).trackingEm * spec(for: style).size
    }

    /// Approximates the design board's line-height multiple as SwiftUI's additive
    /// `lineSpacing` (extra space between lines, not a multiplier).
    static func lineSpacing(for style: RatioTextStyle) -> CGFloat {
        let spec = spec(for: style)
        return spec.size * (spec.lineHeightMultiple - 1.0)
    }

    static func isUppercase(_ style: RatioTextStyle) -> Bool {
        spec(for: style).uppercase
    }

    private static func fontName(spec: RatioFontSpec, dyslexiaFriendly: Bool) -> String {
        if spec.mono {
            switch spec.weight {
            case .medium: return "IBMPlexMono-Medium"
            default: return spec.italic ? "IBMPlexMono-Italic" : "IBMPlexMono-Regular"
            }
        }
        if dyslexiaFriendly {
            switch (spec.weight, spec.italic) {
            case (.semibold, true), (.medium, true): return "Atkinson Hyperlegible Bold Italic"
            case (.semibold, false), (.medium, false): return "Atkinson Hyperlegible Bold"
            case (_, true): return "Atkinson Hyperlegible Italic"
            case (_, false): return "Atkinson Hyperlegible"
            }
        }
        let useDisplayCut = spec.size >= displayCutThreshold
        if useDisplayCut {
            switch (spec.weight, spec.italic) {
            case (_, true): return "NewsreaderDisplay-Italic"
            case (.semibold, false), (.medium, false): return "NewsreaderDisplay-SemiBold"
            default: return "NewsreaderDisplay-Regular"
            }
        } else {
            switch (spec.weight, spec.italic) {
            case (_, true): return "NewsreaderText-Italic"
            case (.semibold, false): return "NewsreaderText-SemiBold"
            case (.medium, false): return "NewsreaderText-Medium"
            default: return "NewsreaderText-Regular"
            }
        }
    }
}

// MARK: - Environment

private struct RatioDyslexiaFriendlyKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Mirrors Settings → Accessibility → "Dyslexia-friendly mode". Set once at the
    /// app root once Settings (Phase 15) exists; defaults to `false`.
    var ratioDyslexiaFriendly: Bool {
        get { self[RatioDyslexiaFriendlyKey.self] }
        set { self[RatioDyslexiaFriendlyKey.self] = newValue }
    }
}

// MARK: - View modifier

private struct RatioFontModifier: ViewModifier {
    @Environment(\.ratioDyslexiaFriendly) private var dyslexiaFriendly
    let style: RatioTextStyle

    func body(content: Content) -> some View {
        content
            .font(RatioTypography.font(for: style, dyslexiaFriendly: dyslexiaFriendly))
            .tracking(RatioTypography.tracking(for: style))
            .lineSpacing(RatioTypography.lineSpacing(for: style))
            .textCase(RatioTypography.isUppercase(style) ? .uppercase : nil)
    }
}

public extension View {
    /// Applies one of Ratio's type styles (font, tracking, line spacing, case),
    /// honouring Dynamic Type and dyslexia-friendly mode automatically.
    func ratioFont(_ style: RatioTextStyle) -> some View {
        modifier(RatioFontModifier(style: style))
    }
}
