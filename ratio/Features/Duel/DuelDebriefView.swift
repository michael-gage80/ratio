import SwiftUI

/// screens/39-duel-debrief.png — every round with the student's answer, the right one
/// when they missed, one line of reasoning and a way back to the lesson; then speed and
/// accuracy head to head (PRD: "Debrief").
struct DuelDebriefView: View {
    let record: DuelRecord
    let backToToday: () -> Void
    let revisit: (String) -> Void

    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

    /// "Partner" or the opponent's first name, for the compact labels.
    private var them: String { record.isSparring ? "Partner" : record.opponent.name.components(separatedBy: " ").first ?? "Them" }

    private var misses: Int { record.rounds.count { !$0.answers[0].correct } }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                Text("Duel debrief · v \(record.opponent.name) · \(record.score[0])–\(record.score[1])")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("\(roundsText), \(Text(missesText).italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.h1)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, RatioSpace.xs)
                ForEach(Array(record.rounds.enumerated()), id: \.offset) { index, round in
                    if let question = record.questions[safe: round.questionIndex] {
                        roundCard(round, question: question, number: index, running: runningScore(through: index))
                    }
                }
                headToHead
                Text("Duel answers update your profile, not your review queue.")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                RatioButton("Back to Today", style: .secondary, action: backToToday)
            }
            .padding(RatioSpace.m)
        }
        .ratioPage()
    }

    private var roundsText: String {
        let words = ["No", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        let n = record.rounds.count
        return "\(words[safe: n] ?? "\(n)") \(n == 1 ? "round" : "rounds")"
    }

    private var missesText: String {
        switch misses {
        case 0: "no misses."
        case 1: "one miss."
        default: "\(misses) misses."
        }
    }

    private func runningScore(through index: Int) -> (Int, Int) {
        let upTo = record.rounds.prefix(index + 1)
        return (upTo.count { $0.winner == 0 }, upTo.count { $0.winner == 1 })
    }

    private func roundCard(_ round: SparringResult.RoundResult, question: DuelQuestion, number: Int, running: (Int, Int)) -> some View {
        let yours = round.answers[0]
        let skill = Skill(rawValue: question.skill)?.title ?? question.skill
        let who = round.winner == 0 ? "You" : round.winner == 1 ? them : "No point"
        let round = Text("\(question.isFinal ? "Final round" : "Round \(Self.numerals[safe: number] ?? "")") · \(question.kind.title) · \(skill)")
        let point = Text("\(who) · \(running.0)–\(running.1)")
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) {
                    round
                    Spacer(minLength: RatioSpace.s)
                    point
                }
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    round
                    point
                }
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)

            if let chosen = yours.answerIndex {
                answerRow(correct: yours.correct,
                          label: yours.correct ? "Correct · you \(seconds(yours.timeMs)) s" : "Not quite · you \(seconds(yours.timeMs)) s",
                          text: question.options[safe: chosen] ?? "")
            } else {
                answerRow(correct: false, label: "No answer", text: "Time ran out")
            }
            if !yours.correct {
                answerRow(correct: true, label: "Correct answer", text: question.options[question.correctIndex])
            }
            Text("\(Text("Why ·").foregroundStyle(Color.ratioInk2)) \(question.why)")
                .ratioFont(.small)
            if !yours.correct {
                Button { revisit(question.lessonId) } label: {
                    Text("Revisit the lesson →").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.ratioPress)
            }
        }
        .ratioCard()
    }

    private func answerRow(correct: Bool, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: RatioSpace.xs) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? Color.ratioVerdigris : Color.ratioOxblood)
                .font(.title3)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text(label).ratioFont(.monoLabel).foregroundStyle(correct ? Color.ratioVerdigris : Color.ratioOxblood)
                Text(text).ratioFont(.body).italic()
            }
        }
        .ratioPanel(correct ? Color.ratioVWash : Color.ratioOxWash)
        .accessibilityElement(children: .combine)
    }

    // MARK: Head to head

    private var headToHead: some View {
        let answered = { (player: Int) in record.rounds.map { $0.answers[player] }.filter { $0.answerIndex != nil && $0.timeMs <= record.limitMs } }
        let speed = { (player: Int) -> Double? in
            let times = answered(player).map { Double($0.timeMs) / 1000 }
            return times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
        }
        let accuracy = { (player: Int) in record.rounds.count { $0.answers[player].correct } }
        let total = record.rounds.count
        let limit = Double(record.limitMs) / 1000
        let legend = HStack(spacing: RatioSpace.s) {
            Label("You", systemImage: "square.fill").foregroundStyle(Color.ratioInk)
            Label(them, systemImage: "square.fill").foregroundStyle(Color.ratioInk2)
        }
        .accessibilityHidden(true)
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Head to head").foregroundStyle(Color.ratioInk2)
                    Spacer()
                    legend
                }
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Head to head").foregroundStyle(Color.ratioInk2)
                    legend
                }
            }
            .ratioFont(.monoLabel)
            comparison("Average speed", note: "Shorter is quicker",
                       you: speed(0).map { ($0 / limit, String(format: "%.1f s", $0)) },
                       them: speed(1).map { ($0 / limit, String(format: "%.1f s", $0)) })
            comparison("Accuracy", note: "Right answers",
                       you: (Double(accuracy(0)) / Double(max(total, 1)), "\(accuracy(0))/\(total)"),
                       them: (Double(accuracy(1)) / Double(max(total, 1)), "\(accuracy(1))/\(total)"))
        }
        .ratioCard()
    }

    private func comparison(_ title: String, note: String, you: (Double, String)?, them: (Double, String)?) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).ratioFont(.h3)
                    Spacer()
                    Text(note).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(title).ratioFont(.h3)
                    Text(note).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
            }
            bar("You", value: you, color: .ratioInk)
            bar(self.them, value: them, color: .ratioInk2)
        }
    }

    /// Who, the bar and the figure on one line; at accessibility sizes the label sits above.
    private func bar(_ who: String, value: (Double, String)?, color: Color) -> some View {
        let track = GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ratioSunk)
                Capsule().fill(color).frame(width: proxy.size.width * min(1, value?.0 ?? 0))
            }
        }
        .frame(height: 8)
        let figure = Text(value?.1 ?? "—").ratioFont(.monoData).fixedSize()
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(who).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    HStack(spacing: RatioSpace.xs) { track; figure }
                }
            } else {
                HStack(spacing: RatioSpace.s) {
                    Text(who).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(width: 64, alignment: .leading)
                    track
                    figure.frame(minWidth: 56, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who): \(value?.1 ?? "no answers")")
    }

    private func seconds(_ ms: Int) -> String { String(format: "%.1f", Double(ms) / 1000) }
}
