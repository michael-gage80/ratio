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
    @Environment(\.ratioWidth) private var width

    var body: some View {
        if width.isCompact { compact } else { wide }
    }

    /// iPad (screens/iPad/5-duel/07-result-win.png): the judgment and figures on the left;
    /// round by round and what next on the right.
    private var wide: some View {
        ScrollView {
            ColumnsLayout(fraction: 0.5, spacing: RatioSpace.xl) {
                VStack(spacing: RatioSpace.m) {
                    judgment
                    details
                }
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Round by round").ratioFont(.h1)
                        Spacer(minLength: RatioSpace.xs)
                        Text("\(DuelScope.title(of: record.moduleId)) · First to 3").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    }
                    roundByRound
                    HStack(spacing: RatioSpace.s) {
                        RatioButton(rematchTitle, action: rematch)
                            .keyboardShortcut(.return, modifiers: .command)
                        RatioButton("See the debrief", style: .tertiary, action: debrief)
                    }
                    HStack {
                        RatioButton("Back to chambers", style: .link, action: close)
                            .keyboardShortcut(.cancelAction)
                        Spacer()
                        KeyHint(keys: "⌘↩", label: "Rematch")
                    }
                }
            }
            .padding(RatioSpace.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .ratioPage()
        .environment(\.colorScheme, .dark)
    }

    private var rematchTitle: String {
        record.isSparring ? "Rematch" : "Challenge \(record.opponent.name.components(separatedBy: " ").first ?? "them") to a rematch"
    }

    private var judgment: some View {
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
        }
    }

    /// Each round: who took the point, the answer, and the time.
    private var roundByRound: some View {
        let them = record.isSparring ? "Partner" : record.opponent.name.components(separatedBy: " ").first ?? "Them"
        var running = (0, 0)
        let rows: [(number: Int, question: DuelQuestion, round: SparringResult.RoundResult, score: (Int, Int))] = record.rounds.enumerated().compactMap { index, round in
            guard let question = record.questions[safe: round.questionIndex] else { return nil }
            if round.winner == 0 { running.0 += 1 } else if round.winner == 1 { running.1 += 1 }
            return (index, question, round, running)
        }
        return VStack(spacing: 0) {
            ForEach(rows, id: \.number) { row in
                if row.number > 0 { Divider().overlay(Color.ratioRule) }
                let won = row.round.winner == 0
                let lost = row.round.winner == 1
                let tint = won ? Color.ratioVerdigris : lost ? Color.ratioOxblood : Color.ratioInk2
                let yours = row.round.answers[0]
                HStack(alignment: .top, spacing: RatioSpace.s) {
                    Image(systemName: won ? "checkmark" : lost ? "xmark" : "minus")
                        .font(.footnote)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(tint))
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text("\(row.question.isFinal ? "Final round" : "Round \(DuelRoundView.numerals[safe: row.number] ?? "\(row.number + 1)")") · \(row.question.kind.title)")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                        Text(row.question.options[safe: row.question.correctIndex] ?? "").ratioFont(.body).italic()
                    }
                    Spacer(minLength: RatioSpace.xs)
                    VStack(alignment: .trailing, spacing: RatioSpace.xxs) {
                        Text("\(won ? "You" : lost ? them : "No point") · \(row.score.0)–\(row.score.1)").ratioFont(.h3)
                        Text(yours.answerIndex == nil ? "No answer" : "\(yours.correct ? "Correct" : "Not quite") · \(String(format: "%.1f", Double(yours.timeMs) / 1000))\u{00A0}s")
                            .ratioFont(.monoData)
                            .foregroundStyle(tint)
                    }
                }
                .padding(.vertical, RatioSpace.s)
                .accessibilityElement(children: .combine)
            }
        }
        .ratioCard(Color.ratioSunk, padding: RatioSpace.s)
    }

    private var compact: some View {
        ScrollView {
            VStack(spacing: RatioSpace.m) {
                judgment
                details
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.bottom, RatioSpace.m)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: RatioSpace.xs) {
                RatioButton(rematchTitle, action: rematch)
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
                    Text("\(String(format: "%.1f", Double(fastest.time) / 1000))\u{00A0}s · \(Text(fastest.answer).italic())").ratioFont(.small)
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
