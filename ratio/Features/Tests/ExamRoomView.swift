import SwiftUI

/// The exam room — screens/21-tests-intro-exam-room.png and 22-test-item.png — then the
/// debrief (23). A dark full-screen moment: "without the notes". Answers aren't marked
/// one by one here; everything is revealed in the debrief.
struct ExamRoomView: View {
    let lesson: Lesson
    let headline: Headline?
    /// Called when the student leaves the debrief ("Back to Today").
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var content
    @State private var model: TestModel
    @State private var started = false
    @State private var result: TestModel.Result?
    @State private var submitFailed = false
    @State private var confirmingLeave = false
    @State private var applicationEstimate: Estimate?

    init(lesson: Lesson, headline: Headline?, onFinish: @escaping () -> Void) {
        self.lesson = lesson
        self.headline = headline
        self.onFinish = onFinish
        _model = State(initialValue: TestModel(lesson: lesson))
    }

    var body: some View {
        Group {
            if let result {
                DebriefView(lesson: lesson, model: model, result: result, onFinish: onFinish)
            } else {
                examRoom
                    .environment(\.colorScheme, .dark)
            }
        }
        .task {
            await model.prepare(headline: headline)
            applicationEstimate = await SkillRepository().estimate(topicId: lesson.topicId, skill: .application) ?? headline?.application
        }
    }

    private var examRoom: some View {
        VStack(spacing: 0) {
            topBar
            if !started {
                intro
            } else if let item = model.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: RatioSpace.m) {
                        Text("Test \(model.responses.count + 1) of \(model.items.count) · \(item.typeTitle)")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                        ItemInteractionView(item: item, lockedResponse: nil, context: context(for: item)) { response in
                            model.answer(response)
                            if model.isFinished { Task { await submit() } }
                        }
                        .id(item.id)
                    }
                    .padding(.horizontal, RatioSpace.m)
                    .padding(.top, RatioSpace.s)
                    .padding(.bottom, RatioSpace.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                .transition(.push(from: .trailing))
            } else {
                submitting
            }
        }
        .animation(RatioMotion.reveal, value: model.responses.count)
        .ratioPage()
        .ratioFeedback(.impact(weight: .light), trigger: model.responses.count)
        .confirmationDialog("Leave the exam room?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave — nothing is saved", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: RatioSpace.s) {
            RatioIconButton(systemImage: started ? "xmark" : "chevron.left", label: "Leave the exam room") {
                if started && !model.responses.isEmpty && result == nil { confirmingLeave = true } else { dismiss() }
            }
            if started {
                HStack(spacing: RatioSpace.xxs) {
                    ForEach(model.items.indices, id: \.self) { index in
                        Capsule()
                            .fill(index < model.responses.count ? Color.ratioInk : index == model.responses.count ? Color.ratioOxblood : Color.ratioRule)
                            .frame(height: 3)
                    }
                }
                .accessibilityHidden(true)
            } else {
                Spacer()
                Text("Exam room").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(.horizontal, RatioSpace.s)
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                Text(model.items.isEmpty ? "Tests · drawing them for you" : "Tests · \(model.items.count) items · drawn for you")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("Without the \(Text("notes.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
                if !model.items.isEmpty {
                    Text("\(model.items.count) items weighted to \(model.weakestSkill.phrase). A retake draws new ones.")
                        .ratioFont(.h3)
                }
                VStack(spacing: 0) {
                    if model.items.isEmpty {
                        ForEach(0..<4, id: \.self) { index in
                            testRow(index: index, title: "Quick check", skill: "Knowledge", weakest: false)
                        }
                        .ratioSkeleton()
                    } else {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            testRow(index: index, title: item.typeTitle, skill: item.skill.title, weakest: item.skill == model.weakestSkill)
                        }
                    }
                }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.l)
            .padding(.bottom, RatioSpace.m)
        }
        .safeAreaInset(edge: .bottom) {
            RatioButton("Begin", isEnabled: !model.items.isEmpty) {
                withAnimation(RatioMotion.reveal) { started = true }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.vertical, RatioSpace.s)
            .background(Color.ratioParchment)
        }
    }

    private func testRow(index: Int, title: String, skill: String, weakest: Bool) -> some View {
        let number = Text(String(format: "%02d", index + 1)).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
        let skillLabel = Text(skill).ratioFont(.monoLabel).foregroundStyle(weakest ? Color.ratioOxblood : Color.ratioInk2)
        return VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.s) {
                    number
                    Text(title).ratioFont(.monoLabel)
                    Spacer(minLength: RatioSpace.xs)
                    skillLabel
                }
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    number
                    Text(title).ratioFont(.monoLabel)
                    skillLabel
                }
            }
            .padding(.vertical, RatioSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Divider().overlay(Color.ratioRule)
        }
    }

    private var submitting: some View {
        VStack(spacing: RatioSpace.m) {
            Spacer()
            ZStack {
                RatioRings(diameter: 140)
                RatioMark(size: 56, opticallyCentred: true)
            }
            if submitFailed {
                RatioErrorState(message: "We couldn't reach the server to mark these. Your answers are still here.") {
                    Task { await submit() }
                }
            } else {
                Text("Marking your answers.").ratioFont(.h2).italic()
            }
            Spacer()
        }
        .padding(RatioSpace.m)
    }

    private func context(for item: Item) -> InteractionContext {
        let decoys = content.iracDecoys(for: item.id, in: lesson.moduleId)
        return InteractionContext(iracLevel: IRACScaffold.level(for: applicationEstimate),
                                  decoyFacts: decoys.facts, decoyRules: decoys.rules, lessonId: lesson.id)
    }

    private func submit() async {
        submitFailed = false
        do {
            let submitted = try await model.submit()
            withAnimation(RatioMotion.reveal) { result = submitted }
        } catch {
            submitFailed = true
        }
    }
}
