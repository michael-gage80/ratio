import Foundation

/// One lesson (PRD: "Lessons: flow, components and in-line games"), decoded from the
/// content JSON. content-tools/lesson.schema.json is the contract; the lint keeps the
/// content honest before it reaches the app.
struct Lesson: Decodable, Identifiable {
    struct ItemCounts: Decodable {
        let lecture: Int
        let testPool: Int
        let testServedPerAttempt: Int
    }

    struct Authority: Decodable, Hashable {
        let citation: String
        let role: String
    }

    struct WhyThisMatters: Decodable {
        let defaultText: String
        let profileHooks: [String: String]?

        private enum CodingKeys: String, CodingKey {
            case defaultText = "default"
            case profileHooks
        }
    }

    struct Overview: Decodable {
        let hook: String
        let lawStatedNotice: String?
    }

    struct Part: Decodable, Identifiable {
        let partNumber: Int
        let heading: String
        let body: [String]
        let components: [LessonComponent]
        let interaction: Item

        var id: Int { partNumber }
    }

    private struct Lecture: Decodable { let parts: [Part] }

    struct Debrief: Decodable {
        let trapSummary: String
    }

    let lessonId: String
    let moduleId: Module
    let lessonNumber: Int
    let topicId: String
    let title: String
    let subtitle: String
    let estimatedMinutes: Int
    let itemCounts: ItemCounts
    let objectives: [String]
    let leadingAuthorities: [Authority]
    let whyThisMattersTemplate: WhyThisMatters
    /// yyyy-MM-dd.
    let lawStatedAt: String
    let reviewedBy: String?
    let contentVersion: String
    let overview: Overview
    private let lecture: Lecture
    let testPool: [Item]
    let debriefConfig: Debrief

    var id: String { lessonId }
    var parts: [Part] { lecture.parts }
    var isReviewed: Bool { reviewedBy != nil }

    /// "22 September 2026".
    var lawStatedDate: String {
        guard let date = try? Date(lawStatedAt, strategy: .iso8601.year().month().day()) else { return lawStatedAt }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    /// The note for this student's growth edge if the lesson has one, otherwise the
    /// default (PRD: "'Why this matters to you', taken from the profile").
    func whyThisMatters(for headline: Headline?) -> String {
        if let headline, let edge = Archetype.growthEdge(headline),
           let hook = whyThisMattersTemplate.profileHooks?["weak" + edge.rawValue.capitalized] {
            return hook
        }
        // Drafts carry an authoring note after the student-facing text ("Where the
        // profile shows…, this note appears: …"); the content lint flags it for removal.
        let text = whyThisMattersTemplate.defaultText
        guard let note = text.range(of: " Where the profile") else { return text }
        return String(text[..<note.lowerBound])
    }
}

/// The content components in a lecture part (PRD: "Content components").
enum LessonComponent: Decodable {
    struct CaseCard: Decodable, Identifiable {
        struct Expanded: Decodable {
            let facts: String
            let judgmentExtract: String
            let significance: String
        }

        let caseName: String
        let citation: String
        let court: String
        let year: Int
        let factsShort: String
        let ratioShort: String
        let expanded: Expanded?

        var id: String { caseName + citation }
    }

    struct DoctrineMap: Decodable {
        struct Node: Decodable { let id: String; let label: String }
        struct Edge: Decodable { let from: String; let to: String; let label: String }
        let title: String
        let nodes: [Node]
        let edges: [Edge]
        let textAlternative: String
    }

    struct TimelineEvent: Decodable, Hashable {
        let date: String?
        let label: String
        let description: String
    }

    case caseCard(CaseCard)
    case statute(citation: String, text: String, elements: [String])
    case keyConcept(term: String, definition: String)
    case ratioPanel(label: String, points: [String])
    case trap(commonWrongAnswer: String, whyItsWrong: String)
    case doctrineMap(DoctrineMap)
    case timeline(title: String, events: [TimelineEvent])

    private enum CodingKeys: String, CodingKey {
        case type, citation, text, elements, term, definition, label, points, commonWrongAnswer, whyItsWrong, title, events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "caseCard":
            self = .caseCard(try CaseCard(from: decoder))
        case "statuteBlock":
            self = .statute(citation: try c.decode(String.self, forKey: .citation),
                            text: try c.decode(String.self, forKey: .text),
                            elements: try c.decode([String].self, forKey: .elements))
        case "keyConcept":
            self = .keyConcept(term: try c.decode(String.self, forKey: .term), definition: try c.decode(String.self, forKey: .definition))
        case "ratioPanel":
            self = .ratioPanel(label: try c.decode(String.self, forKey: .label), points: try c.decode([String].self, forKey: .points))
        case "theTrap":
            self = .trap(commonWrongAnswer: try c.decode(String.self, forKey: .commonWrongAnswer),
                         whyItsWrong: try c.decode(String.self, forKey: .whyItsWrong))
        case "doctrineMap":
            self = .doctrineMap(try DoctrineMap(from: decoder))
        case "timeline":
            self = .timeline(title: try c.decode(String.self, forKey: .title), events: try c.decode([TimelineEvent].self, forKey: .events))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown component \(other)")
        }
    }
}
