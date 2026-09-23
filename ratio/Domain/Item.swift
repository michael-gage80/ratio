import Foundation

/// A question from the content JSON — the diagnostic bank now, lesson test pools and
/// in-line checks later. Types match the PRD's "In-line games and test types"; the two
/// lesson-only types (IRAC builder, highlight the ratio) arrive with the lesson engine.
struct Item: Decodable, Identifiable {
    enum Kind {
        /// quickCheck, mcqWithTrap, applyTheRule, statuteParser — and distinguishTheCase,
        /// whose two scenarios are the options.
        case choice(options: [String], correctIndex: Int)
        case tapTheFact(text: String, spans: [String], correctSpan: String)
        /// 0 = the left label is correct, 1 = the right.
        case slider(labels: [String], correctSide: Int)
        case sequence(items: [String], correctOrder: [Int])
        case recall(modelAnswer: String)
    }

    let id: String
    let type: String
    let topicId: String?
    let skill: Skill
    /// 0–1, on the scale the scoring model maps to logits.
    let difficulty: Double
    let prompt: String
    let kind: Kind

    /// Shown after locking in: why the answer is what it is.
    let explanation: String?
    /// Names the tempting wrong answer; shown only when the student falls for it.
    let trapExplanation: String?
    let feedbackCorrect: String?
    let feedbackIncorrect: String?

    func feedback(correct: Bool) -> String? {
        (correct ? feedbackCorrect : feedbackIncorrect) ?? explanation
    }

    /// Mirrors `isCorrect` in functions/src/scoring.ts, which is what actually counts.
    func isCorrect(_ response: ItemResponse) -> Bool {
        switch kind {
        case .choice(_, let correctIndex):
            return response.choiceIndex == correctIndex
        case .tapTheFact(_, _, let correctSpan):
            return response.span == correctSpan
        case .slider(_, let correctSide):
            guard let value = response.sliderValue, value != 0.5 else { return false }
            return correctSide == 1 ? value > 0.5 : value < 0.5
        case .sequence(_, let correctOrder):
            return response.order == correctOrder
        case .recall:
            return response.selfMarkedCorrect == true
        }
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case itemId, type, topicId, skillTag, difficultyStart, prompt
        case options, correctIndex, scenarioA, scenarioB, correctScenario
        case scenarioText, tappableSpans, correctSpan
        case sliderLabels, correctPosition
        case items, correctOrder
        case modelAnswer
        case briefExplanation, explanation, trapExplanation, feedbackCorrect, feedbackIncorrect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .itemId)
        type = try c.decode(String.self, forKey: .type)
        topicId = try c.decodeIfPresent(String.self, forKey: .topicId)
        skill = try c.decode(Skill.self, forKey: .skillTag)
        difficulty = try c.decodeIfPresent(Double.self, forKey: .difficultyStart) ?? 0.5
        prompt = try c.decode(String.self, forKey: .prompt)
        explanation = try c.decodeIfPresent(String.self, forKey: .briefExplanation)
            ?? c.decodeIfPresent(String.self, forKey: .explanation)
        trapExplanation = try c.decodeIfPresent(String.self, forKey: .trapExplanation)
        feedbackCorrect = try c.decodeIfPresent(String.self, forKey: .feedbackCorrect)
        feedbackIncorrect = try c.decodeIfPresent(String.self, forKey: .feedbackIncorrect)

        switch type {
        case "quickCheck", "mcqWithTrap", "applyTheRule", "statuteParser":
            kind = .choice(options: try c.decode([String].self, forKey: .options),
                           correctIndex: try c.decode(Int.self, forKey: .correctIndex))
        case "distinguishTheCase":
            let correct = try c.decode(String.self, forKey: .correctScenario)
            kind = .choice(options: [try c.decode(String.self, forKey: .scenarioA), try c.decode(String.self, forKey: .scenarioB)],
                           correctIndex: correct == "A" ? 0 : 1)
        case "tapTheFact":
            kind = .tapTheFact(text: try c.decode(String.self, forKey: .scenarioText),
                               spans: try c.decode([String].self, forKey: .tappableSpans),
                               correctSpan: try c.decode(String.self, forKey: .correctSpan))
        case "thresholdSlider":
            let labels = try c.decode([String].self, forKey: .sliderLabels)
            let target = try c.decode(String.self, forKey: .correctPosition).lowercased()
            // Same rule as the server: the end whose label contains the answer.
            let leftMatches = labels.first.map { $0.lowercased().contains(target) } ?? false
            kind = .slider(labels: labels, correctSide: leftMatches ? 0 : 1)
        case "sequence":
            kind = .sequence(items: try c.decode([String].self, forKey: .items),
                             correctOrder: try c.decode([Int].self, forKey: .correctOrder))
        case "recallFirst":
            kind = .recall(modelAnswer: try c.decode(String.self, forKey: .modelAnswer))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unsupported item type \(type)")
        }
    }
}

/// What the student answered, in the shape the scoring Function expects
/// (`ItemResponse` in functions/src/scoring.ts). Only the field for the item's type is set.
nonisolated struct ItemResponse: Codable, Equatable {
    let itemId: String
    var choiceIndex: Int?
    var span: String?
    var sliderValue: Double?
    var order: [Int]?
    var selfMarkedCorrect: Bool?
}
