import SwiftUI

/// screens/18-lecture-gated-scroll.png — the lecture as one long page, each part
/// opening once the student answers the one before (PRD: lesson stage 2, "Lecture").
/// Progress is saved after every part, so the lecture resumes where it stopped.
struct LectureView: View {
    let lesson: Lesson

    @State private var partsCompleted = 0
    /// The current part's answer, once locked in.
    @State private var lockedResponse: ItemResponse?
    @State private var loaded = false
    @State private var showsTestsNotice = false

    private let progress = LessonProgressRepository()
    private static let numerals = ["I", "II", "III", "IV", "V", "VI"]

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
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
                    Text("Educational, not legal advice · Law stated as at \(lesson.lawStatedDate)")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar {
            ToolbarItem(placement: .principal) {
                progressBar
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            partsCompleted = min(await progress.partsCompleted(lessonId: lesson.id), lesson.parts.count)
            loaded = true
        }
        .sensoryFeedback(trigger: lockedResponse) { _, response in
            guard let response, let item = lesson.parts[safe: partsCompleted]?.interaction else { return nil }
            return item.isCorrect(response) ? .success : .error
        }
        .alert("Tests arrive next phase", isPresented: $showsTestsNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You've finished the lecture. The exam-room tests and debrief come in the next build.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lecture · \(lesson.moduleId.title) · Lesson \(lesson.lessonNumber)")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            Text(lesson.title).ratioFont(.h1)
            Text("\(lesson.parts.count) parts, about \(lesson.estimatedMinutes) minutes. Each part opens when you answer the one before.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
            Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.top, 8)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
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

    private func partView(_ part: Lesson.Part, index: Int, scroll: ScrollViewProxy) -> some View {
        let isCurrent = index == partsCompleted
        return VStack(alignment: .leading, spacing: 18) {
            Text("Part \(Self.numerals[safe: index] ?? "\(index + 1)")").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(part.heading).ratioFont(.h2)
            ForEach(Array(part.body.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).ratioFont(.body)
            }
            ForEach(Array(part.components.enumerated()), id: \.offset) { _, component in
                LessonComponentView(component: component, moduleTitle: lesson.moduleId.title)
            }

            if isCurrent {
                VStack(alignment: .leading, spacing: 16) {
                    Label(part.interaction.typeTitle, systemImage: "circle.fill")
                        .labelStyle(DotLabelStyle())
                        .ratioFont(.monoLabel)
                    ItemInteractionView(item: part.interaction, lockedResponse: lockedResponse) { response in
                        lockedResponse = response
                    }
                    if lockedResponse != nil {
                        RatioButton(index == lesson.parts.count - 1 ? "To the tests" : "Continue", style: .secondary) {
                            advance(scroll: scroll)
                        }
                    }
                }
                .padding(20)
                .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.ratioRule) }
            } else {
                Label("Checked", systemImage: "checkmark.circle.fill")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioVerdigris)
            }
        }
    }

    /// A part not yet opened ("PART II · THE TEST · ANSWER TO CONTINUE"), or the tests
    /// when `part` is nil.
    @ViewBuilder
    private func lockedRow(_ part: Lesson.Part?, index: Int) -> some View {
        if index > partsCompleted || (part == nil && partsCompleted < lesson.parts.count) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").imageScale(.small)
                Text(part.map { "Part \(Self.numerals[safe: index] ?? "\(index + 1)") · \($0.heading)" } ?? "To the tests")
                    .lineLimit(2)
                Spacer()
                Text("Answer to continue")
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            .padding(16)
            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
            .accessibilityElement(children: .combine)
        }
    }

    private func advance(scroll: ScrollViewProxy) {
        let isLast = partsCompleted == lesson.parts.count - 1
        partsCompleted += 1
        lockedResponse = nil
        progress.save(lessonId: lesson.id, partsCompleted: partsCompleted)
        if isLast {
            showsTestsNotice = true
        } else if let next = lesson.parts[safe: partsCompleted] {
            withAnimation { scroll.scrollTo(next.id, anchor: .top) }
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.ratioOxblood)
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
        default: type
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
