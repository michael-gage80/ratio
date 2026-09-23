import FirebaseFirestore
import Foundation

/// Live copies of the student's own documents, shared by the tabs so the Pathway and
/// Me update the moment a test is scored. Firestore serves these from its cache
/// offline and when the app launches.
@Observable
final class StudentStore {
    let uid: String
    private(set) var profile: UserProfile
    /// Keyed by topic ID.
    private(set) var topics: [String: TopicScores] = [:]
    private(set) var items: [ReviewItem] = []
    /// Lecture parts completed, keyed by lesson ID.
    private(set) var partsCompleted: [String: Int] = [:]
    private(set) var attempts: [TestAttempt] = []

    @ObservationIgnored private var listeners: [ListenerRegistration] = []

    init(uid: String, profile: UserProfile) {
        self.uid = uid
        self.profile = profile
    }

    var headline: Headline { profile.headline ?? .prior }

    func start() {
        guard listeners.isEmpty else { return }
        let user = Firestore.firestore().collection("users").document(uid)
        listeners = [
            user.addSnapshotListener { [weak self] snapshot, _ in
                if let profile = try? snapshot?.data(as: UserProfile.self) { self?.profile = profile }
            },
            user.collection("skills").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.topics = Dictionary(uniqueKeysWithValues: snapshot.documents.compactMap { document in
                    (try? document.data(as: TopicScores.self)).map { (document.documentID, $0) }
                })
            },
            user.collection("items").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.items = snapshot.documents.compactMap { try? $0.data(as: ReviewItem.self) }
            },
            user.collection("lessons").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.partsCompleted = Dictionary(uniqueKeysWithValues: snapshot.documents.map {
                    ($0.documentID, $0.data()["partsCompleted"] as? Int ?? 0)
                })
            },
            user.collection("testAttempts").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.attempts = snapshot.documents.compactMap { try? $0.data(as: TestAttempt.self) }
            },
        ]
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
    }
}

// MARK: - Documents

/// `users/{uid}/skills/{topicId}`: the current estimate per skill, and a snapshot
/// after every scored attempt for the trend charts.
nonisolated struct TopicScores: Decodable {
    var knowledge: Estimate?
    var understanding: Estimate?
    var application: Estimate?
    var history: [Snapshot]?
    var updatedAt: Date?

    nonisolated struct Snapshot: Decodable {
        var at: Date
        var knowledge: Estimate?
        var understanding: Estimate?
        var application: Estimate?

        subscript(skill: Skill) -> Estimate? {
            switch skill {
            case .knowledge: knowledge
            case .understanding: understanding
            case .application: application
            }
        }
    }

    subscript(skill: Skill) -> Estimate? {
        switch skill {
        case .knowledge: knowledge
        case .understanding: understanding
        case .application: application
        }
    }
}

/// `users/{uid}/items/{itemId}`: a tested item's review schedule (the fields the app needs).
nonisolated struct ReviewItem: Decodable {
    var lessonId: String
    var topicId: String
    var due: Date
    var lastCorrect: Bool
}

/// `users/{uid}/testAttempts/{attemptId}` (the fields the app needs).
nonisolated struct TestAttempt: Decodable {
    var lessonId: String
    var createdAt: Date?
    /// Items in this attempt that came back 7 or more days after they were last seen.
    var delayed: Delayed?

    nonisolated struct Delayed: Decodable {
        var total: Int
        var correct: Int
    }
}

extension Headline {
    /// Every skill at the prior: the widest band.
    static let prior = Headline(knowledge: .prior, understanding: .prior, application: .prior)
}

// MARK: - Derived

/// A lesson's state on the Pathway (PRD: "not started, in progress, secure, or needs review").
enum LessonState {
    case notStarted, inProgress, secure, needsReview
}

extension StudentStore {
    /// Tested lessons are secure until an item is missed or comes due for review.
    func state(of lesson: Lesson, now: Date = .now) -> LessonState {
        let tested = items.filter { $0.lessonId == lesson.id }
        if !tested.isEmpty {
            return tested.contains { !$0.lastCorrect || $0.due <= now } ? .needsReview : .secure
        }
        return (partsCompleted[lesson.id] ?? 0) > 0 ? .inProgress : .notStarted
    }

    /// The share of a module's lessons that are secure, or nil if it has none yet.
    func mastery(of lessons: [Lesson]) -> Int? {
        guard !lessons.isEmpty else { return nil }
        let secure = lessons.count { state(of: $0) == .secure }
        return Int((100 * Double(secure) / Double(lessons.count)).rounded())
    }

    /// Where to carry on: a lecture already started, otherwise the first lesson not yet begun.
    func nextLesson(in modules: [Module], content: ContentStore) -> Lesson? {
        let lessons = modules.flatMap { content.lessons(in: $0) }
        return lessons.first { state(of: $0) == .inProgress } ?? lessons.first { state(of: $0) == .notStarted }
    }

    /// Delayed retention (PRD north star): accuracy on items that came back 7+ days
    /// after they were last seen. Nil until there are enough of them to mean anything.
    var retention: Retention? {
        let dated = attempts
            .compactMap { attempt in attempt.createdAt.flatMap { date in attempt.delayed.map { (date, $0) } } }
            .filter { $0.1.total > 0 }
            .sorted { $0.0 < $1.0 }
        var total = 0, correct = 0
        let points = dated.map { date, delayed in
            total += delayed.total
            correct += delayed.correct
            return Retention.Point(date: date, percent: 100 * Double(correct) / Double(total))
        }
        guard total >= Retention.minimumItems, let latest = points.last else { return nil }
        let monthAgo = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        let baseline = points.last { $0.date <= monthAgo }
        return Retention(percent: Int(latest.percent.rounded()), items: total, points: points,
                         change: baseline.map { Int((latest.percent - $0.percent).rounded()) })
    }
}

struct Retention {
    static let minimumItems = 5

    struct Point: Identifiable {
        let date: Date
        let percent: Double
        var id: Date { date }
    }

    let percent: Int
    let items: Int
    /// Running retention after each attempt, for the sparkline.
    let points: [Point]
    /// Points gained or lost over the last four weeks.
    let change: Int?
}
