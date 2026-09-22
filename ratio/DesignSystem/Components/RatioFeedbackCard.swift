import SwiftUI

/// "WHY" and "THE TRAP" explanation cards — cell 04 (option feedback) and the
/// `theTrap` lecture component (Content operations, "The trap" in the PRD). Always
/// shown after lock-in, alongside the "Spotted an error? Report it" link every item
/// carries.
public struct RatioWhyCard: View {
    private let explanation: String

    public init(_ explanation: String) {
        self.explanation = explanation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why").ratioFont(.monoLabel).foregroundStyle(.secondary)
            Text(explanation).ratioFont(.body).foregroundStyle(Color.ratioInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.ratioRule.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

public struct RatioTrapCard: View {
    private let commonWrongAnswer: String
    private let whyItsWrong: String

    public init(commonWrongAnswer: String, whyItsWrong: String) {
        self.commonWrongAnswer = commonWrongAnswer
        self.whyItsWrong = whyItsWrong
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The trap").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
            Text(commonWrongAnswer).ratioFont(.bodyEmphasis).foregroundStyle(Color.ratioOxblood)
            Text(whyItsWrong).ratioFont(.body).foregroundStyle(Color.ratioInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.ratioOxblood.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// "Spotted an error? Report it" — present on every lecture component and test item.
public struct RatioReportErrorLink: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button("Spotted an error? Report it", action: action)
            .ratioFont(.monoLabel)
            .foregroundStyle(.secondary)
            .underline()
    }
}
