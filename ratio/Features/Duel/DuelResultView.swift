import SwiftUI

/// screens/37-result-win.png and 38-result-loss.png — "Judgment entered".
struct DuelResultView: View {
    let record: DuelRecord
    /// Sparring: another match at the same level. Against a student: an async challenge.
    let rematch: () -> Void
    let debrief: () -> Void
    let close: () -> Void

    @Environment(ContentStore.self) private var content


    var body: some View {
        VStack(spacing: 24) {
            Text("Judgment entered").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).padding(.top, 24)
            ZStack {
                Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [2, 4])).frame(width: 170, height: 170)
                Circle().fill(record.winner == 0 ? Color.ratioOxblood : Color.ratioSunk).frame(width: 144, height: 144)
                Text("R.").font(.custom("NewsreaderDisplay-Italic", size: 64, relativeTo: .largeTitle))
                    .foregroundStyle(record.winner == 0 ? Color.ratioOnInk : Color.ratioInk)
            }
            .accessibilityHidden(true)
            headline.ratioFont(.display).multilineTextAlignment(.center)
            if record.forfeited == true {
                Text(record.winner == 0 ? "\(record.opponent.name) left the match." : "You left the match.")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            Text("\(record.score[0]) – \(record.score[1]) · v \(record.opponentTitle)")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            VStack(spacing: 0) {
                row("Rating · \(DuelScope.title(of: record.moduleId))") {
                    let delta = record.ratingAfter - record.ratingBefore
                    Text("\(record.ratingBefore.formatted()) → \(record.ratingAfter.formatted()) \(Text(delta >= 0 ? "+\(delta)" : "\(delta)").foregroundStyle(delta >= 0 ? Color.ratioVerdigris : Color.ratioOxblood))")
                        .ratioFont(.monoData)
                }
                if let fastest {
                    row("Fastest point") {
                        Text("\(String(format: "%.1f", Double(fastest.time) / 1000)) s · \(Text(fastest.answer).italic())").ratioFont(.small).lineLimit(1)
                    }
                }
                if let moved = record.skillMoved, let skill = Skill(rawValue: moved.skill) {
                    row("Skill moved") {
                        Text("\(skill.title) · \(topicTitle(moved.topicId)) \(moved.before.displayScore) → \(moved.after.displayScore)")
                            .ratioFont(.small)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer()
            VStack(spacing: 12) {
                RatioButton(record.isSparring ? "Rematch" : "Challenge \(record.opponent.name.components(separatedBy: " ").first ?? "them") to a rematch", action: rematch)
                RatioButton("See the debrief", style: .tertiary, action: debrief)
                RatioButton("Back to chambers", style: .link, action: close)
            }
        }
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .environment(\.colorScheme, .dark)
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

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.ratioRule)
            HStack(spacing: 16) {
                Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer()
                value()
            }
            .padding(.vertical, 16)
        }
    }
}
