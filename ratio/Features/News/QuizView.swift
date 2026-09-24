import SwiftUI

/// screens/44-sunday-quiz.png — seven questions on the week's stories, each linked to its
/// article and "Why it matters" note. Practice only: it counts towards the week's
/// activity, never the boards (PRD: "Weekly current-affairs quiz").
struct QuizView: View {
    let quiz: SundayQuiz

    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigator.self) private var navigator
    @State private var index = 0
    @State private var selection: Int?
    @State private var locked = false
    @State private var right = 0
    @State private var finished = false
    @AppStorage private var score: Int

    init(quiz: SundayQuiz) {
        self.quiz = quiz
        _score = AppStorage(wrappedValue: -1, "quiz.score.\(quiz.sunday)")
    }

    private var question: SundayQuiz.Question { quiz.questions[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if finished {
                summary
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: RatioSpace.m) {
                        story
                        Text(question.prompt).ratioFont(.h1)
                        VStack(spacing: RatioSpace.xs) {
                            ForEach(question.options.indices, id: \.self) { i in
                                RatioOptionRow(letter: String(Character(UnicodeScalar(UInt8(65 + i)))), text: question.options[i], state: state(i),
                                               action: locked ? nil : { selection = i })
                            }
                        }
                        if locked {
                            RatioWhyCard(question.explanation)
                            if let why = question.story.whyItMatters {
                                WhyItMattersBox(why: why) { lessonId in
                                    dismiss()
                                    navigator.push(.overview(lessonId))
                                }
                            }
                        }
                    }
                    .padding(RatioSpace.m)
                }
                footer
            }
        }
        .ratioPage()
        .ratioFeedback(trigger: locked) { _, isLocked in
            guard isLocked else { return nil }
            return selection == question.correctIndex ? .success : .error
        }
    }

    private var header: some View {
        VStack(spacing: RatioSpace.s) {
            HStack {
                RatioIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                Spacer()
                Text("Sunday quiz · \(min(index + 1, quiz.questions.count)) of \(quiz.questions.count)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    .multilineTextAlignment(.center)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            HStack(spacing: RatioSpace.xxs) {
                ForEach(quiz.questions.indices, id: \.self) { i in
                    Capsule()
                        .fill(i < index || finished ? Color.ratioInk : i == index ? Color.ratioOxblood : Color.ratioRule)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, RatioSpace.m)
        .padding(.top, RatioSpace.xs)
    }

    private var story: some View {
        Link(destination: question.story.link ?? URL(fileURLWithPath: "/")) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text("From the week · \(question.story.source)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text(question.story.title).ratioFont(.h3).italic().foregroundStyle(Color.ratioInk2).multilineTextAlignment(.leading)
            }
            .padding(.leading, RatioSpace.s)
            .overlay(alignment: .leading) { Rectangle().fill(Color.ratioRule).frame(width: 2) }
        }
        .buttonStyle(.ratioPress)
        .disabled(question.story.link == nil)
        .accessibilityHint("Opens the story")
    }

    private var footer: some View {
        VStack(spacing: RatioSpace.s) {
            Text("Counts as practice. Not on the boards.").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if locked {
                RatioButton(index + 1 == quiz.questions.count ? "See your score" : "Next question", style: .secondary) { next() }
            } else {
                RatioButton("Lock it in", isEnabled: selection != nil) { lock() }
            }
        }
        .padding(RatioSpace.m)
        .background(Color.ratioPaper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(Color.ratioRule) }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Spacer()
            Text("Sunday quiz · Done").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("\(right) of \(quiz.questions.count) \(Text("right.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("Stories like these come up in training contract and pupillage interviews. Next week's quiz arrives on Sunday.")
                .ratioFont(.h3)
            Spacer()
            RatioButton("Done", style: .secondary) { dismiss() }
        }
        .padding(RatioSpace.m)
    }

    private func state(_ i: Int) -> RatioOptionState {
        guard locked else { return selection == i ? .selected : .default }
        if i == question.correctIndex { return .correct }
        return selection == i ? .incorrect : .default
    }

    private func lock() {
        guard selection != nil else { return }
        if selection == question.correctIndex { right += 1 }
        locked = true
    }

    private func next() {
        if index + 1 < quiz.questions.count {
            index += 1
            selection = nil
            locked = false
        } else {
            finished = true
            score = right
            ActivityRepository.markToday()
        }
    }
}
