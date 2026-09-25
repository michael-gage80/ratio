import FirebaseFunctions
import Foundation

/// What a duel is played on: one module, or "mixed" — questions from the student's own
/// modules (between two students, the ones they share), with its own rating and pool.
nonisolated enum DuelScope: Hashable, Identifiable {
    case mixed
    case module(Module)

    init?(id: String) {
        if id == "mixed" { self = .mixed } else if let module = Module(rawValue: id) { self = .module(module) } else { return nil }
    }

    var id: String {
        switch self {
        case .mixed: "mixed"
        case .module(let module): module.rawValue
        }
    }

    @MainActor var title: String {
        switch self {
        case .mixed: "Mixed"
        case .module(let module): module.title
        }
    }

    /// "Mixed", "Crime", or the raw ID if it's unknown.
    @MainActor static func title(of id: String) -> String { DuelScope(id: id)?.title ?? id }
}

/// Seconds a question: 15 for everyone, or 30 with extra time (Settings → Accessibility),
/// which is matched in its own pool.
enum DuelTime {
    static let standard = 15
    static let extended = 30
    static func seconds(extended: Int) -> Int { extended == Self.extended ? Self.extended : Self.standard }
}

/// A duel question as served by `startSparring` (functions/src/duel.ts).
nonisolated struct DuelQuestion: Codable, Equatable, Identifiable {
    var id: String
    var kind: Kind
    /// A `Skill` raw value.
    var skill: String
    var prompt: String
    var options: [String]
    var correctIndex: Int
    /// Spot the issue: the scenario phrase by phrase; tappable ones carry an option index.
    var segments: [Segment]?
    var why: String
    var lessonId: String
    var topicId: String
    var final: Bool?

    nonisolated struct Segment: Codable, Equatable {
        var text: String
        var option: Int?
    }

    nonisolated enum Kind: String, Codable {
        case fastestFinger, nameTheCase, spotTheIssue

        var title: String {
            switch self {
            case .fastestFinger: "Fastest finger"
            case .nameTheCase: "Name the case"
            case .spotTheIssue: "Spot the issue"
            }
        }
    }

    var isFinal: Bool { final == true }
}

nonisolated struct DuelAnswer: Codable, Equatable {
    /// Nil when the player didn't answer in time.
    var answerIndex: Int?
    var timeMs: Int
}

/// What `startSparring` returns.
nonisolated struct SparringMatch: Decodable {
    /// Nil for the tutorial, which isn't stored or rated.
    var matchId: String?
    var questions: [DuelQuestion]
    /// The partner's answer to each question, fixed by the server.
    var plan: [DuelAnswer]
    var partner: Partner
    var limitMs: Int
    var rating: RatingValue

    nonisolated struct Partner: Decodable {
        var name: String
        var level: Int
        var rating: Double
    }

    nonisolated struct RatingValue: Decodable {
        var rating: Double
        var rd: Double
    }
}

/// What `submitSparring` returns: the server's decision on every round.
nonisolated struct SparringResult: Codable, Equatable {
    var rounds: [RoundResult]
    var score: [Int]
    /// 0 for the student, 1 for the partner, nil for a draw.
    var winner: Int?
    var ratingBefore: Int
    var ratingAfter: Int
    var skillMoved: SkillMoved?

    nonisolated struct RoundResult: Codable, Equatable {
        var questionIndex: Int
        var answers: [Answer]
        var winner: Int?

        nonisolated struct Answer: Codable, Equatable {
            var answerIndex: Int?
            var timeMs: Int
            var correct: Bool
        }
    }

    nonisolated struct SkillMoved: Codable, Equatable {
        var topicId: String
        var skill: String
        var before: Estimate
        var after: Estimate
    }
}

/// A finished match from the student's side — sparring, live or async (`PlayerRecord`
/// in functions/src/multiplayer.ts). Answers are [yours, theirs]; winner 0 is you.
nonisolated struct DuelRecord: Codable, Equatable {
    var questions: [DuelQuestion]
    var limitMs: Int
    var moduleId: String
    var opponent: Opponent
    var rounds: [SparringResult.RoundResult]
    var score: [Int]
    var winner: Int?
    var forfeited: Bool?
    var ratingBefore: Int
    var ratingAfter: Int
    var skillMoved: SparringResult.SkillMoved?

    nonisolated struct Opponent: Codable, Equatable {
        var uid: String?
        var name: String
        var initial: String
        var avatarVersion: Int?
        /// Set for a sparring partner.
        var level: Int?
    }

    var isSparring: Bool { opponent.level != nil }

    private enum CodingKeys: String, CodingKey {
        case questions, limitMs, moduleId, opponent, rounds, score, winner, forfeited, ratingBefore, ratingAfter, skillMoved
    }

    /// The Realtime Database drops empty arrays (a match forfeited before its first round).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questions = try c.decode([DuelQuestion].self, forKey: .questions)
        limitMs = try c.decode(Int.self, forKey: .limitMs)
        moduleId = try c.decode(String.self, forKey: .moduleId)
        opponent = try c.decode(Opponent.self, forKey: .opponent)
        rounds = try c.decodeIfPresent([SparringResult.RoundResult].self, forKey: .rounds) ?? []
        score = try c.decodeIfPresent([Int].self, forKey: .score) ?? [0, 0]
        winner = try c.decodeIfPresent(Int.self, forKey: .winner)
        forfeited = try c.decodeIfPresent(Bool.self, forKey: .forfeited)
        ratingBefore = try c.decode(Int.self, forKey: .ratingBefore)
        ratingAfter = try c.decode(Int.self, forKey: .ratingAfter)
        skillMoved = try c.decodeIfPresent(SparringResult.SkillMoved.self, forKey: .skillMoved)
    }

    /// "Sparring partner, level 2" or "Zara K.".
    var opponentTitle: String { opponent.level.map { "\(opponent.name), level \($0)" } ?? opponent.name }

    init(match: SparringMatch, result: SparringResult, scope: DuelScope) {
        questions = match.questions
        limitMs = match.limitMs
        moduleId = scope.id
        opponent = Opponent(uid: nil, name: match.partner.name, initial: "S", avatarVersion: nil, level: match.partner.level)
        rounds = result.rounds
        score = result.score
        winner = result.winner
        forfeited = false
        ratingBefore = result.ratingBefore
        ratingAfter = result.ratingAfter
        skillMoved = result.skillMoved
    }
}

/// The duel rules, as in functions/src/duel.ts, so rounds can be revealed instantly.
/// The server replays the match with the same rules and its result is the one kept.
enum DuelRules {
    static let pointsToWin = 3
    static let minAnswerMs = 250

    static func counts(_ answer: DuelAnswer, limitMs: Int) -> Bool {
        answer.answerIndex != nil && answer.timeMs >= minAnswerMs && answer.timeMs <= limitMs
    }

    /// The first answer decides: right takes the point, wrong gives it away. 0 is the student.
    static func winner(of question: DuelQuestion, you: DuelAnswer, them: DuelAnswer, limitMs: Int) -> Int? {
        let answers = [you, them]
        let valid = [0, 1].filter { counts(answers[$0], limitMs: limitMs) }.sorted { answers[$0].timeMs < answers[$1].timeMs }
        guard let first = valid.first else { return nil }
        let correct = { (player: Int) in answers[player].answerIndex == question.correctIndex }
        if valid.count == 2, answers[valid[0]].timeMs == answers[valid[1]].timeMs {
            return correct(0) == correct(1) ? nil : (correct(0) ? 0 : 1)
        }
        return correct(first) ? first : 1 - first
    }

    /// The next question to play, or nil when the match is over.
    static func nextQuestion(in questions: [DuelQuestion], score: [Int], regularPlayed: Int, finalPlayed: Bool) -> Int? {
        guard score.max() ?? 0 < pointsToWin, !finalPlayed else { return nil }
        let finalIndex = questions.firstIndex { $0.isFinal }
        if score == [pointsToWin - 1, pointsToWin - 1], let finalIndex { return finalIndex }
        let regular = questions.indices.filter { $0 != finalIndex }
        return regular[safe: regularPlayed]
    }
}

enum DuelService {
    private nonisolated struct StartRequest: Encodable {
        let moduleId: String
        let level: Int
        let seconds: Int
        let tutorial: Bool
    }

    private nonisolated struct SubmitRequest: Encodable {
        let matchId: String
        let answers: [DuelAnswer]
    }

    private static var functions: Functions { Functions.functions(region: "europe-west2") }

    static func startSparring(scope: DuelScope, level: Int, seconds: Int, tutorial: Bool = false) async throws -> SparringMatch {
        try await functions.httpsCallable("startSparring", requestAs: StartRequest.self, responseAs: SparringMatch.self)
            .call(StartRequest(moduleId: scope.id, level: level, seconds: seconds, tutorial: tutorial))
    }

    static func submitSparring(matchId: String, answers: [DuelAnswer]) async throws -> SparringResult {
        try await functions.httpsCallable("submitSparring", requestAs: SubmitRequest.self, responseAs: SparringResult.self)
            .call(SubmitRequest(matchId: matchId, answers: answers))
    }
}

/// Five sparring bands (PRD: "Bots in 5 difficulty bands"), as described to the student.
enum SparringLevel {
    static let all = 1...5

    static func title(_ level: Int) -> String {
        ["Gentle", "Steady", "Sharp", "Quick", "Formidable"][max(0, min(4, level - 1))]
    }

    static func detail(_ level: Int) -> String {
        [
            "Takes its time and often slips. A place to learn the format.",
            "Right a little over half the time, at a relaxed pace.",
            "Usually right, and quicker. A fair test.",
            "Right three times in four, and fast.",
            "Rarely wrong, rarely slow.",
        ][max(0, min(4, level - 1))]
    }
}

// MARK: - The round screen's view of a match

enum DuelRoundPhase {
    /// Before the first round, or between a reveal and the next question.
    case waiting
    /// The tutorial's coach marks, with the clock stopped.
    case coaching
    case playing
    case revealing
}

/// Who's across the board: a labelled sparring partner or another student.
struct DuelOpponent: Equatable {
    var name: String
    /// "Level 2" for a partner; a rating or "Plays later" for a student.
    var detail: String
    var isBot: Bool
    var uid: String?
    var initial: String
    var avatarVersion: Int?

    static func sparring(level: Int) -> DuelOpponent {
        DuelOpponent(name: "Sparring partner", detail: "Level \(level)", isBot: true, uid: nil, initial: "S", avatarVersion: nil)
    }
}

struct DuelPlayed: Equatable {
    let questionIndex: Int
    let you: DuelAnswer
    let them: DuelAnswer
    /// 0 for the student, 1 for the opponent, nil for no point.
    let winner: Int?
}

/// A round already played, for the iPad "Match so far" panel.
struct DuelRoundSummary: Identifiable, Equatable {
    /// The round's number (1-based).
    let id: Int
    let kind: DuelQuestion.Kind
    let isFinal: Bool
    let played: DuelPlayed
}

/// What the round screen needs: sparring, live and async matches all provide it.
protocol DuelRoundModel: AnyObject, Observable {
    var roundPhase: DuelRoundPhase { get }
    /// The question on screen; its `correctIndex` is only meaningful once revealed.
    var question: DuelQuestion? { get }
    /// 1-based number of the round on screen.
    var roundNumber: Int { get }
    var yourAnswer: DuelAnswer? { get }
    var lastPlayed: DuelPlayed? { get }
    var roundStart: Date { get }
    var limitMs: Int { get }
    /// [you, them].
    var score: [Int] { get }
    /// An async half has no running score.
    var showsScore: Bool { get }
    var pulse: Int { get }
    var labelPrefix: String { get }
    var opponent: DuelOpponent { get }
    /// Every round revealed so far, oldest first (for the iPad arena's side panel).
    var history: [DuelRoundSummary] { get }
    func opponentLocked(at date: Date) -> Bool
    func answer(_ index: Int)
    /// The line under a revealed round, and whether it went the student's way.
    func revealMessage(_ played: DuelPlayed, question: DuelQuestion) -> (text: String, good: Bool?)
}

extension DuelRoundModel {
    var showsScore: Bool { true }
    var labelPrefix: String { "" }
    var history: [DuelRoundSummary] { [] }

    func revealMessage(_ played: DuelPlayed, question: DuelQuestion) -> (text: String, good: Bool?) {
        let seconds = { (ms: Int) in String(format: "%.1f", Double(ms) / 1000) }
        let youRight = played.you.answerIndex == question.correctIndex
        switch played.winner {
        case 0:
            return (youRight ? "Your point — \(seconds(played.you.timeMs))\u{00A0}s." : "Your point — \(opponent.isBot ? "your partner" : opponent.name) answered wrong.", true)
        case 1:
            let gaveItAway = played.you.answerIndex != nil && !youRight && played.you.timeMs <= played.them.timeMs
            return (gaveItAway ? "Their point — a wrong answer gives it away." : "Their point — right in \(seconds(played.them.timeMs))\u{00A0}s.", false)
        default:
            return ("No point — nobody got it in time.", nil)
        }
    }
}

// MARK: - Playing other students

extension DuelService {
    private static func call<Response: Decodable>(_ name: String, _ payload: [String: Any] = [:], as: Response.Type = Response.self) async throws -> Response {
        let result = try await Functions.functions(region: "europe-west2").httpsCallable(name).call(payload)
        let data = try JSONSerialization.data(withJSONObject: result.data)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private nonisolated struct Empty: Decodable {}

    // Friend lobbies

    private nonisolated struct Code: Decodable { let code: String }
    private nonisolated struct MatchID: Decodable { let matchId: String? }

    static func createLobby(scope: DuelScope, seconds: Int) async throws -> String {
        try await call("createLobby", ["moduleId": scope.id, "seconds": seconds], as: Code.self).code
    }

    static func joinLobby(code: String) async throws -> String {
        try await call("joinLobby", ["code": code], as: Code.self).code
    }

    static func leaveLobby(code: String) async {
        _ = try? await call("leaveLobby", ["code": code], as: Empty.self)
    }

    static func startLobby(code: String) async throws -> String? {
        try await call("startLobby", ["code": code], as: MatchID.self).matchId
    }

    nonisolated struct SendResult: Decodable {
        let sent: Bool
        /// "contact" or "abuse" when the filter stopped it.
        let reason: String?
    }

    static func sendMessage(code: String, text: String) async throws -> SendResult {
        try await call("sendLobbyMessage", ["code": code, "text": text])
    }

    static func report(code: String, messageId: String) async throws {
        _ = try await call("reportMessage", ["code": code, "messageId": messageId], as: Empty.self)
    }

    static func block(uid: String) async throws {
        _ = try await call("blockUser", ["uid": uid], as: Empty.self)
    }

    // Ranked matchmaking

    nonisolated struct Search: Decodable {
        let matchId: String?
        /// The rating gap being searched, while waiting.
        let window: Int?
    }

    static func findMatch(scope: DuelScope, seconds: Int) async throws -> Search {
        try await call("findMatch", ["moduleId": scope.id, "seconds": seconds])
    }

    static func cancelMatchmaking() async {
        _ = try? await call("cancelMatchmaking", as: Empty.self)
    }

    // Async challenges

    private nonisolated struct ChallengeID: Decodable { let challengeId: String }

    @discardableResult
    static func createChallenge(opponent: String, scope: DuelScope, seconds: Int) async throws -> String {
        try await call("createChallenge", ["opponent": opponent, "moduleId": scope.id, "seconds": seconds], as: ChallengeID.self).challengeId
    }

    /// Turns down a challenge before playing it; no rating changes.
    static func declineChallenge(id: String) async throws {
        _ = try await call("declineChallenge", ["challengeId": id], as: Empty.self)
    }

    nonisolated struct ChallengeStep: Decodable {
        nonisolated struct Revealed: Decodable {
            let correct: Bool
            let correctIndex: Int
            let why: String
        }

        let revealed: Revealed?
        let question: DuelQuestion?
        let index: Int?
        let total: Int
        let limitMs: Int
        let result: DuelRecord?
    }

    /// Answers question `index` (nil to fetch the next one) and serves the next.
    static func playChallenge(id: String, index: Int?, answer: DuelAnswer?) async throws -> ChallengeStep {
        var payload: [String: Any] = ["challengeId": id]
        if let index { payload["index"] = index }
        if let answer {
            payload["timeMs"] = answer.timeMs
            if let choice = answer.answerIndex { payload["answerIndex"] = choice }
        }
        return try await call("playChallenge", payload)
    }
}
