import SwiftUI

/// screens/37-result-win.png and 38-result-loss.png — "Judgment entered".
struct DuelResultView: View {
    let record: DuelRecord
    /// Sparring: another duel at the same level. Against a student: an async challenge.
    let rematch: () -> Void
    let debrief: () -> Void
    let close: () -> Void

    @Environment(ContentStore.self) private var content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: RatioSpace.m) {
                Text("Judgment entered").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).padding(.top, RatioSpace.m)
                ZStack {
                    Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [2, 4])).frame(width: 170, height: 170)
                    // The deep oxblood (not the lifted dark-mode accent), so cream stays readable.
                    Circle().fill(record.winner == 0 ? Color.ratioCommitFill : Color.ratioSunk).frame(width: 144, height: 144)
                    Text("R.").ratioFont(.displayAccent)
                        .foregroundStyle(record.winner == 0 ? Color.ratioOnInk : Color.ratioInk)
                }
                .accessibilityHidden(true)
                headline.ratioFont(.display).multilineTextAlignment(.center)
                if record.forfeited == true {
                    Text(record.winner == 0 ? "\(record.opponent.name) left the duel." : "You left the duel.")
                        .ratioFont(.small)
                        .foregroundStyle(Color.ratioInk2)
                }
                Text("\(record.score[0]) – \(record.score[1]) · v \(record.opponentTitle)")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .multilineTextAlignment(.center)
                details
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.bottom, RatioSpace.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: RatioSpace.xs) {
                RatioButton(record.isSparring ? "Rematch" : "Challenge \(record.opponent.name.components(separatedBy: " ").first ?? "them") to a rematch", action: rematch)
                RatioButton("See the debrief", style: .tertiary, action: debrief)
                RatioButton("Back to chambers", style: .link, action: close)
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.xs)
            .background(Color.ratioParchment)
        }
        .ratioPage()
        .environment(\.colorScheme, .dark)
    }

    private var details: some View {
        VStack(spacing: 0) {
            row("Rating · \(DuelScope.title(of: record.moduleId))") {
                let delta = record.ratingAfter - record.ratingBefore
                Text("\(record.ratingBefore.formatted()) → \(record.ratingAfter.formatted()) \(Text(delta >= 0 ? "+\(delta)" : "\(delta)").foregroundStyle(delta >= 0 ? Color.ratioVerdigris : Color.ratioOxblood))")
                    .ratioFont(.monoData)
            }
            if let fastest {
                row("Fastest point") {
                    Text("\(String(format: "%.1f", Double(fastest.time) / 1000)) s · \(Text(fastest.answer).italic())").ratioFont(.small)
                }
            }
            if let moved = record.skillMoved, let skill = Skill(rawValue: moved.skill) {
                row("Skill moved") {
                    Text("\(skill.title) · \(topicTitle(moved.topicId)) \(moved.before.displayScore) → \(moved.after.displayScore)")
                        .ratioFont(.small)
                }
            }
            Divider().overlay(Color.ratioRule)
        }
    }

    private var headline: Text {
        switch record.winner {
        case 0: Text("You won the \(Text("duel.").italic().foregroundStyle(Color.ratioOxblood))")
        case 1: Text("Not this \(Text("time.").italic().foregroundStyle(Color.ratioOxblood))")
        default: Text("Honours \(Text("even.").italic().foregroundStyle(Color.ratioOxblood))")
        }
    }

    private var fastest: (time: Int, answer: String)? {
        record.rounds
            .filter { $0.winner == 0 && $0.answers[0].correct }
            .min { $0.answers[0].timeMs < $1.answers[0].timeMs }
            .flatMap { round in
                record.questions[safe: round.questionIndex].map { (round.answers[0].timeMs, $0.options[$0.correctIndex]) }
            }
    }

    private func topicTitle(_ topicId: String) -> String {
        Module(topicId: topicId).flatMap { content.lessons(in: $0).first { $0.topicId == topicId }?.title } ?? TopicGroup.title(forTopic: topicId)
    }

    /// Label and value side by side; stacked at accessibility sizes.
    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.ratioRule)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RatioSpace.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: RatioSpace.s))
            layout {
                Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                if !typeSize.isAccessibilitySize { Spacer(minLength: RatioSpace.xs) }
                value().multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, RatioSpace.s)
            .accessibilityElement(children: .combine)
        }
    }
}
