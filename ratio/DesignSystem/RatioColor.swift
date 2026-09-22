import SwiftUI

/// Ratio's colour tokens — see screens/00-design-system/01-foundations.png and the
/// PRD's "Design system, brand and icons" section.
///
/// Each token is an asset-catalog colour set with a light and dark appearance, so
/// `Color.ratio*` automatically follows the system appearance. Dark mode follows the
/// PRD's rule literally: "dark mode inverts ink and parchment" (each token's *role*
/// stays the same; the ink/parchment *values* swap), and oxblood/verdigris are
/// lightened in dark mode to keep 4.5:1 contrast against the dark background.
public extension Color {
    /// Main text, primary buttons, dark surfaces (light: #1D1B18 · dark: parchment's tone).
    static let ratioInk = Color("Ink", bundle: .main)

    /// App background (light: #F3F0E9 · dark: ink's tone).
    static let ratioParchment = Color("Parchment", bundle: .main)

    /// Cards and reading surfaces (light: #FDFCF8 · dark: a lifted near-black).
    static let ratioPaper = Color("Paper", bundle: .main)

    /// Accent, key terms, case names, the main call to action (light: #9B2A24 ·
    /// dark: lightened to ≥4.5:1 against the dark background).
    static let ratioOxblood = Color("Oxblood", bundle: .main)

    /// Correct answers and "secure" states only — never a general-purpose accent
    /// (light: #1F7A4D · dark: lightened to ≥4.5:1).
    static let ratioVerdigris = Color("Verdigris", bundle: .main)

    /// Dividers and outlines (light: #D9D4CA · dark: a subtle lift off ink).
    static let ratioRule = Color("Rule", bundle: .main)

    /// Text field / input boundary (#8C857A both appearances — meets the 3:1 WCAG
    /// 1.4.11 non-text contrast requirement against both paper surfaces). The plain
    /// `rule` hairline is for dividers only, never input boundaries.
    static let ratioInputBorder = Color("InputBorder", bundle: .main)
}
