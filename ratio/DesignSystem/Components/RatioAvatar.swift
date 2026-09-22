import SwiftUI

/// The initial-letter avatar — screens/00-design-system/01-foundations.png ("Avatars:
/// italic initial on 4 fills, set by user id"). The fills stay deep in both
/// appearances so the paper-coloured initial keeps its contrast.
struct RatioAvatar: View {
    let initial: String
    /// Stable seed for the fill, normally the user ID.
    let seed: String
    var size: CGFloat = 40

    private static let fills: [Color] = [
        Color(red: 0.608, green: 0.165, blue: 0.141), // oxblood #9B2A24
        Color(red: 0.110, green: 0.443, blue: 0.278), // verdigris #1C7147
        Color(red: 0.580, green: 0.396, blue: 0.094), // ochre #946518
        Color(red: 0.114, green: 0.106, blue: 0.094), // ink #1D1B18
    ]

    var body: some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(Color.ratioRule, lineWidth: 1))
            .overlay {
                Text(initial.prefix(1).uppercased())
                    .font(.custom("NewsreaderDisplay-Italic", fixedSize: size * 0.55))
                    .foregroundStyle(Color.ratioOnInk)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// `String.hashValue` changes every launch, so sum the scalars instead.
    private var fill: Color {
        let sum = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.fills[sum % Self.fills.count]
    }
}
