import Foundation

/// One sparring match (or the tutorial) from start to judgment. Rounds are revealed
/// locally with `DuelRules`; the finished match is refereed by `submitSparring`.
@Observable
final class DuelMatchModel: DuelRoundModel {
    enum Phase: Equatable {
        case loading, failed, versus, coaching, playing, revealing, submitting, submitFailed, finished
    }

    let scope: DuelScope
    let level: Int
    let seconds: Int
    let isTutorial: Bool

    private(set) var match: SparringMatch?
    private(set) var phase: Phase = .loading
    private(set) var score = [0, 0]
    private(set) var played: [DuelPlayed] = []
    /// The question being played.
    private(set) var current: Int?
    private(set) var roundStart = Date.now
    private(set) var yourAnswer: DuelAnswer?
    private(set) var result: SparringResult?
    /// The free plan's duels are used up for today.
    private(set) var hitFreeLimit = false
    /// Bumped once a second in the last three seconds, for the haptic pulse.
    private(set) var pulse = 0

    @ObservationIgnored private var regularPlayed = 0
    @ObservationIgnored private var finalPlayed = false
    @ObservationIgnored private var clock: Task<Void, Never>?

    init(scope: DuelScope, level: Int, seconds: Int, isTutorial: Bool) {
        self.scope = scope
        self.level = level
        self.seconds = seconds
        self.isTutorial = isTutorial
    }

    var limitMs: Int { match?.limitMs ?? seconds * 1000 }
    var question: DuelQuestion? { current.flatMap { match?.questions[safe: $0] } }
    var lastPlayed: DuelPlayed? { played.last }

    var roundPhase: DuelRoundPhase {
        switch phase {
        case .coaching: .coaching
        case .playing: .playing
        case .revealing: .revealing
        default: .waiting
        }
    }

    var roundNumber: Int { played.count + (phase == .revealing ? 0 : 1) }
    var labelPrefix: String { isTutorial ? "Practice · " : "" }
    var opponent: DuelOpponent { .sparring(level: level) }

    func opponentLocked(at date: Date) -> Bool { partnerLocked(at: date) }

    func load() async {
        phase = .loading
        do {
            match = try await DuelService.startSparring(scope: scope, level: level, seconds: seconds, tutorial: isTutorial)
            if isTutorial {
                prepareRound()
                phase = .coaching
            } else {
                phase = .versus
            }
        } catch {
            hitFreeLimit = PlanService.isFreeLimit(error)
            phase = .failed
        }
    }

    /// From the versus screen, or once the tutorial's coach marks are done.
    func begin() {
        if phase == .coaching {
            startClock()
        } else {
            nextRound()
        }
    }

    func answer(_ index: Int) {
        guard phase == .playing, yourAnswer == nil else { return }
        let elapsed = Int((Date.now.timeIntervalSince(roundStart) * 1000).rounded())
        endRound(with: DuelAnswer(answerIndex: index, timeMs: elapsed))
    }

    /// Whether the partner has locked in by `date`.
    func partnerLocked(at date: Date) -> Bool {
        guard let current, let plan = match?.plan[safe: current], plan.answerIndex != nil else { return false }
        return date.timeIntervalSince(roundStart) * 1000 >= Double(plan.timeMs)
    }

    func stop() {
        clock?.cancel()
    }

    func submit() async {
        guard let match else { return }
        guard let matchId = match.matchId else {
            phase = .finished // The tutorial isn't refereed or rated.
            return
        }
        phase = .submitting
        do {
            result = try await DuelService.submitSparring(matchId: matchId, answers: played.map(\.you))
            phase = .finished
            ActivityRepository.markToday()
        } catch {
            phase = .submitFailed
        }
    }

    // MARK: Rounds

    private func prepareRound() {
        guard let match,
              let next = DuelRules.nextQuestion(in: match.questions, score: score, regularPlayed: regularPlayed, finalPlayed: finalPlayed) else {
            current = nil
            return
        }
        if match.questions[next].isFinal { finalPlayed = true } else { regularPlayed += 1 }
        current = next
        yourAnswer = nil
    }

    private func nextRound() {
        prepareRound()
        if current == nil {
            Task { await submit() }
        } else {
            startClock()
        }
    }

    private func startClock() {
        roundStart = .now
        phase = .playing
        let limit = Double(limitMs) / 1000
        let start = roundStart
        clock?.cancel()
        clock = Task { [weak self] in
            for second in stride(from: limit - 3, to: limit, by: 1) {
                try? await Task.sleep(until: .now + .seconds(max(0, start.addingTimeInterval(second).timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.pulse += 1
            }
            try? await Task.sleep(until: .now + .seconds(max(0, start.addingTimeInterval(limit).timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.endRound(with: DuelAnswer(answerIndex: nil, timeMs: self?.limitMs ?? 10_000))
        }
    }

    private func endRound(with answer: DuelAnswer) {
        guard phase == .playing, let match, let current else { return }
        clock?.cancel()
        yourAnswer = answer
        let them = match.plan[safe: current] ?? DuelAnswer(answerIndex: nil, timeMs: limitMs)
        let winner = DuelRules.winner(of: match.questions[current], you: answer, them: them, limitMs: limitMs)
        if let winner { score[winner] += 1 }
        played.append(DuelPlayed(questionIndex: current, you: answer, them: them, winner: winner))
        phase = .revealing
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.nextRound()
        }
    }
}
