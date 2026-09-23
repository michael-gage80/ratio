import FirebaseFunctions
import Foundation

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

    static func startSparring(module: Module, level: Int, seconds: Int, tutorial: Bool = false) async throws -> SparringMatch {
        try await functions.httpsCallable("startSparring", requestAs: StartRequest.self, responseAs: SparringMatch.self)
            .call(StartRequest(moduleId: module.rawValue, level: level, seconds: seconds, tutorial: tutorial))
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
