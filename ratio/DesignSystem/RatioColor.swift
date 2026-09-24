import SwiftUI

/// Ratio's colour tokens, taken directly from screens/00-design-system/01-foundations.png
/// ("Colour", light and dark · warm ink). The PRD's table gives starting values only;
/// the board is the finalised set. Each token is an asset-catalog colour with a light
/// and dark appearance, so it follows the system appearance automatically.
public extension Color {
    // MARK: Surfaces

    /// App background (#F3F0E9 · dark #1D1B18).
    static let ratioParchment = Color("Parchment", bundle: .main)
    /// Cards and reading surfaces (#FDFCF8 · dark #282521).
    static let ratioPaper = Color("Paper", bundle: .main)
    /// Inset panels and tracks (#EAE6DD · dark #332F2A).
    static let ratioSunk = Color("Sunk", bundle: .main)
    /// Hairline dividers only — inputs use `ratioInputBorder` (#D9D4CA · dark #3A3631).
    static let ratioRule = Color("Rule", bundle: .main)

    // MARK: Text

    /// Main text and continue buttons (#1D1B18 · dark #F3F0E9).
    static let ratioInk = Color("Ink", bundle: .main)
    /// Metadata and captions (#6B655C, 5.1:1 · dark #A9A296, 6.8:1).
    static let ratioInk2 = Color("Ink2", bundle: .main)
    /// Text on ink and oxblood fills (#FDFCF8 in both appearances).
    static let ratioOnInk = Color("OnInk", bundle: .main)

    // MARK: Accent and feedback

    /// Accent text: key terms, case names, incorrect (#9B2A24 · dark lifted to #E27B73).
    static let ratioOxblood = Color("Oxblood", bundle: .main)
    /// Primary-button fill — keeps the deep oxblood in dark mode (#9B2A24 both).
    static let ratioCommitFill = Color("CommitFill", bundle: .main)
    /// Trap panel and missed-answer fill (#F2E4E1 · dark #3A2524).
    static let ratioOxWash = Color("OxWash", bundle: .main)
    /// Correct and "secure" only — never a general accent (#1C7147 · dark #6CC096).
    static let ratioVerdigris = Color("Verdigris", bundle: .main)
    /// Correct-row fill (#DDEBE2 · dark #1F3328).
    static let ratioVWash = Color("VWash", bundle: .main)
    /// Avatar fill only (#946518 · dark #D9A24A).
    static let ratioOchre = Color("Ochre", bundle: .main)
    /// The streak block on Today, with `ratioOnInk` text (#1F4D36 both appearances).
    static let ratioForest = Color("Forest", bundle: .main)
    /// The Duel block on Today, with `ratioOnInk` text: ink, deep oxblood in dark (#1D1B18 · dark #9B2A24).
    static let ratioDuelBlock = Color("DuelBlock", bundle: .main)

    /// Text field / input boundary (#8C857A both appearances — meets the 3:1 WCAG
    /// 1.4.11 non-text contrast requirement against both paper surfaces).
    static let ratioInputBorder = Color("InputBorder", bundle: .main)
}
