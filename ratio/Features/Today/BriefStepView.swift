import SwiftUI

/// screens/15-brief-step.png — where the student is in today's brief, and the way into
/// the next step. A Read step opens the lesson's lecture; the others open a practice
/// session over the items the brief chose.
struct BriefStepView: View {
    /// iPad: shown as a form sheet over Today, so leaving closes the sheet.
    var inSheet = false

    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var practising: PracticeStep?

    var body: some View {
        Group {
            if let brief = student.brief {
                steps(brief)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ratioPage()
        .fullScreenCover(item: $practising) { practice in
            if let brief = student.brief {
                PracticeSessionView(brief: brief, stepIndex: practice.index)
            }
        }
        // No completion screen: once the last step is done, back to Today, where the
        // brief card says so.
        .onChange(of: isComplete) { _, complete in
            guard complete else { return }
            if inSheet { dismiss() } else { navigator.todayPath.removeAll() }
        }
    }

    private var isComplete: Bool {
        student.brief.map { student.currentStep(of: $0, content: content) == nil } ?? false
    }

    private func steps(_ brief: DailyBrief) -> some View {
        let current = student.currentStep(of: brief, content: content)
        let shown = current ?? brief.steps.count - 1
        let step = brief.steps[shown]
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    Text(current == nil ? "Brief · Complete" : "Brief · Step \(shown + 1) of \(brief.steps.count) · \(step.kind.title)")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        if shown > 0 && current != nil {
                            // "Read ✓ COMPLETE", as in screens/15-brief-step.png.
                            let previous = brief.steps[shown - 1]
                            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                                Text(previous.kind.title)
                                    .strikethrough(color: .ratioVerdigris)
                                    .foregroundStyle(Color.ratioInk2)
                                    .ratioFont(.h3)
                                Label("Complete", systemImage: "checkmark")
                                    .ratioFont(.monoLabel)
                                    .foregroundStyle(Color.ratioVerdigris)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(previous.kind.title) complete")
                        }
                        heading(current: current, of: brief).ratioFont(.display)
                    }
                    Text(current == nil ? "Everything you answered is scheduled for review. A new brief is waiting tomorrow." : detail(step, in: brief))
                        .ratioFont(.h3)
                    VStack(spacing: 0) {
                        ForEach(brief.steps.indices, id: \.self) { index in
                            Divider().overlay(Color.ratioRule)
                            row(brief.steps[index], index: index, brief: brief, isCurrent: index == current)
                        }
                        Divider().overlay(Color.ratioRule)
                    }
                }
                .padding(RatioSpace.m)
            }
            Group {
                if let current {
                    HStack(spacing: RatioSpace.s) {
                        RatioButton("Continue →", style: .secondary) { begin(current, of: brief) }
                            .keyboardShortcut(.return, modifiers: .command)
                        KeyHint(keys: "⌘↩", label: "Continue")
                    }
                } else {
                    RatioButton("Back to Today", style: .secondary) { dismiss() }
                }
            }
            .padding(RatioSpace.m)
        }
        .toolbar {
            ToolbarItem(placement: .principal) { progress(done: brief.steps.indices.count { student.isDone(step: $0, of: brief, content: content) }, of: brief.steps.count) }
            if inSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
    }

    private func heading(current: Int?, of brief: DailyBrief) -> Text {
        guard let current else { return Text("Brief complete.") }
        let kind = brief.steps[current].kind.rawValue
        let lead = current == 0 ? "First, the" : current == brief.steps.count - 1 ? "Last, the" : "Now, the"
        return Text("\(lead) \(Text(kind + ".").italic().foregroundStyle(Color.ratioOxblood))")
    }

    private func detail(_ step: DailyBrief.Step, in brief: DailyBrief) -> String {
        switch step.kind {
        case .read:
            return "The lecture on \(brief.title), about \(step.minutes) minutes. Each part opens when you answer the one before."
        case .drill:
            let own = step.itemIds.count { content.testItem(id: $0)?.lesson.id == brief.lessonId }
            let others = step.itemIds.count - own
            return "\(own) quick questions on \(brief.title)" + (others > 0 ? ", mixed with \(others) due \(others == 1 ? "review" : "reviews") from other topics." : ".")
        case .build:
            return "Apply the rule to fresh facts: \(step.itemIds.count) \(step.itemIds.count == 1 ? "problem" : "problems"), about \(step.minutes) minutes."
        case .review:
            return "\(step.itemIds.count) \(step.itemIds.count == 1 ? "item that has" : "items that have") come due, mixed across topics so you learn to tell the rules apart."
        }
    }

    private func row(_ step: DailyBrief.Step, index: Int, brief: DailyBrief, isCurrent: Bool) -> some View {
        let done = student.isDone(step: index, of: brief, content: content)
        let title = HStack(alignment: .firstTextBaseline, spacing: RatioSpace.m) {
            Text(String(format: "%02d", index + 1)).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            Text(step.kind.title)
                .ratioFont(.h2)
                .italic(isCurrent)
                .strikethrough(done, color: .ratioVerdigris)
                .foregroundStyle(done ? Color.ratioInk2 : isCurrent ? Color.ratioOxblood : Color.ratioInk)
        }
        let status = Group {
            if done {
                Label("Done", systemImage: "checkmark").foregroundStyle(Color.ratioVerdigris)
            } else if isCurrent {
                Text(step.kind == .read ? "Now · \(step.minutes)\u{00A0}min" : "Now · \(step.itemIds.count) questions").foregroundStyle(Color.ratioOxblood)
            } else {
                Text("\(step.minutes)\u{00A0}min").foregroundStyle(Color.ratioInk2)
            }
        }
        .ratioFont(.monoLabel)
        // Side by side, or stacked at the accessibility text sizes.
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: RatioSpace.xs) { title; status }
            } else {
                HStack(alignment: .firstTextBaseline) { title; Spacer(minLength: RatioSpace.xs); status }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RatioSpace.s)
        .accessibilityElement(children: .combine)
    }

    private func progress(done: Int, of total: Int) -> some View {
        HStack(spacing: RatioSpace.s) {
            GeometryReader { proxy in
                let x = proxy.size.width * CGFloat(done) / CGFloat(max(total, 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ratioRule).frame(height: 2)
                    Capsule().fill(Color.ratioInk).frame(width: x, height: 2)
                    Circle().fill(Color.ratioOxblood).frame(width: 8, height: 8).offset(x: max(0, x - 4))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(minWidth: 120, maxWidth: 220)
            .frame(height: 8)
            Text("\(done) / \(total)").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) steps done")
    }

    private func begin(_ index: Int, of brief: DailyBrief) {
        let step = brief.steps[index]
        if step.kind == .read, let lessonId = step.lessonId {
            // From the iPad sheet, close it and open the lecture on Today's stack.
            if inSheet { dismiss() }
            navigator.todayPath.append(.lecture(lessonId))
        } else {
            practising = PracticeStep(index: index)
        }
    }
}

private struct PracticeStep: Identifiable {
    let index: Int
    var id: Int { index }
}
