import Foundation

/// The planned lessons for each module (Ratio-Lesson-Spine.md, bundled as spine.json),
/// shown locked on the Pathway for modules whose lessons are still in preparation.
enum Spine {
    struct PlannedLesson: Decodable, Identifiable {
        let number: Int
        let title: String
        /// A live currency point: first in line for "Law moved".
        let watch: Bool
        var id: Int { number }
    }

    private struct File: Decodable {
        let modules: [String: [PlannedLesson]]
    }

    static func lessons(in module: Module) -> [PlannedLesson] {
        all[module.rawValue] ?? []
    }

    private static let all: [String: [PlannedLesson]] = Bundle.main
        .url(forResource: "spine", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode(File.self, from: $0).modules }
        ?? [:]
}

/// A module's topics, grouped the way the content IDs are ("crime.homicide.murder" is
/// the murder topic in the homicide group).
struct TopicGroup: Identifiable {
    let id: String
    let lessons: [Lesson]

    var title: String { Self.title(forGroup: id) }

    /// Groups in teaching order — the order of their first lesson.
    static func groups(of lessons: [Lesson]) -> [TopicGroup] {
        var order: [String] = []
        var byGroup: [String: [Lesson]] = [:]
        for lesson in lessons {
            let group = groupId(of: lesson.topicId)
            if byGroup[group] == nil { order.append(group) }
            byGroup[group, default: []].append(lesson)
        }
        return order.map { TopicGroup(id: $0, lessons: byGroup[$0] ?? []) }
    }

    static func groupId(of topicId: String) -> String {
        let parts = topicId.split(separator: ".")
        return parts.count > 1 ? String(parts[1]) : topicId
    }

    private static let titles = [
        "non-fatal": "Non-fatal offences",
        "property": "Property offences",
        "human-rights-act": "Human Rights Act",
        "rylands-v-fletcher": "Rylands v Fletcher",
        "occupiers-liability": "Occupiers' liability",
        "trespass-to-person": "Trespass to the person",
    ]

    /// "general-principles" → "General principles".
    static func title(forGroup group: String) -> String {
        titles[group] ?? humanised(group)
    }

    /// A topic's name from its ID, for topics that have scores but no lesson here yet.
    static func title(forTopic topicId: String) -> String {
        humanised(String(topicId.split(separator: ".").last ?? Substring(topicId)))
    }

    private static func humanised(_ slug: String) -> String {
        let words = slug.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
