import SwiftUI

/// Text field — screens/00-design-system/02-components.png, cell 03. A mono-caps
/// label above a paper-filled, `ratioInputBorder`-outlined field (the 3:1-contrast
/// boundary is what makes the field's edge visible without relying on the fainter
/// `rule` hairline, which is reserved for dividers).
public struct RatioTextField: View {
    private let label: String
    private let placeholder: String
    @Binding private var text: String
    private let axis: Axis
    private let isSecure: Bool

    public init(_ label: String, placeholder: String = "", text: Binding<String>, axis: Axis = .horizontal, isSecure: Bool = false) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
        self.isSecure = isSecure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text(label).ratioFont(.monoLabel)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else if axis == .vertical {
                    TextField(placeholder, text: $text, axis: .vertical)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .ratioFont(.body)
            .padding(RatioSpace.s)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
                    .strokeBorder(Color.ratioInputBorder, lineWidth: 1)
            }
        }
    }
}
