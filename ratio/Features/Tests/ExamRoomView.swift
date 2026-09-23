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
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Test \(model.responses.count + 1) of \(model.items.count) · \(item.typeTitle)")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                        ItemInteractionView(item: item, lockedResponse: nil, context: context(for: item)) { response in
                            model.answer(response)
                            if model.isFinished { Task { await submit() } }
                        }
                        .id(item.id)
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
                .transition(.push(from: .trailing))
            } else {
                submitting
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.responses.count)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .sensoryFeedback(.impact(weight: .light), trigger: model.responses.count)
        .confirmationDialog("Leave the exam room?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave — nothing is saved", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                if started && !model.responses.isEmpty && result == nil { confirmingLeave = true } else { dismiss() }
            } label: {
                Image(systemName: started ? "xmark" : "chevron.left").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Leave the exam room")
            if started {
                HStack(spacing: 4) {
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
        .padding(.horizontal, 16)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Tests · \(model.items.count) items · drawn for you").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("Without the \(Text("notes.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("\(model.items.count) items weighted to \(model.weakestSkill.phrase). A retake draws new ones.")
                .ratioFont(.h3)
            VStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(String(format: "%02d", index + 1)).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                        Text(item.typeTitle).ratioFont(.monoLabel).padding(.leading, 12)
                        Spacer()
                        Text(item.skill.title)
                            .ratioFont(.monoLabel)
                            .foregroundStyle(item.skill == model.weakestSkill ? Color.ratioOxblood : Color.ratioInk2)
                    }
                    .padding(.vertical, 14)
                    Divider().overlay(Color.ratioRule)
                }
            }
            Spacer()
            RatioButton("Begin", isEnabled: !model.items.isEmpty) {
                withAnimation { started = true }
            }
            Text("Educational, not legal advice").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private var submitting: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                RatioRings(diameter: 140)
                RatioMark(size: 72)
            }
            if submitFailed {
                Text("We couldn't reach the server. Your answers are still here.").ratioFont(.small).multilineTextAlignment(.center)
                RatioButton("Try again", style: .secondary) { Task { await submit() } }
            } else {
                Text("Marking your answers.").ratioFont(.h2).italic()
            }
            Spacer()
        }
        .padding(24)
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
            withAnimation { result = submitted }
        } catch {
            submitFailed = true
        }
    }
}
