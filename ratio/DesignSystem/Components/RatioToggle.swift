import SwiftUI

/// Toggle — screens/00-design-system/02-components.png, cell 03. A thin wrapper over
/// the system `Toggle` so every switch in the app shares one tint and label style,
/// with an optional mono caption underneath (e.g. "DAYS A WEEK YOU AIM TO STUDY").
public struct RatioToggle: View {
    private let title: String
    private let caption: String?
    @Binding private var isOn: Bool

    public init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            Toggle(isOn: $isOn) {
                Text(title).ratioFont(.body)
            }
            .tint(.ratioControl)
            if let caption {
                Text(caption)
                    .ratioFont(.caption)
                    .foregroundStyle(Color.ratioInk2)
            }
        }
    }
}

/// Stepper — "Weekly target · − 4 of 7 +" (cell 03).
public struct RatioStepper: View {
    private let title: String
    private let unitLabel: (Int) -> String
    @Binding private var value: Int
    private let range: ClosedRange<Int>

    public init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, unitLabel: @escaping (Int) -> String) {
        self.title = title
        self._value = value
        self.range = range
        self.unitLabel = unitLabel
    }

    public var body: some View {
        HStack {
            Text(title).ratioFont(.body)
            Spacer()
            HStack(spacing: RatioSpace.s) {
                Button {
                    if value > range.lowerBound { value -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                        .background(Color.ratioSunk, in: Circle())
                }
                .disabled(value <= range.lowerBound)

                Text(unitLabel(value))
                    .ratioFont(.h3)
                    .frame(minWidth: 64)

                Button {
                    if value < range.upperBound { value += 1 }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .background(Color.ratioSunk, in: Circle())
                }
                .disabled(value >= range.upperBound)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ratioInk)
        }
    }
}
