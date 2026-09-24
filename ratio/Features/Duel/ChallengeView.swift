import SwiftUI

/// One student's half of an async challenge (PRD: "They have 24 h to play their half").
/// Every question is answered in turn and marked straight away; the rounds are decided
/// once both halves are in, by the same rules as a live match.
@Observable
final class ChallengeHalfModel: DuelRoundModel {
    enum Phase: Equatable {
        case loading, round, halfDone, finished, failed(String)
    }

    let challengeId: String
    let opponent: DuelOpponent

    private(set) var phase: Phase = .loading
    private(set) var question: DuelQuestion?
    private(set) var index = 0
    private(set) var total = 9
    private(set) var limitMs = 10_000
    private(set) var yourAnswer: DuelAnswer?
    private(set) var lastPlayed: DuelPlayed?
    private(set) var roundStart = Date.now
    private(set) var revealing = false
    private(set) var pulse = 0
    private(set) var record: DuelRecord?

    @ObservationIgnored private var clock: Task<Void, Never>?

    init(challengeId: String, opponent: DuelOpponent) {
        self.challengeId = challengeId
        self.opponent = opponent
    }

    var roundPhase: DuelRoundPhase {
        guard phase == .round else { return .waiting }
        return revealing ? .revealing : .playing
    }

    var roundNumber: Int { index + 1 }
    var score: [Int] { [0, 0] }
    var showsScore: Bool { false }
    var labelPrefix: String { "Challenge · " }

    func opponentLocked(at date: Date) -> Bool { false }

    func revealMessage(_ played: DuelPlayed, question: DuelQuestion) -> (text: String, good: Bool?) {
        if played.you.answerIndex == nil { return ("Time ran out.", nil) }
        return played.you.answerIndex == question.correctIndex
            ? ("Right — \(String(format: "%.1f", Double(played.you.timeMs) / 1000))\u{00A0}s.", true)
            : ("Not quite.", false)
    }

    func load() async {
        do {
            show(try await DuelService.playChallenge(id: challengeId, index: nil, answer: nil))
        } catch {
            phase = .failed((error as NSError).localizedDescription)
        }
    }

    func answer(_ choice: Int) {
        guard roundPhase == .playing, yourAnswer == nil else { return }
        submit(DuelAnswer(answerIndex: choice, timeMs: Int((Date.now.timeIntervalSince(roundStart) * 1000).rounded())))
    }

    func stop() { clock?.cancel() }

    private func submit(_ answer: DuelAnswer) {
        clock?.cancel()
        yourAnswer = answer
        Task {
            do {
                let step = try await DuelService.playChallenge(id: challengeId, index: index, answer: answer)
                reveal(step, answer: answer)
            } catch {
                phase = .failed((error as NSError).localizedDescription)
            }
        }
    }

    private func reveal(_ step: DuelService.ChallengeStep, answer: DuelAnswer) {
        if let revealed = step.revealed, var shown = question {
            shown.correctIndex = revealed.correctIndex
            shown.why = revealed.why
            question = shown
            lastPlayed = DuelPlayed(questionIndex: index, you: answer, them: DuelAnswer(answerIndex: nil, timeMs: limitMs),
                                    winner: revealed.correct ? 0 : nil)
            revealing = true
        }
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.show(step)
        }
    }

    private func show(_ step: DuelService.ChallengeStep) {
        total = step.total
        limitMs = step.limitMs
        if let result = step.result {
            record = result
            phase = .finished
            return
        }
        guard let next = step.question, let index = step.index else {
            phase = .halfDone
            return
        }
        self.index = index
        question = next
        yourAnswer = nil
        lastPlayed = nil
        revealing = false
        roundStart = .now
        phase = .round
        let limit = Double(limitMs) / 1000
        let start = roundStart
        clock = Task { [weak self] in
            for second in stride(from: limit - 3, to: limit, by: 1) {
                try? await Task.sleep(for: .seconds(max(0, start.addingTimeInterval(second).timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.pulse += 1
            }
            try? await Task.sleep(for: .seconds(max(0, start.addingTimeInterval(limit).timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, yourAnswer == nil else { return }
            submit(DuelAnswer(answerIndex: nil, timeMs: limitMs))
        }
    }
}

struct ChallengeView: View {
    let challenge: ChallengeSummary

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @State private var model: ChallengeHalfModel?
    @State private var showsDebrief = false
    @State private var sent: String?

    var body: some View {
        // Not a Group: with no model yet it would be empty, and the `.task` that loads
        // the challenge would never run.
        ZStack {
            if let model {
                switch model.phase {
                case .loading:
                    loading
                case .round:
                    VStack(spacing: 0) {
                        HStack {
                            RatioIconButton(systemImage: "xmark", label: "Pause — carry on later") { dismiss() }
                                .foregroundStyle(Color.ratioInk2)
                            Spacer()
                            Text("Question \(model.index + 1) of \(model.total)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        }
                        .padding(.horizontal, RatioSpace.s)
                        DuelRoundView(model: model)
                    }
                case .halfDone:
                    halfDone
                case .finished:
                    if let record = model.record {
                        if showsDebrief {
                            DuelDebriefView(record: record) {
                                dismiss()
                                navigator.backToToday()
                            } revisit: { lessonId in
                                dismiss()
                                navigator.pathwayPath = [.overview(lessonId)]
                                navigator.tab = .pathway
                            }
                        } else {
                            DuelResultView(record: record, rematch: { rematch(record) }, debrief: { showsDebrief = true }, close: { dismiss() })
                        }
                    }
                case .failed(let message):
                    VStack(spacing: RatioSpace.xs) {
                        RatioErrorState(message: message) { Task { await model.load() } }
                        Button("Close") { dismiss() }
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(RatioSpace.l)
                }
            } else {
                loading
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ratioPage()
        .task {
            guard model == nil else { return }
            let opponent = challenge.opponent(of: student.uid)
            let half = ChallengeHalfModel(challengeId: challenge.id, opponent: DuelOpponent(
                name: opponent.name, detail: challenge.done[opponent.uid] == true ? "Played their half" : "Plays later",
                isBot: false, uid: opponent.uid, initial: String(opponent.name.prefix(1)), avatarVersion: nil))
            model = half
            await half.load()
        }
        .onDisappear { model?.stop() }
        .alert("Challenge sent", isPresented: Binding(get: { sent != nil }, set: { if !$0 { sent = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sent ?? "")
        }
    }

    private var loading: some View {
        VStack(spacing: RatioSpace.s) {
            ProgressView()
            Text("Loading the challenge…").ratioFont(.small).foregroundStyle(Color.ratioInk2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var halfDone: some View {
        let opponent = challenge.opponent(of: student.uid)
        return VStack(alignment: .leading, spacing: RatioSpace.m) {
            Spacer()
            Text("Challenge · \(DuelScope.title(of: challenge.moduleId))").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("Your half is \(Text("in.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("\(opponent.name) has until \(challenge.expiresAt.formatted(.dateTime.weekday(.wide).hour().minute())) to play theirs. The rounds are decided then, and you'll see the result under Recent duels.")
                .ratioFont(.h3)
            Spacer()
            RatioButton("Done", style: .secondary) { dismiss() }
        }
        .padding(RatioSpace.m)
    }

    private func rematch(_ record: DuelRecord) {
        guard let opponent = record.opponent.uid, let scope = DuelScope(id: record.moduleId) else { return }
        Task {
            do {
                try await DuelService.createChallenge(opponent: opponent, scope: scope, seconds: record.limitMs / 1000)
                sent = "\(record.opponent.name) has 24 hours to play their half."
            } catch {
                sent = (error as NSError).localizedDescription
            }
        }
    }
}
