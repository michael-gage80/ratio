import Foundation

/// `users/{uid}/briefs/{date}`: one day's brief, built by the brief Functions
/// (functions/src/brief.ts). Fixed for the day; progress comes from what the student
/// has done, not from the brief document.
nonisolated struct DailyBrief: Decodable, Equatable {
    /// The UK date, yyyy-mm-dd.
    var date: String
    var lessonId: String
    var moduleId: String
    var topicId: String
    var title: String
    var minutes: Int
    var reason: String
    var tutorNote: String?
    var steps: [Step]

    nonisolated struct Step: Decodable, Equatable {
        var kind: Kind
        var lessonId: String?
        var itemIds: [String]
        var minutes: Int
    }

    nonisolated enum Kind: String, Decodable {
        case read, drill, build, review

        var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }
}

/// Dates in UK time, which the brief, the streak and the boards all run on (PRD).
enum UKDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
        return calendar
    }()

    /// "2026-09-23"
    static func key(for date: Date = .now) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
