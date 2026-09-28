import SwiftUI

/// Case of the day on Today: an oxblood block with one case from the student's own
/// modules. The facts first, then "What was the ratio?" to reveal it, then Knew it /
/// Didn't know it — a miss comes back in a later brief's Review. Once rated it
/// collapses to one line until tomorrow (functions/src/caseOfDay.ts).
struct CaseOfDayCard: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(NetworkMonitor.self) private var network
    /// "-caseRevealed" (debug screenshots) opens it with the ratio showing.
    @State private var revealed = ProcessInfo.processInfo.arguments.contains("-caseRevealed")
    @State private var saving = false
    @State private var failed = false

    var body: some View {
        if let day = student.caseOfDay, let found = content.caseCard(itemId: day.caseId) {
            Group {
                if let result = day.result {
                    rated(found.card, result: result)
                } else {
                    full(found.card, day: day, module: found.lesson.moduleId)
                }
            }
            .foregroundStyle(Color.ratioOnInk)
            .ratioCard(.ratioCaseBlock, bordered: false)
            .animation(RatioMotion.reveal, value: revealed)
            .animation(RatioMotion.reveal, value: day.result)
        }
    }

    // MARK: Before rating

    private func full(_ card: LessonComponent.CaseCard, day: CaseDay, module: Module) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text("Case of the day · \(module.title)").ratioFont(.monoLabel).opacity(0.8)
                Text(card.caseName).italic().ratioFont(.h2)
                Text("\(card.citation) · \(card.court)").ratioFont(.monoLabel).opacity(0.8)
            }
            .accessibilityElement(children: .combine)
            Text(card.factsShort).ratioFont(.body)

            if revealed {
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Ratio").ratioFont(.monoLabel).opacity(0.8)
                    Text(card.ratioShort).ratioFont(.body).italic()
                }
                .padding(RatioSpace.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ratioOnInk.opacity(0.12), in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))

                links(card, lessonId: day.lessonId)

                Text("Did you know it?").ratioFont(.monoLabel).opacity(0.8)
                HStack(spacing: RatioSpace.s) {
                    pill("Knew it", filled: true) { rate(knew: true) }
                    pill("Didn't know it", filled: false) { rate(knew: false) }
                }
                .disabled(saving || !network.isOnline)
                if failed {
                    Text("That didn't save. Try again.").ratioFont(.small).italic()
                } else if !network.isOnline {
                    Text("You're offline — rate it when you're back.").ratioFont(.small).italic().opacity(0.85)
                }
            } else {
                pill("What was the ratio? Reveal", filled: true) { revealed = true }
                    .accessibilityHint("Try to recall it first")
            }
        }
    }

    private func links(_ card: LessonComponent.CaseCard, lessonId: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RatioSpace.m) { linkButtons(card, lessonId: lessonId) }
            VStack(alignment: .leading, spacing: RatioSpace.xs) { linkButtons(card, lessonId: lessonId) }
        }
    }

    @ViewBuilder
    private func linkButtons(_ card: LessonComponent.CaseCard, lessonId: String) -> some View {
        Button { openCase(card) } label: {
            Text("Read the case →").ratioFont(.small).underline().frame(minHeight: 44)
        }
        .buttonStyle(.ratioPress)
        if let lesson = content.lesson(id: lessonId) {
            Button { openLesson(lesson.id) } label: {
                Text("From: \(lesson.title) →").ratioFont(.small).underline().multilineTextAlignment(.leading).frame(minHeight: 44)
            }
            .buttonStyle(.ratioPress)
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ratioFont(.h3)
                .foregroundStyle(filled ? Color.ratioInk : Color.ratioOnInk)
                .padding(.horizontal, RatioSpace.m)
                .frame(minHeight: 44)
                .background {
                    if filled {
                        Capsule().fill(Color.ratioParchment)
                    } else {
                        Capsule().strokeBorder(Color.ratioOnInk.opacity(0.6))
                    }
                }
        }
        .buttonStyle(.ratioPress)
    }

    // MARK: After rating

    private func rated(_ card: LessonComponent.CaseCard, result: CaseDay.Result) -> some View {
        Button { openCase(card) } label: {
            HStack(spacing: RatioSpace.s) {
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text("Case of the day").ratioFont(.monoLabel).opacity(0.8)
                    Text("\(result == .knew ? "✓ " : "")\(Text(card.caseName).italic()) · \(result == .knew ? "You knew it" : "Back in your reviews")")
                        .ratioFont(.h3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: RatioSpace.xs)
                Image(systemName: "arrow.right").opacity(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.ratioPress)
        .accessibilityHint("Opens the case in the Library")
    }

    // MARK: Actions

    private func rate(knew: Bool) {
        saving = true
        failed = false
        Task {
            do {
                try await student.rateCaseOfDay(knew: knew)
                revealed = false
            } catch {
                failed = true
            }
            saving = false
        }
    }

    private func openCase(_ card: LessonComponent.CaseCard) {
        navigator.pathwayPath = [.library, .libraryEntry("case:\(card.caseName)")]
        navigator.tab = .pathway
    }

    private func openLesson(_ id: String) {
        navigator.pathwayPath = [.overview(id)]
        navigator.tab = .pathway
    }
}
