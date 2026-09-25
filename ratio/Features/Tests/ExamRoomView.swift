import SwiftUI

/// The exam room — screens/21-tests-intro-exam-room.png and 22-test-item.png — then the
/// debrief (23). A dark full-screen moment: "without the notes". Answers aren't marked
/// one by one here; everything is revealed in the debrief. SQE1 lessons run as "SQE1
/// practice", with the real exam's pace (about 1 min 42 s a question) shown as a guide.
/// On iPad (screens/iPad/3-lesson/06–07) a question's fact pattern sits on the left and
/// the question and options on the right.
struct ExamRoomView: View {
    let lesson: Lesson
    let headline: Headline?
    /// Called when the student leaves the debrief ("Back to Today").
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ContentStore.self) private var content
    @Environment(\.ratioWidth) private var width
    @State private var model: TestModel
    @State private var started = false
    @State private var result: TestModel.Result?
    @State private var submitFailed = false
    @State private var confirmingLeave = false
    @State private var applicationEstimate: Estimate?
    /// When the question on screen was shown, for the SQE1 pace guide.
    @State private var questionStart = Date.now

    private var isSQE: Bool { lesson.moduleId.programme == .sqe1 }

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
                    if width.isCompact {
                        VStack(alignment: .leading, spacing: RatioSpace.m) {
                            question(item, prompt: nil)
                        }
                        .padding(.horizontal, RatioSpace.m)
                        .padding(.top, RatioSpace.s)
                        .padding(.bottom, RatioSpace.xl)
                    } else if let split = Self.factPattern(of: item) {
                        ColumnsLayout(fraction: 0.44, spacing: RatioSpace.xl) {
                            factPattern(split.facts)
                            VStack(alignment: .leading, spacing: RatioSpace.m) {
                                question(item, prompt: split.question)
                            }
                        }
                        .padding(.horizontal, RatioSpace.xl)
                        .padding(.top, RatioSpace.m)
                        .padding(.bottom, RatioSpace.xl)
                    } else {
                        VStack(alignment: .leading, spacing: RatioSpace.m) {
                            question(item, prompt: nil)
                        }
                        .ratioReadableWidth(760)
                        .padding(.horizontal, RatioSpace.xl)
                        .padding(.top, RatioSpace.m)
                        .padding(.bottom, RatioSpace.xl)
                    }
                }
                .holdsStillWhileReordering()
                .scrollDismissesKeyboard(.interactively)
                .transition(.push(from: .trailing))
            } else {
                submitting
            }
        }
        .animation(RatioMotion.reveal, value: model.responses.count)
        .onChange(of: model.responses.count) { questionStart = .now }
        .onChange(of: started) { questionStart = .now }
        .ratioPage()
        .ratioFeedback(.impact(weight: .light), trigger: model.responses.count)
        .confirmationDialog("Leave the exam room?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave — nothing is saved", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func question(_ item: Item, prompt: String?) -> some View {
        Text("\(isSQE ? "Question" : "Test") \(model.responses.count + 1) of \(model.items.count)\(isSQE ? "" : " · \(item.typeTitle)")")
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
        if isSQE { PaceGuide(start: questionStart) }
        ItemInteractionView(item: item, lockedResponse: nil, context: context(for: item), promptOverride: prompt) { response in
            model.answer(response)
            if model.isFinished { Task { await submit() } }
        }
        .id(item.id)
    }

    /// iPad: the fact pattern, set large beside the question.
    private func factPattern(_ facts: String) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Fact pattern").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(facts)
                .ratioFont(.h2)
                .italic()
                .padding(.leading, RatioSpace.m)
                .overlay(alignment: .leading) { Rectangle().fill(Color.ratioInk2).frame(width: 2) }
            Rectangle().fill(Color.ratioRule).frame(height: 1).padding(.top, RatioSpace.l)
            Text("No hints in the exam room. Everything is marked at the end, with the reasoning.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
        }
    }

    /// A question whose prompt sets out facts and then asks something ("Dev sets fire to a
    /// flat… On Woollin, the safest direction to the jury is —"): the facts and the
    /// question, or nil for a short prompt or an interaction that needs its text inline.
    private static func factPattern(of item: Item) -> (facts: String, question: String)? {
        guard case .choice = item.kind, item.prompt.count >= 140 else { return nil }
        let sentences = Item.sentences(in: item.prompt)
        guard sentences.count >= 2, let last = sentences.last,
              ["?", "—", ":", "…"].contains(where: { last.hasSuffix($0) }) else { return nil }
        return (sentences.dropLast().joined(separator: " "), last)
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
                Text(isSQE ? "SQE1 practice" : "Exam room").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
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
                    Text(isSQE
                         ? "\(model.items.count) single-best-answer questions, weighted to \(model.weakestSkill.phrase). Aim for about 1 min 42 s each, as in SQE1. Nothing is marked until the end."
                         : "\(model.items.count) items weighted to \(model.weakestSkill.phrase). A retake draws new ones.")
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
            .ratioReadableWidth(width.isCompact ? .infinity : 760)
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.l)
            .padding(.bottom, RatioSpace.m)
        }
        .holdsStillWhileReordering()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: RatioSpace.xs) {
                RatioButton("Begin", isEnabled: !model.items.isEmpty) {
                    withAnimation(RatioMotion.reveal) { started = true }
                }
                .keyboardShortcut(.return, modifiers: .command)
                if KeyboardMonitor.shared.isConnected { KeyHint(keys: "⌘↩", label: "Begin") }
            }
            .ratioReadableWidth(width.isCompact ? .infinity : 480)
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

/// SQE1 pace: the real exam allows about 1 min 42 s a question. A guide, not a limit —
/// the bar fills over that time and the elapsed time turns oxblood after it.
private struct PaceGuide: View {
    let start: Date
    private static let pace: TimeInterval = 102

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(start))
            let over = elapsed > Self.pace
            HStack(spacing: RatioSpace.xs) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ratioRule)
                        Capsule().fill(over ? Color.ratioOxblood : Color.ratioInk2)
                            .frame(width: proxy.size.width * min(1, elapsed / Self.pace))
                    }
                }
                .frame(height: 3)
                Text("\(Self.clock(elapsed)) / 1:42")
                    .ratioFont(.monoData)
                    .foregroundStyle(over ? Color.ratioOxblood : Color.ratioInk2)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pace: \(Int(elapsed)) seconds of about 102")
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
