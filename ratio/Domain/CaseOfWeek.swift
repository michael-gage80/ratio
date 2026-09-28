import Foundation

/// `users/{uid}/caseWeeks/{monday}`: the week's case, chosen by the `getCaseOfWeek`
/// Function (functions/src/caseOfWeek.ts), and the student's rating once given.
nonisolated struct CaseWeek: Decodable, Equatable {
    enum Result: String, Decodable {
        case knew, missed
    }

    var week: String
    /// The case's review-item ID ("case-r-v-woollin").
    var caseId: String
    /// The lesson the card links to.
    var lessonId: String
    var moduleId: String
    var result: Result?
}

/// Rules shared with functions/src/content.ts, so the app and the server agree on
/// which case cards are cases and what each one's review item is called.
enum CaseOfWeek {
    static let itemPrefix = "case-"

    /// Same rule as `caseItemId` in functions/src/content.ts.
    static func itemId(for caseName: String) -> String {
        let slug = caseName.lowercased()
            .replacing(/[^a-z0-9]+/, with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return itemPrefix + String(slug.prefix(80))
    }

    /// A reported case, not a worked example or summary on a case card (same rule as
    /// `isReportedCase` in functions/src/content.ts).
    static func isReportedCase(_ card: LessonComponent.CaseCard) -> Bool {
        card.citation.contains(/[\[(]\d{4}[\])]/) && !card.court.contains(/^N\/A|(?i)not a case/)
    }

    /// The UK date of this week's Monday: the case changes at 00:00 UK time on Monday.
    static func weekKey(for date: Date = .now) -> String {
        UKDate.key(for: UKDate.calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date)
    }
}

extension ContentStore {
    /// A case by its review-item ID, with the first lesson (by ID) whose lecture has it —
    /// the same lesson the server files its review under.
    func caseCard(itemId: String) -> (card: LessonComponent.CaseCard, lesson: Lesson)? {
        guard itemId.hasPrefix(CaseOfWeek.itemPrefix) else { return nil }
        var found: (card: LessonComponent.CaseCard, lesson: Lesson)?
        for module in Module.allCases {
            for lesson in lessons(in: module) where found.map({ lesson.id < $0.lesson.id }) ?? true {
                for case .caseCard(let card) in lesson.parts.flatMap(\.components)
                where CaseOfWeek.itemId(for: card.caseName) == itemId && CaseOfWeek.isReportedCase(card) {
                    found = (card, lesson)
                    break
                }
            }
        }
        return found
    }
}

extension Item {
    /// A case recall in the brief's Review: the facts, then the ratio to mark yourself against.
    init(caseRecall card: LessonComponent.CaseCard, id: String, topicId: String) {
        self.id = id
        type = "recallFirst"
        self.topicId = topicId
        skill = .knowledge
        difficulty = 0.5
        prompt = "Case of the week · \(card.caseName) \(card.citation). \(card.factsShort) What was the ratio?"
        kind = .recall(modelAnswer: card.ratioShort, acceptableAnswers: [])
        explanation = card.expanded?.significance
        trapExplanation = nil
        feedbackCorrect = nil
        feedbackIncorrect = nil
    }
}
