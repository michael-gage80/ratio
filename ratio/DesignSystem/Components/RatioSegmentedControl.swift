import SwiftUI

/// Controls — screens/00-design-system/02-components.png, cell 03.
/// A pill-track segmented control (Boards' Daily/Weekly/Monthly, Settings' Light/Dark/
/// Auto). Built custom rather than the system segmented style so the selected segment
/// renders as a solid paper capsule on a rule-toned track, matching the mockups.
public struct RatioSegmentedControl<T: Hashable>: View {
    private let options: [(value: T, label: String)]
    @Binding private var selection: T

    public init(options: [(value: T, label: String)], selection: Binding<T>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .ratioFont(.h3)
                        .foregroundStyle(isSelected ? Color.ratioInk : Color.ratioInk.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.ratioPaper)
                                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Color.ratioRule.opacity(0.4), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}
