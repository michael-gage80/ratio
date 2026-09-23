import FirebaseFunctions
import SwiftUI

/// A Drill, Build or Review step of the daily brief. Unlike a test, each answer is
/// marked straight away with its explanation (PRD: "Explanatory feedback"); the
/// answers are then scored and rescheduled by the `submitPractice` Function.
struct PracticeSessionView: View {
    let brief: DailyBrief
    let stepIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var content
    @Environment(StudentStore.self) private var student
    @State private var attemptId = UUID().uuidString
    @State private var responses: [ItemResponse] = []
    @State private var locked: ItemResponse?
    @State private var submitted = false
    @State private var submitFailed = false
    @State private var confirmingLeave = false

    private var step: DailyBrief.Step { brief.steps[stepIndex] }
    /// Items no longer in the content (after an update) are skipped.
    private var items: [(item: Item, lesson: Lesson)] { step.itemIds.compactMap { content.testItem(id: $0) } }
    private var current: (item: Item, lesson: Lesson)? { items[safe: responses.count] }
    private var rightCount: Int {
        responses.count { response in items.first { $0.item.id == response.itemId }.map { $0.item.isCorrect(response) } ?? false }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("\(step.kind.title) · \(responses.count + 1) of \(items.count)")
                            Spacer()
                            Text("\(current.lesson.moduleId.title) · \(TopicGroup.title(forGroup: TopicGroup.groupId(of: current.lesson.topicId)))")
                                .lineLimit(1)
                        }
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        ItemInteractionView(item: current.item, lockedResponse: locked, context: context(for: current)) { locked = $0 }
                            .id(current.item.id)
                        if let locked {
                            RatioButton(responses.count + 1 == items.count ? "Finish" : "Continue", style: .secondary) {
                                responses.append(locked)
                                self.locked = nil
                                if responses.count == items.count { Task { await submit() } }
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
                .transition(.push(from: .trailing))
            } else {
                summary
            }
        }
        .animation(.easeInOut(duration: 0.25), value: responses.count)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .sensoryFeedback(trigger: locked) { _, response in
            guard let response, let item = current?.item else { return nil }
            return item.isCorrect(response) ? .success : .error
        }
        .confirmationDialog("Leave this step?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave — answers so far aren't saved", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                if !responses.isEmpty && !submitted { confirmingLeave = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            HStack(spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < responses.count ? Color.ratioInk : index == responses.count ? Color.ratioOxblood : Color.ratioRule)
                        .frame(height: 3)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("\(step.kind.title) · Done").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("\(rightCount) of \(items.count) \(Text("right.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("Misses come back tomorrow; the rest drift further out.").ratioFont(.body)
            Spacer()
            if submitFailed {
                Text("We couldn't reach the server. Your answers are still here.").ratioFont(.small)
                RatioButton("Try again", style: .secondary) { Task { await submit() } }
            } else if submitted {
                RatioButton("Back to your brief", style: .secondary) { dismiss() }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Scheduling your reviews…").ratioFont(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
        }
        .padding(24)
    }

    private func context(for entry: (item: Item, lesson: Lesson)) -> InteractionContext {
        let decoys = content.iracDecoys(for: entry.item.id, in: entry.lesson.moduleId)
        let application = student.topics[entry.lesson.topicId]?.application ?? student.headline.application
        return InteractionContext(iracLevel: IRACScaffold.level(for: application),
                                  decoyFacts: decoys.facts, decoyRules: decoys.rules, lessonId: entry.lesson.id)
    }

    private nonisolated struct Request: Encodable {
        let attemptId: String
        let briefDate: String
        let stepIndex: Int
        let responses: [ItemResponse]
    }

    private nonisolated struct Response: Decodable {}

    private func submit() async {
        submitFailed = false
        let function = Functions.functions(region: "europe-west2")
            .httpsCallable("submitPractice", requestAs: Request.self, responseAs: Response.self)
        do {
            _ = try await function.call(Request(attemptId: attemptId, briefDate: brief.date, stepIndex: stepIndex, responses: responses))
            ActivityRepository.markToday()
            submitted = true
        } catch {
            submitFailed = true
        }
    }
}
