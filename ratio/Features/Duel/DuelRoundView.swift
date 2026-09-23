import SwiftUI

/// screens/35-round-fastest-finger.png and 36-final-round-spot-the-issue.png — the
/// scoreboard with both scores and the timer ring, then the question. A tap locks the
/// answer; the round is revealed once the student answers or time runs out.
struct DuelRoundView: View {
    let model: DuelMatchModel

    @Environment(StudentStore.self) private var student
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Scoreboard(model: model)
            if let question = model.question {
                VStack(alignment: .leading, spacing: 14) {
                    Text(label(question))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    Text(question.kind == .spotTheIssue && question.prompt.isEmpty ? "Tap the phrase that decides the case." : question.prompt)
                        .ratioFont(question.kind == .nameTheCase ? .h3 : .h2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                        if model.phase == .revealing, let played = model.lastPlayed {
                            RevealBanner(played: played, question: question)
                                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.pulse)
        .sensoryFeedback(trigger: model.played.count) { _, _ in
            guard let winner = model.lastPlayed?.winner else { return .warning }
            return winner == 0 ? .success : .error
        }
    }

    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

    private func label(_ question: DuelQuestion) -> String {
        let skill = Skill(rawValue: question.skill)?.title ?? question.skill
        let round = question.isFinal ? "Final round" : "Round \(Self.numerals[safe: model.played.count - (model.phase == .revealing ? 1 : 0)] ?? "")"
        return "\(model.isTutorial ? "Practice · " : "")\(round) · \(question.kind.title) · \(skill)"
    }

    private var footer: String {
        if model.score == [DuelRules.pointsToWin - 1, DuelRules.pointsToWin - 1] && model.phase != .revealing {
            return "Tap locks your answer · \(model.score[0]) – \(model.score[1]), next point wins"
        }
        return "Tap locks your answer · First right answer takes the point"
    }
}

/// You, the timer, and the sparring partner — Liquid Glass over the paper.
private struct Scoreboard: View {
    let model: DuelMatchModel

    @Environment(StudentStore.self) private var student

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 0.1)) { context in
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You").ratioFont(.h3)
                        Points(score: model.score[0])
                    }
                }
                Spacer(minLength: 4)
                TimerRing(remaining: remaining(at: context.date), limit: Double(model.limitMs) / 1000)
                Spacer(minLength: 4)
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Sparring partner").ratioFont(.small).multilineTextAlignment(.trailing)
                        Text("Level \(model.level)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Points(score: model.score[1])
                    }
                    SparringMark(size: 44)
                        .overlay(alignment: .bottomTrailing) {
                            if model.phase == .playing && model.partnerLocked(at: context.date) {
                                Text("Locked in")
                                    .ratioFont(.monoLabel)
                                    .foregroundStyle(Color.ratioOxblood)
                                    .padding(.horizontal, 6)
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
            .padding(16)
            .ratioGlassCard(cornerRadius: 28)
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.ratioRule) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You \(model.score[0]), sparring partner \(model.score[1])")
    }

    private func remaining(at date: Date) -> Double {
        let limit = Double(model.limitMs) / 1000
        switch model.phase {
        case .playing: return max(0, limit - date.timeIntervalSince(model.roundStart))
        case .revealing: return max(0, limit - Double(model.lastPlayed?.you.timeMs ?? model.limitMs) / 1000)
        default: return limit
        }
    }
}

/// Three dots, filled for points won.
struct Points: View {
    let score: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<DuelRules.pointsToWin, id: \.self) { index in
                Circle()
                    .fill(index < score ? Color.ratioInk : Color.clear)
                    .overlay(Circle().strokeBorder(Color.ratioInk, lineWidth: 1.2))
                    .frame(width: 11, height: 11)
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
                .monospacedDigit()
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

/// Fastest finger and Name the case: four options in a 2×2 grid.
private struct OptionGrid: View {
    let question: DuelQuestion
    let model: DuelMatchModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            ForEach(question.options.indices, id: \.self) { index in
                Button { model.answer(index) } label: {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .background(state(index).fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(state(index).border, lineWidth: state(index) == .plain ? 1 : 2) }
                }
                .buttonStyle(.plain)
                .disabled(model.phase != .playing)
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
    let model: DuelMatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if let option = segment.option {
                    let state = OptionState(index: option, question: question, model: model)
                    Button { model.answer(option) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(segment.text).ratioFont(.body).multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            OptionMarker(state: state)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(state.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(state == .plain ? Color.ratioRule : state.border) }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.phase != .playing)
                    .accessibilityLabel("\(segment.text)\(state.spoken)")
                } else {
                    Text(segment.text).ratioFont(.body).foregroundStyle(Color.ratioInk2).padding(.horizontal, 12)
                }
            }
        }
        .padding(16)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
    }
}

/// How an option looks: plain while playing; once revealed, the right answer, the
/// student's wrong pick, and the partner's pick are marked — with icons, not colour alone.
private enum OptionState: Equatable {
    case plain, chosen, correct, wrong, partner

    init(index: Int, question: DuelQuestion, model: DuelMatchModel) {
        let yours = model.yourAnswer?.answerIndex == index
        guard model.phase == .revealing, let played = model.lastPlayed else {
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
        case .partner: ", partner's answer"
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
    let played: DuelMatchModel.Played
    let question: DuelQuestion

    var body: some View {
        let youAnswered = played.you.answerIndex != nil
        let youRight = played.you.answerIndex == question.correctIndex
        let text: String = switch played.winner {
        case 0: youRight ? "Your point — \(seconds(played.you.timeMs)) s." : "Your point — your partner answered wrong."
        case 1: youAnswered && !youRight && played.you.timeMs <= played.them.timeMs
            ? "Their point — a wrong answer gives it away."
            : "Their point — right in \(seconds(played.them.timeMs)) s."
        default: "No point — time ran out."
        }
        Label(text, systemImage: played.winner == 0 ? "checkmark" : played.winner == 1 ? "xmark" : "clock")
            .ratioFont(.h3)
            .foregroundStyle(played.winner == 0 ? Color.ratioVerdigris : played.winner == 1 ? Color.ratioOxblood : Color.ratioInk2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func seconds(_ ms: Int) -> String { String(format: "%.1f", Double(ms) / 1000) }
}
