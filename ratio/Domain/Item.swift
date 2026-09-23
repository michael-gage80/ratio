import Foundation

/// A question from the content JSON — the diagnostic bank, lesson in-line checks and
/// test pools. Types match the PRD's "In-line games and test types".
struct Item: Decodable, Identifiable {
    struct IRACAnswer: Decodable {
        let issue: String
        let rule: String
        let application: String
        let conclusion: String
    }

    enum Kind {
        /// quickCheck, mcqWithTrap, applyTheRule, statuteParser — and distinguishTheCase,
        /// whose two scenarios are the options.
        case choice(options: [String], correctIndex: Int)
        case tapTheFact(text: String, spans: [String], correctSpan: String)
        /// 0 = the left label is correct, 1 = the right.
        case slider(labels: [String], correctSide: Int)
        case sequence(items: [String], correctOrder: [Int])
        case recall(modelAnswer: String, acceptableAnswers: [String])
        /// The passage split into sentences; the student taps the one stating the ratio.
        case highlight(sentences: [String], ratioSentence: String)
        /// Shown as a worked example (scaffold level 1) until the IRAC builder's fading
        /// levels arrive.
        case irac(facts: [String], modelAnswer: IRACAnswer)
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
        case .irac(let facts, _):
            // Levels 2–4: the facts placed must be exactly the real ones (decoys arrive
            // as -1), any rule chosen must be the right one (0), and the written part
            // must have been marked as covering the model answer.
            if let placed = response.order, Set(placed) != Set(facts.indices) { return false }
            if let rule = response.choiceIndex, rule != 0 { return false }
            return response.selfMarkedCorrect == true
        case .highlight(_, let ratioSentence):
            return response.span.map { Self.sentence($0, states: ratioSentence) } ?? false
        }
    }

    /// Splits a passage where a full stop, question or exclamation mark is followed by
    /// whitespace — the same split as content-tools/validate.mjs.
    static func sentences(in passage: String) -> [String] {
        var result: [String] = []
        var rest = Substring(passage)
        while let match = rest.firstMatch(of: /.+?[.!?](?=\s|$)/.dotMatchesNewlines()) {
            result.append(String(match.output))
            rest = rest[match.range.upperBound...]
        }
        result.append(String(rest))
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Same rule as content-tools/validate.mjs: a sentence "states" the ratio if either
    /// contains the other, ignoring case, spacing and the final full stop — the ratio
    /// can be a clause of a longer sentence.
    static func sentence(_ sentence: String, states ratio: String) -> Bool {
        func normalise(_ s: String) -> String {
            s.lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        }
        let (a, b) = (normalise(sentence), normalise(ratio))
        return a.contains(b) || b.contains(a)
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case itemId, type, topicId, skillTag, difficultyStart, prompt
        case options, correctIndex, scenarioA, scenarioB, correctScenario
        case scenarioText, tappableSpans, correctSpan
        case sliderLabels, correctPosition
        case items, correctOrder
        case modelAnswer, acceptableAnswers
        case passage, ratioSentence
        case factsToOrder
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
            kind = .recall(modelAnswer: try c.decode(String.self, forKey: .modelAnswer),
                           acceptableAnswers: try c.decodeIfPresent([String].self, forKey: .acceptableAnswers) ?? [])
        case "highlightTheRatio":
            let passage = try c.decode(String.self, forKey: .passage)
            kind = .highlight(sentences: Self.sentences(in: passage), ratioSentence: try c.decode(String.self, forKey: .ratioSentence))
        case "irac":
            kind = .irac(facts: try c.decode([String].self, forKey: .factsToOrder),
                         modelAnswer: try c.decode(IRACAnswer.self, forKey: .modelAnswer))
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
