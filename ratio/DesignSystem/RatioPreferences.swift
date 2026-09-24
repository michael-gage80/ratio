import SwiftUI

/// The student's appearance and accessibility choices (Settings → Appearance and
/// Accessibility), kept on the phone and applied to the whole app from the root.
enum RatioPreferences {
    static let appearance = "appearance" // "auto", "light" or "dark"
    static let dyslexia = "a11y.dyslexia"
    static let reduceMotion = "a11y.reduceMotion"
    static let haptics = "a11y.haptics"
}

private struct RatioPreferencesModifier: ViewModifier {
    @AppStorage(RatioPreferences.appearance) private var appearance = "auto"
    @AppStorage(RatioPreferences.dyslexia) private var dyslexia = false
    @AppStorage(RatioPreferences.reduceMotion) private var reduceMotion = false

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .environment(\.ratioDyslexiaFriendly, dyslexia)
            // "Reduce motion" in Ratio as well as the system setting (PRD: always respected).
            .transaction { transaction in
                if reduceMotion { transaction.animation = nil }
            }
    }
}

extension View {
    func ratioPreferences() -> some View { modifier(RatioPreferencesModifier()) }

    /// Haptics that respect Settings → Accessibility → Haptics.
    func ratioFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, condition: @escaping (T, T) -> Bool = { _, _ in true }) -> some View {
        modifier(RatioFeedback(trigger: trigger) { old, new in condition(old, new) ? feedback : nil })
    }

    func ratioFeedback<T: Equatable>(trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?) -> some View {
        modifier(RatioFeedback(trigger: trigger, feedback: feedback))
    }
}

private struct RatioFeedback<T: Equatable>: ViewModifier {
    @AppStorage(RatioPreferences.haptics) private var enabled = true
    let trigger: T
    let feedback: (T, T) -> SensoryFeedback?

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { old, new in enabled ? feedback(old, new) : nil }
    }
}
