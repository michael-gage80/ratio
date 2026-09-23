import FirebaseAuth
import FirebaseDatabase
import FirebaseFunctions
import Foundation

/// A live match against another student (PRD: "server-authoritative"). The referee
/// Functions own /live/{matchId}; this model follows its public view, shows each round
/// at the server's start time, sends answers and timeouts, and keeps the student's
/// presence so a dropped connection can be claimed after 45 seconds.
@Observable
final class LiveMatchModel: DuelRoundModel {
    enum Phase: Equatable {
        case connecting, countdown, round, settling, finished, failed
    }

    let matchId: String
    let uid: String

    private(set) var phase: Phase = .connecting
    private(set) var view: LivePublic?
    private(set) var question: DuelQuestion?
    private(set) var roundNumber = 0
    private(set) var yourAnswer: DuelAnswer?
    private(set) var lastPlayed: DuelPlayed?
    private(set) var roundStart = Date.distantFuture
    private(set) var revealing = false
    private(set) var pulse = 0
    private(set) var record: DuelRecord?
    /// When the opponent's connection dropped, if it has.
    private(set) var opponentGoneSince: Date?

    @ObservationIgnored private var serverOffsetMs: Double = 0
    @ObservationIgnored private var handles: [(DatabaseReference, DatabaseHandle)] = []
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var claimTask: Task<Void, Never>?
    @ObservationIgnored private var revealedRound = 0

    init(matchId: String, uid: String) {
        self.matchId = matchId
        self.uid = uid
    }

    private var me: Int { view?.order.firstIndex(of: uid) ?? 0 }
    private var opponentUid: String? { view?.order.first { $0 != uid } }

    var limitMs: Int { view?.limitMs ?? 10_000 }
    var score: [Int] { view.map { [$0.score[safe: me] ?? 0, $0.score[safe: 1 - me] ?? 0] } ?? [0, 0] }
    var moduleId: String? { view?.moduleId }

    var roundPhase: DuelRoundPhase {
        guard phase == .round else { return .waiting }
        return revealing ? .revealing : .playing
    }

    var opponent: DuelOpponent {
        guard let opponentUid, let player = view?.players[opponentUid] else {
            return DuelOpponent(name: "Opponent", detail: "", isBot: false, uid: nil, initial: "?", avatarVersion: nil)
        }
        return DuelOpponent(name: player.name, detail: "Rating \(player.rating.formatted())", isBot: false, uid: opponentUid,
                            initial: player.initial, avatarVersion: player.avatarVersion)
    }

    /// When the first question appears, for the countdown.
    var firstRoundAt: Date? { view?.round.map { localDate($0.startsAt) } }

    func opponentLocked(at date: Date) -> Bool {
        view?.locked[safe: 1 - me] == true && view?.round?.number == roundNumber
    }

    // MARK: Connecting

    func start() {
        guard handles.isEmpty else { return }
        let db = Realtime.database
        let offset = db.reference(withPath: ".info/serverTimeOffset")
        handles.append((offset, offset.observe(.value) { [weak self] snapshot in
            self?.serverOffsetMs = snapshot.value as? Double ?? 0
        }))
        let publicRef = db.reference(withPath: "live/\(matchId)/public")
        handles.append((publicRef, publicRef.observe(.value) { [weak self] snapshot in
            self?.receive(snapshot.value)
        } withCancel: { [weak self] _ in
            self?.phase = .failed
        }))

        // Presence: online now, offline (with the time) if the connection drops.
        let presence = db.reference(withPath: "presence/\(matchId)/\(uid)")
        presence.onDisconnectSetValue(["online": false, "lastSeen": ServerValue.timestamp()])
        presence.setValue(["online": true, "lastSeen": ServerValue.timestamp()])
    }

    func stop() {
        clock?.cancel()
        claimTask?.cancel()
        for (ref, handle) in handles { ref.removeObserver(withHandle: handle) }
        handles = []
        let presence = Realtime.database.reference(withPath: "presence/\(matchId)/\(uid)")
        presence.setValue(["online": false, "lastSeen": ServerValue.timestamp()])
        presence.cancelDisconnectOperations()
    }

    private func observeOpponent() {
        guard let opponentUid, !handles.contains(where: { $0.0.url.hasSuffix("/presence/\(matchId)/\(opponentUid)") }) else { return }
        let ref = Realtime.database.reference(withPath: "presence/\(matchId)/\(opponentUid)")
        handles.append((ref, ref.observe(.value) { [weak self] snapshot in
            guard let self else { return }
            let value = snapshot.value as? [String: Any]
            if value?["online"] as? Bool == false, let lastSeen = value?["lastSeen"] as? Double {
                opponentGoneSince = localDate(lastSeen)
                scheduleClaim()
            } else {
                opponentGoneSince = nil
                claimTask?.cancel()
            }
        }))
    }

    /// Claims the match 45 seconds after the opponent's connection dropped (PRD).
    private func scheduleClaim() {
        guard let since = opponentGoneSince else { return }
        claimTask?.cancel()
        claimTask = Task { [weak self, matchId] in
            try? await Task.sleep(for: .seconds(max(0, since.addingTimeInterval(46).timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            _ = try? await Functions.functions(region: "europe-west2").httpsCallable("liveClaim").call(["matchId": matchId])
            self?.claimTask = nil
        }
    }

    // MARK: The referee's view

    private func receive(_ value: Any?) {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value),
              let view = try? JSONDecoder().decode(LivePublic.self, from: data) else { return }
        let first = self.view == nil
        self.view = view
        if first { observeOpponent() }

        if let result = view.results?[uid] {
            record = result
            phase = .finished
            clock?.cancel()
            claimTask?.cancel()
            return
        }
        if view.status == "complete" {
            if let reveal = view.lastReveal { showReveal(reveal) }
            phase = .settling
            return
        }
        if let reveal = view.lastReveal { showReveal(reveal) }
        if let round = view.round, round.number != roundNumber {
            scheduleRound(round)
        }
    }

    private func showReveal(_ reveal: LivePublic.Reveal) {
        guard reveal.number == roundNumber, reveal.number != revealedRound, var shown = question else { return }
        revealedRound = reveal.number
        clock?.cancel()
        shown.correctIndex = reveal.correctIndex
        shown.why = reveal.why
        question = shown
        let answers = reveal.answers.map { DuelAnswer(answerIndex: $0.answerIndex, timeMs: $0.timeMs) }
        let none = DuelAnswer(answerIndex: nil, timeMs: limitMs)
        lastPlayed = DuelPlayed(questionIndex: reveal.questionIndex, you: answers[safe: me] ?? none, them: answers[safe: 1 - me] ?? none,
                                winner: reveal.winner.map { $0 == me ? 0 : 1 })
        if yourAnswer == nil { yourAnswer = none }
        revealing = true
        phase = .round
    }

    /// Shows the next question at the server's start time; the reveal stays up until then.
    private func scheduleRound(_ round: LivePublic.Round) {
        let startsAt = localDate(round.startsAt)
        if roundNumber == 0 { phase = .countdown }
        clock?.cancel()
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, startsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.begin(round, at: startsAt)
        }
    }

    private func begin(_ round: LivePublic.Round, at startsAt: Date) {
        roundNumber = round.number
        question = round.question
        yourAnswer = nil
        lastPlayed = nil
        revealing = false
        roundStart = startsAt
        phase = .round
        let limit = Double(limitMs) / 1000
        clock = Task { [weak self, matchId] in
            for second in stride(from: limit - 3, to: limit, by: 1) {
                try? await Task.sleep(for: .seconds(max(0, startsAt.addingTimeInterval(second).timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                self?.pulse += 1
            }
            // Time's up: lock the screen and ask the referee to close the round (with a
            // little grace for the network). Both players do this; the first one counts.
            try? await Task.sleep(for: .seconds(max(0, startsAt.addingTimeInterval(limit).timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            if yourAnswer == nil { yourAnswer = DuelAnswer(answerIndex: nil, timeMs: limitMs) }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            _ = try? await Functions.functions(region: "europe-west2").httpsCallable("liveTimeout").call(["matchId": matchId, "round": round.number])
        }
    }

    func answer(_ index: Int) {
        guard roundPhase == .playing, yourAnswer == nil else { return }
        let timeMs = Int((Date.now.timeIntervalSince(roundStart) * 1000).rounded())
        yourAnswer = DuelAnswer(answerIndex: index, timeMs: timeMs)
        let payload: [String: Any] = ["matchId": matchId, "round": roundNumber, "answerIndex": index, "timeMs": timeMs]
        Task {
            let function = Functions.functions(region: "europe-west2").httpsCallable("liveAnswer")
            if (try? await function.call(payload)) == nil {
                _ = try? await function.call(payload) // One retry for a flaky connection.
            }
        }
    }

    /// Leaving forfeits the match.
    func leave() async {
        _ = try? await Functions.functions(region: "europe-west2").httpsCallable("liveLeave").call(["matchId": matchId])
    }

    private func localDate(_ serverMs: Double) -> Date {
        Date(timeIntervalSince1970: (serverMs - serverOffsetMs) / 1000)
    }
}

/// /live/{matchId}/public (functions/src/live.ts `publicView`).
nonisolated struct LivePublic: Decodable {
    var moduleId: String
    var limitMs: Int
    var order: [String]
    var players: [String: Player]
    var status: String
    var score: [Int]
    var round: Round?
    var locked: [Bool]
    var lastReveal: Reveal?
    var winner: Int?
    var forfeitedBy: Int?
    var results: [String: DuelRecord]?

    nonisolated struct Player: Decodable {
        var name: String
        var initial: String
        var rating: Int
        var avatarVersion: Int?
    }

    nonisolated struct Round: Decodable {
        var number: Int
        var startsAt: Double
        var question: DuelQuestion
    }

    nonisolated struct Reveal: Decodable {
        var number: Int
        var questionIndex: Int
        var winner: Int?
        var correctIndex: Int
        var why: String
        var answers: [SparringResult.RoundResult.Answer]
    }

    private enum CodingKeys: String, CodingKey {
        case moduleId, limitMs, order, players, status, score, round, locked, lastReveal, winner, forfeitedBy, results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moduleId = try c.decode(String.self, forKey: .moduleId)
        limitMs = try c.decode(Int.self, forKey: .limitMs)
        order = try c.decode([String].self, forKey: .order)
        players = try c.decode([String: Player].self, forKey: .players)
        status = try c.decode(String.self, forKey: .status)
        score = try c.decodeIfPresent([Int].self, forKey: .score) ?? [0, 0]
        round = try c.decodeIfPresent(Round.self, forKey: .round)
        // The database drops `false`-only arrays' trailing values and empty arrays.
        locked = try c.decodeIfPresent([Bool].self, forKey: .locked) ?? [false, false]
        lastReveal = try c.decodeIfPresent(Reveal.self, forKey: .lastReveal)
        winner = try c.decodeIfPresent(Int.self, forKey: .winner)
        forfeitedBy = try c.decodeIfPresent(Int.self, forKey: .forfeitedBy)
        results = try c.decodeIfPresent([String: DuelRecord].self, forKey: .results)
    }
}

/// The Realtime Database for live duels. Named explicitly: it lives in europe-west1,
/// and GoogleService-Info.plist may predate it.
enum Realtime {
    static let database = Database.database(url: "https://ratio-91a04-default-rtdb.europe-west1.firebasedatabase.app")
}
