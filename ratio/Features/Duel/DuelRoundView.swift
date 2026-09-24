import SwiftUI

/// screens/35-round-fastest-finger.png and 36-final-round-spot-the-issue.png — the
/// scoreboard with both scores and the timer ring, then the question. A tap locks the
/// answer; the round is revealed once the student answers or time runs out. On iPad
/// (screens/iPad/5-duel/05): the question on the left, "Match so far" on the right.
struct DuelRoundView: View {
    let model: any DuelRoundModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ratioWidth) private var width

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            Scoreboard(model: model)
            if let question = model.question {
                if width.isCompact {
                    prompt(question)
                    ScrollView {
                        answers(question).padding(.bottom, RatioSpace.m)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView {
                        ColumnsLayout(fraction: 0.68, spacing: RatioSpace.l) {
                            VStack(alignment: .leading, spacing: RatioSpace.m) {
                                prompt(question)
                                answers(question)
                            }
                            MatchSoFar(model: model)
                        }
                        .padding(.bottom, RatioSpace.m)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(.horizontal, RatioSpace.m)
        .padding(.top, RatioSpace.xs)
        .animation(RatioMotion.reveal, value: model.roundPhase)
        .ratioFeedback(.impact(weight: .medium), trigger: model.pulse)
        .ratioFeedback(trigger: model.lastPlayed) { _, played in
            guard let played else { return nil }
            return played.winner == 0 ? .success : played.winner == 1 ? .error : .warning
        }
    }

    private func prompt(_ question: DuelQuestion) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text(label(question))
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            Text(question.kind == .spotTheIssue && question.prompt.isEmpty ? "Tap the phrase that decides the case." : question.prompt)
                .ratioFont(question.kind == .nameTheCase ? .h3 : .h2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answers(_ question: DuelQuestion) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            if question.kind == .spotTheIssue, let segments = question.segments {
                SpotTheIssueCard(question: question, segments: segments, model: model)
            } else {
                OptionGrid(question: question, model: model)
            }
            Text(footer)
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            KeyHint(keys: "1–\(max(1, question.options.count))", label: "Choose")
                .frame(maxWidth: .infinity)
            if model.roundPhase == .revealing, let played = model.lastPlayed {
                RevealBanner(message: model.revealMessage(played, question: question))
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

    private func label(_ question: DuelQuestion) -> String {
        let skill = Skill(rawValue: question.skill)?.title ?? question.skill
        let round = question.isFinal ? "Final round" : "Round \(Self.numerals[safe: model.roundNumber - 1] ?? "\(model.roundNumber)")"
        return "\(model.labelPrefix)\(round) · \(question.kind.title) · \(skill)"
    }

    private var footer: String {
        if model.showsScore && model.score == [DuelRules.pointsToWin - 1, DuelRules.pointsToWin - 1] && model.roundPhase != .revealing {
            return "Tap locks your answer · \(model.score[0]) – \(model.score[1]), next point wins"
        }
        return "Tap locks your answer · First right answer takes the point"
    }
}

/// You, the timer, and the sparring partner — Liquid Glass over the paper.
private struct Scoreboard: View {
    let model: any DuelRoundModel

    @Environment(StudentStore.self) private var student
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            Group {
                // At accessibility sizes: both players on their own lines, the timer beneath.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        you
                        opponent(at: context.date)
                        timer(at: context.date).frame(maxWidth: .infinity)
                    }
                } else {
                    HStack(spacing: RatioSpace.xs) {
                        you
                        Spacer(minLength: RatioSpace.xxs)
                        timer(at: context.date)
                        Spacer(minLength: RatioSpace.xxs)
                        opponent(at: context.date)
                    }
                }
            }
            .padding(RatioSpace.s)
            .ratioGlassCard(cornerRadius: RatioRadius.card)
            .overlay { RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous).strokeBorder(Color.ratioRule) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.showsScore ? "You \(model.score[0]), \(model.opponent.name) \(model.score[1])" : "You against \(model.opponent.name)")
    }

    private var you: some View {
        HStack(spacing: RatioSpace.xs) {
            ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 44)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text("You").ratioFont(.h3)
                if model.showsScore { Points(score: model.score[0]) }
            }
        }
    }

    private func timer(at date: Date) -> some View {
        TimerRing(remaining: remaining(at: date), limit: Double(model.limitMs) / 1000)
    }

    private func opponent(at date: Date) -> some View {
        HStack(spacing: RatioSpace.xs) {
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: RatioSpace.xxs) {
                Text(model.opponent.name).ratioFont(.small).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                Text(model.opponent.detail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                if model.showsScore { Points(score: model.score[1]) }
            }
            OpponentMark(opponent: model.opponent, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if model.roundPhase == .playing && model.opponentLocked(at: date) {
                        Text("Locked in")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioOxblood)
                            .padding(.horizontal, RatioSpace.xs)
                            .padding(.vertical, 2)
                            .background(Color.ratioPaper, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.ratioOxblood))
                            .rotationEffect(.degrees(-8))
                            .fixedSize()
                            .offset(x: 10, y: 14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
        }
    }

    private func remaining(at date: Date) -> Double {
        let limit = Double(model.limitMs) / 1000
        switch model.roundPhase {
        case .playing: return max(0, min(limit, limit - date.timeIntervalSince(model.roundStart)))
        case .revealing: return max(0, limit - Double(model.lastPlayed?.you.timeMs ?? model.limitMs) / 1000)
        default: return limit
        }
    }
}

/// Three dots, filled for points won.
struct Points: View {
    let score: Int

    var body: some View {
        HStack(spacing: RatioSpace.xxs) {
            ForEach(0..<DuelRules.pointsToWin, id: \.self) { index in
                Circle()
                    .fill(index < score ? Color.ratioInk : Color.clear)
                    .overlay(Circle().strokeBorder(Color.ratioInk, lineWidth: 1.2))
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The countdown: ink, turning oxblood in the last three seconds.
private struct TimerRing: View {
    let remaining: Double
    let limit: Double

    var body: some View {
        let urgent = remaining <= 3 && remaining > 0
        ZStack {
            Circle().stroke(Color.ratioRule, lineWidth: 5)
            Circle()
                .trim(from: 0, to: limit > 0 ? remaining / limit : 0)
                .stroke(urgent ? Color.ratioOxblood : Color.ratioInk, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(remaining.rounded(.up)))")
                .ratioFont(.h2)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .foregroundStyle(urgent ? Color.ratioOxblood : Color.ratioInk)
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
    }
}

/// The sparring partner's mark: concentric rings, never a face (PRD: "always labelled").
struct SparringMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.ratioInk, lineWidth: 1.2)
            Circle().strokeBorder(Color.ratioInk, lineWidth: 1.2).padding(size * 0.18)
            Circle().fill(Color.ratioInk).frame(width: size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The opponent's mark: rings for a sparring partner, their avatar for a student.
struct OpponentMark: View {
    let opponent: DuelOpponent
    var size: CGFloat = 44

    var body: some View {
        if opponent.isBot {
            SparringMark(size: size)
        } else {
            ProfilePhoto(uid: opponent.uid ?? opponent.name, initial: opponent.initial, version: opponent.avatarVersion, size: size)
        }
    }
}

/// Fastest finger and Name the case: four options in a 2×2 grid.
private struct OptionGrid: View {
    let question: DuelQuestion
    let model: any DuelRoundModel
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Two columns, or one at accessibility sizes so options never cramp.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: RatioSpace.s), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: RatioSpace.s) {
            ForEach(question.options.indices, id: \.self) { index in
                Button { model.answer(index) } label: {
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        HStack {
                            Text(Self.letter(index)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Spacer()
                            OptionMarker(state: state(index))
                        }
                        Text(question.options[index])
                            .ratioFont(question.options[index].count > 60 ? .small : .body)
                            .italic(question.kind != .fastestFinger || isCaseName(question.options[index]))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(RatioSpace.s)
                    .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 44 : 120, alignment: .topLeading)
                    .background(state(index).fill, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(state(index).border, lineWidth: state(index) == .plain ? 1 : 2) }
                }
                .buttonStyle(.plain)
                .disabled(model.roundPhase != .playing || model.yourAnswer != nil)
                .keyboardShortcut(numberKey(index), modifiers: [])
                .accessibilityLabel("\(Self.letter(index)): \(question.options[index])\(state(index).spoken)")
            }
        }
    }

    static func letter(_ index: Int) -> String { String(Character(UnicodeScalar(UInt8(65 + min(index, 25))))) }

    private func isCaseName(_ text: String) -> Bool { text.contains(" v ") || text.hasPrefix("R v") || text.hasPrefix("Re ") }

    private func state(_ index: Int) -> OptionState {
        OptionState(index: index, question: question, model: model)
    }
}

/// Spot the issue: the scenario phrase by phrase; the tappable ones are the answers.
private struct SpotTheIssueCard: View {
    let question: DuelQuestion
    let segments: [DuelQuestion.Segment]
    let model: any DuelRoundModel

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if let option = segment.option {
                    let state = OptionState(index: option, question: question, model: model)
                    Button { model.answer(option) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(segment.text).ratioFont(.body).multilineTextAlignment(.leading)
                            Spacer(minLength: RatioSpace.xs)
                            OptionMarker(state: state)
                        }
                        .padding(.horizontal, RatioSpace.s)
                        .padding(.vertical, RatioSpace.xs)
                        .frame(minHeight: 44)
                        .background(state.fill, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).strokeBorder(state == .plain ? Color.ratioRule : state.border) }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.roundPhase != .playing || model.yourAnswer != nil)
                    .keyboardShortcut(numberKey(option), modifiers: [])
                    .accessibilityLabel("\(segment.text)\(state.spoken)")
                } else {
                    Text(segment.text).ratioFont(.body).foregroundStyle(Color.ratioInk2).padding(.horizontal, RatioSpace.s)
                }
            }
        }
        .ratioCard(padding: RatioSpace.s)
    }
}

/// How an option looks: plain while playing; once revealed, the right answer, the
/// student's wrong pick, and the partner's pick are marked — with icons, not colour alone.
private enum OptionState: Equatable {
    case plain, chosen, correct, wrong, partner

    init(index: Int, question: DuelQuestion, model: any DuelRoundModel) {
        let yours = model.yourAnswer?.answerIndex == index
        guard model.roundPhase == .revealing, let played = model.lastPlayed else {
            self = yours ? .chosen : .plain
            return
        }
        if index == question.correctIndex { self = .correct }
        else if yours { self = .wrong }
        else if played.them.answerIndex == index && DuelRules.counts(played.them, limitMs: model.limitMs) { self = .partner }
        else { self = .plain }
    }

    var fill: Color {
        switch self {
        case .correct: .ratioVWash
        case .wrong: .ratioOxWash
        default: .ratioPaper
        }
    }

    var border: Color {
        switch self {
        case .plain: .ratioRule
        case .chosen: .ratioInk
        case .correct: .ratioVerdigris
        case .wrong: .ratioOxblood
        case .partner: .ratioInk2
        }
    }

    var spoken: String {
        switch self {
        case .plain: ""
        case .chosen: ", your answer"
        case .correct: ", correct answer"
        case .wrong: ", your answer, wrong"
        case .partner: ", opponent's answer"
        }
    }
}

private struct OptionMarker: View {
    let state: OptionState

    var body: some View {
        switch state {
        case .correct: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ratioVerdigris)
        case .wrong: Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ratioOxblood)
        case .partner: SparringMark(size: 16)
        case .chosen: Image(systemName: "lock.fill").imageScale(.small).foregroundStyle(Color.ratioInk)
        case .plain: EmptyView()
        }
    }
}

/// Who took the point, and why.
private struct RevealBanner: View {
    let message: (text: String, good: Bool?)

    var body: some View {
        Label(message.text, systemImage: message.good == true ? "checkmark" : message.good == false ? "xmark" : "clock")
            .ratioFont(.h3)
            .foregroundStyle(message.good == true ? Color.ratioVerdigris : message.good == false ? Color.ratioOxblood : Color.ratioInk2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, RatioSpace.xs)
    }
}

/// Keys 1–9 choose an option with a hardware keyboard.
private func numberKey(_ index: Int) -> KeyEquivalent {
    KeyEquivalent(Character(String(min(index + 1, 9))))
}

/// iPad: the score and every round so far, with the one in play (screens/iPad/5-duel/05).
private struct MatchSoFar: View {
    let model: any DuelRoundModel

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Match so far").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if model.showsScore {
                Text("\(model.score[0]) – \(model.score[1])").ratioFont(.figure)
                Text("You v \(model.opponent.isBot ? "sparring partner" : model.opponent.name) · first to \(DuelRules.pointsToWin)")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
            }
            VStack(spacing: 0) {
                ForEach(Array(model.history.enumerated()), id: \.element.id) { index, round in
                    Divider().overlay(Color.ratioRule)
                    row(round, scoreAfter: scores[index])
                }
                if model.roundPhase == .playing, let question = model.question {
                    Divider().overlay(Color.ratioRule)
                    HStack(alignment: .top, spacing: RatioSpace.s) {
                        Text(DuelRoundView.numerals[safe: model.roundNumber - 1] ?? "\(model.roundNumber)")
                            .ratioFont(.monoData)
                            .foregroundStyle(Color.ratioParchment)
                            .frame(width: 36, height: 36)
                            .background(Color.ratioInk, in: Circle())
                        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                            Text("\(title(model.roundNumber, final: question.isFinal)) · \(question.kind.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Text("In play").ratioFont(.h3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, RatioSpace.s)
                }
                Divider().overlay(Color.ratioRule)
            }
            Text("Every round comes back in your debrief, with the reasoning.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
                .padding(.top, RatioSpace.xs)
        }
        .ratioCard()
        .accessibilityElement(children: .contain)
    }

    /// The running score after each round.
    private var scores: [[Int]] {
        var score = [0, 0]
        return model.history.map { round in
            if let winner = round.played.winner { score[winner] += 1 }
            return score
        }
    }

    private func title(_ number: Int, final: Bool) -> String {
        final ? "Final round" : "Round \(DuelRoundView.numerals[safe: number - 1] ?? "\(number)")"
    }

    private func row(_ round: DuelRoundSummary, scoreAfter: [Int]) -> some View {
        let seconds = { (ms: Int) in String(format: "%.1f", Double(ms) / 1000) }
        let won = round.played.winner == 0
        let lost = round.played.winner == 1
        let who = won ? "You" : lost ? (model.opponent.isBot ? "Partner" : model.opponent.name) : "No point"
        let detail = round.played.you.answerIndex == nil
            ? "No answer"
            : "\(won ? "Correct" : "Not quite") · \(seconds(round.played.you.timeMs))\u{00A0}s"
        let tint = won ? Color.ratioVerdigris : lost ? Color.ratioOxblood : Color.ratioInk2
        return HStack(alignment: .top, spacing: RatioSpace.s) {
            Image(systemName: won ? "checkmark" : lost ? "xmark" : "minus")
                .font(.footnote)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(tint))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text("\(title(round.id, final: round.isFinal)) · \(round.kind.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text(model.showsScore ? "\(who) · \(scoreAfter[0])–\(scoreAfter[1])" : who).ratioFont(.h3)
                Text(detail).ratioFont(.monoData).foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, RatioSpace.s)
        .accessibilityElement(children: .combine)
    }
}
