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
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Why").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(explanation).ratioFont(.body).foregroundStyle(Color.ratioInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RatioSpace.s)
        .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
    }
}

public struct RatioTrapCard: View {
    private let commonWrongAnswer: String?
    private let whyItsWrong: String

    /// `commonWrongAnswer` is the lesson `theTrap` component's quoted wrong answer;
    /// item-level trap explanations already name it, so they pass `nil`.
    public init(commonWrongAnswer: String? = nil, whyItsWrong: String) {
        self.commonWrongAnswer = commonWrongAnswer
        self.whyItsWrong = whyItsWrong
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("The trap").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
            if let commonWrongAnswer {
                Text(commonWrongAnswer).ratioFont(.bodyEmphasis).foregroundStyle(Color.ratioOxblood)
            }
            Text(whyItsWrong).ratioFont(.body).foregroundStyle(Color.ratioInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RatioSpace.s)
        .background(Color.ratioOxWash, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
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
            .foregroundStyle(Color.ratioInk2)
            .underline()
    }
}
