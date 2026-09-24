import SwiftUI

/// screens/18-lecture-gated-scroll.png — the lecture as one long page, each part
/// opening once the student answers the one before (PRD: lesson stage 2, "Lecture").
/// Progress is saved after every part, so the lecture resumes where it stopped. There's
/// no Continue button: once an answer locks, its feedback stays, the next part opens
/// beneath, and the page scrolls to it after a moment (not with Reduce Motion). On iPad
/// (screens/iPad/3-lesson/02) each part's case cards, statutes and maps sit in a margin
/// beside its text; the margin is also where Pencil notes will go.
struct LectureView: View {
    let lesson: Lesson
    /// Fallback for the IRAC scaffold level when this topic hasn't been assessed yet.
    let headline: Headline?
    /// Called when the student finishes the debrief and heads back to Today.
    let onExit: () -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.ratioWidth) private var width
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(RatioPreferences.reduceMotion) private var reduceMotion = false
    @State private var applicationEstimate: Estimate?

    @State private var partsCompleted = 0
    /// Answers locked in this visit, by part, so their feedback stays on the page.
    @State private var responses: [Int: ItemResponse] = [:]
    /// The part answered most recently (for the haptic).
    @State private var lastLocked: Int?
    @State private var loaded = false
    @State private var showsExamRoom = false

    private let progress = LessonProgressRepository()
    private static let numerals = ["I", "II", "III", "IV", "V", "VI"]

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RatioSpace.l) {
                    header
                    ForEach(Array(lesson.parts.enumerated()), id: \.element.id) { index, part in
                        if index <= partsCompleted {
                            partView(part, index: index, scroll: scroll)
                                .id(part.id)
                        } else {
                            lockedRow(part, index: index)
                        }
                    }
                    lockedRow(nil, index: lesson.parts.count)
                    if loaded && partsCompleted >= lesson.parts.count {
                        RatioButton("Take the tests") { showsExamRoom = true }
                    }
                    Text("Law stated as at \(lesson.lawStatedDate)")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, width.isCompact ? RatioSpace.m : RatioSpace.xl)
                .padding(.top, RatioSpace.s)
                .padding(.bottom, RatioSpace.xl)
            }
            .holdsStillWhileReordering()
            .scrollDismissesKeyboard(.interactively)
        }
        .ratioPage()
        .toolbar {
            ToolbarItem(placement: .principal) {
                progressBar
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            partsCompleted = min(await progress.partsCompleted(lessonId: lesson.id), lesson.parts.count)
            applicationEstimate = await SkillRepository().estimate(topicId: lesson.topicId, skill: .application) ?? headline?.application
            loaded = true
        }
        .ratioFeedback(trigger: lastLocked) { _, index in
            guard let index, let response = responses[index], let item = lesson.parts[safe: index]?.interaction else { return nil }
            return item.isCorrect(response) ? .success : .error
        }
        .fullScreenCover(isPresented: $showsExamRoom) {
            ExamRoomView(lesson: lesson, headline: headline) {
                showsExamRoom = false
                onExit()
            }
            .ratioMeasuresWidth()
        }
    }

    private var header: some View {
        let title = VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Lecture · \(lesson.moduleId.title) · Lesson \(lesson.lessonNumber)")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            Text(lesson.title).ratioFont(.h1)
            Text("\(lesson.parts.count) parts, about \(lesson.estimatedMinutes) minutes. Each part opens when you answer the one before.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
            Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.top, RatioSpace.xs)
        }
        return Group {
            if width.isCompact {
                title
            } else {
                ColumnsLayout(fraction: Self.textFraction, spacing: RatioSpace.l) {
                    title
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Rectangle().fill(Color.ratioRule).frame(height: 1)
                        Text("The margin").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Text("Case cards, statutes and the doctrine map sit here, beside the part they belong to.")
                            .ratioFont(.small)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    .padding(.top, RatioSpace.xl)
                }
            }
        }
    }

    /// iPad: the share of a part's width given to its text; the margin gets the rest.
    private static let textFraction: CGFloat = 0.63

    private var progressBar: some View {
        HStack(spacing: RatioSpace.xs) {
            HStack(spacing: RatioSpace.xxs) {
                ForEach(lesson.parts.indices, id: \.self) { index in
                    Capsule()
                        .fill(index < partsCompleted ? Color.ratioInk : index == partsCompleted ? Color.ratioOxblood : Color.ratioRule)
                        .frame(width: 28, height: 3)
                }
            }
            Text("Part \(min(partsCompleted + 1, lesson.parts.count)) of \(lesson.parts.count)")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Part \(min(partsCompleted + 1, lesson.parts.count)) of \(lesson.parts.count)")
    }

    @ViewBuilder
    private func partView(_ part: Lesson.Part, index: Int, scroll: ScrollViewProxy) -> some View {
        if width.isCompact {
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                partText(part, index: index)
                components(part)
                interaction(part, index: index, scroll: scroll)
            }
        } else {
            // The part's text and interaction on the left; its components in the margin,
            // level with the top of the part.
            ColumnsLayout(fraction: Self.textFraction, spacing: RatioSpace.l) {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    Rectangle().fill(Color.ratioInk).frame(height: 1)
                    partText(part, index: index)
                    interaction(part, index: index, scroll: scroll)
                }
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    components(part)
                }
                .padding(.top, RatioSpace.l)
            }
        }
    }

    @ViewBuilder
    private func partText(_ part: Lesson.Part, index: Int) -> some View {
        Text("Part \(Self.numerals[safe: index] ?? "\(index + 1)")").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
        Text(part.heading).ratioFont(.h2)
        ForEach(Array(part.body.enumerated()), id: \.offset) { _, paragraph in
            Text(paragraph).ratioFont(.body)
        }
    }

    @ViewBuilder
    private func components(_ part: Lesson.Part) -> some View {
        ForEach(Array(part.components.enumerated()), id: \.offset) { _, component in
            LessonComponentView(component: component, moduleTitle: lesson.moduleId.title)
        }
    }

    @ViewBuilder
    private func interaction(_ part: Lesson.Part, index: Int, scroll: ScrollViewProxy) -> some View {
        let isCurrent = index == partsCompleted
        let response = responses[index]
            if isCurrent || response != nil {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    Label(part.interaction.typeTitle, systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle())
                        .ratioFont(.monoLabel)
                    ItemInteractionView(item: part.interaction, lockedResponse: response, context: context(for: part.interaction)) { response in
                        lock(response, part: index, scroll: scroll)
                    }
                }
                .ratioCard()
            } else {
                // Answered on an earlier visit. Ink, not verdigris: it says nothing about
                // whether the answer was right.
                Label("Answered", systemImage: "checkmark")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
            }
    }

    /// A part not yet opened ("PART II · THE TEST · ANSWER TO CONTINUE"), or the tests
    /// when `part` is nil.
    @ViewBuilder
    private func lockedRow(_ part: Lesson.Part?, index: Int) -> some View {
        if index > partsCompleted || (part == nil && partsCompleted < lesson.parts.count) {
            let title = Text(part.map { "Part \(Self.numerals[safe: index] ?? "\(index + 1)") · \($0.heading)" } ?? "The tests")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                    Image(systemName: "lock").imageScale(.small)
                    title
                    Spacer(minLength: RatioSpace.xs)
                    Text("Opens when you answer")
                }
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Label { title } icon: { Image(systemName: "lock").imageScale(.small) }
                    Text("Opens when you answer")
                }
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            .ratioPanel()
            .overlay {
                RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
                    .strokeBorder(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func context(for item: Item) -> InteractionContext {
        let decoys = content.iracDecoys(for: item.id, in: lesson.moduleId)
        return InteractionContext(
            iracLevel: IRACScaffold.level(for: applicationEstimate),
            decoyFacts: decoys.facts,
            decoyRules: decoys.rules,
            lessonId: lesson.id
        )
    }

    /// Opens the next part straight away; after a moment, scrolls to it — or, after the
    /// last part, opens the exam room.
    private func lock(_ response: ItemResponse, part index: Int, scroll: ScrollViewProxy) {
        guard index == partsCompleted, responses[index] == nil else { return }
        responses[index] = response
        lastLocked = index
        partsCompleted = index + 1
        progress.save(lessonId: lesson.id, partsCompleted: partsCompleted)
        let next = lesson.parts[safe: partsCompleted]
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if next == nil {
                showsExamRoom = true
            } else if let next, !(reduceMotion || systemReduceMotion) {
                withAnimation(RatioMotion.reveal) { scroll.scrollTo(next.id, anchor: .top) }
            }
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RatioSpace.xs) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.ratioOxblood).accessibilityHidden(true)
            configuration.title
        }
    }
}

extension Item {
    /// The in-line game's name, as labelled on the design board ("RECALL FIRST").
    var typeTitle: String {
        switch type {
        case "recallFirst": "Recall first"
        case "quickCheck": "Quick check"
        case "thresholdSlider": "Threshold slider"
        case "tapTheFact": "Tap the fact"
        case "irac": "IRAC builder"
        case "sequence": "Sequence"
        case "mcqWithTrap": "MCQ with trap"
        case "highlightTheRatio": "Highlight the ratio"
        case "distinguishTheCase": "Distinguish the case"
        case "statuteParser": "Statute parser"
        case "applyTheRule": "Apply the rule"
        case "sortIntoBuckets": "Sort into buckets"
        default: type
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
