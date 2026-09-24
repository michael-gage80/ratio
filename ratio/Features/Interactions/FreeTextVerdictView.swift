import SwiftUI

/// Shows the model answer for something the student wrote, then settles whether it
/// covered the key point. With Apple Intelligence, the on-device model proposes a
/// verdict and the student confirms or overrides it in one tap; otherwise the student
/// marks themselves (PRD: "Recall first"; plan: Foundation Models with self-mark fallback).
struct FreeTextVerdictView: View {
    let studentAnswer: String
    let modelAnswer: String
    var keyPoints: [String] = []
    let onDecision: (Bool) -> Void

    @State private var marking: AnswerMarker.Marking?
    @State private var isMarking = AnswerMarker.isAvailable

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text("Model answer").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text(modelAnswer).ratioFont(.body)
            }
            .ratioPanel()

            if isMarking {
                HStack(spacing: RatioSpace.xs) {
                    ProgressView().controlSize(.small)
                    Text("Checking your answer on this phone…").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
            } else if let marking {
                Label {
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text(marking.coversKeyPoint ? "Ratio's check: covers the key point" : "Ratio's check: misses the key point")
                            .ratioFont(.monoLabel)
                        Text(marking.comment).ratioFont(.small)
                    }
                } icon: {
                    Image(systemName: marking.coversKeyPoint ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
                .foregroundStyle(marking.coversKeyPoint ? Color.ratioVerdigris : Color.ratioOxblood)

                RatioButton("Continue", style: .secondary) { onDecision(marking.coversKeyPoint) }
                Button(marking.coversKeyPoint ? "Actually, I missed it" : "Actually, I got it") {
                    onDecision(!marking.coversKeyPoint)
                }
                .ratioFont(.small)
                .underline()
                .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Text("Did your answer cover the key point?").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RatioSpace.xs) { selfMark }
                    VStack(spacing: RatioSpace.xs) { selfMark }
                }
            }
        }
        .task {
            guard isMarking else { return }
            defer { isMarking = false }
            marking = await AnswerMarker.mark(answer: studentAnswer, modelAnswer: modelAnswer, keyPoints: keyPoints)
        }
    }

    @ViewBuilder private var selfMark: some View {
        RatioButton("I missed it", style: .tertiary) { onDecision(false) }
        RatioButton("I got it", style: .secondary) { onDecision(true) }
    }
}
