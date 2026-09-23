import FirebaseFirestore
import FirebaseFunctions
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
    /// Today's brief, once built.
    private(set) var brief: DailyBrief?
    /// Set when today's brief can't be built — none of the student's modules has lessons yet.
    private(set) var briefUnavailable = false
    /// UK dates the student was active on, over the last few weeks.
    private(set) var activeDays: Set<String> = []

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var briefListener: ListenerRegistration?
    @ObservationIgnored private var briefDate: String?

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
            user.collection("activity")
                .whereField("at", isGreaterThan: Timestamp(date: .now.addingTimeInterval(-Streak.lookbackWeeks * 7 * 86_400)))
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let snapshot else { return }
                    self?.activeDays = Set(snapshot.documents.map(\.documentID))
                },
        ]
        listenToTodaysBrief()
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        briefListener?.remove()
        briefListener = nil
        briefDate = nil
    }

    /// Follows today's brief document, switching over when the UK date changes.
    func listenToTodaysBrief() {
        let today = UKDate.key()
        guard briefDate != today else { return }
        briefListener?.remove()
        briefDate = today
        brief = nil
        briefUnavailable = false
        briefListener = Firestore.firestore().collection("users").document(uid).collection("briefs").document(today)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot, snapshot.exists else { return }
                self?.brief = try? snapshot.data(as: DailyBrief.self)
            }
    }

    private nonisolated struct BriefResponse: Decodable {
        let brief: DailyBrief?
    }

    /// Builds today's brief if the nightly job hasn't (day 1, or a new day since the app
    /// was opened). The listener picks the result up; this only reports "none possible".
    func ensureBrief() async {
        listenToTodaysBrief()
        guard brief == nil else { return }
        let function = Functions.functions(region: "europe-west2").httpsCallable("getBrief", requestAs: [String: String].self, responseAs: BriefResponse.self)
        guard let response = try? await function.call([:]) else { return }
        if let built = response.brief { brief = built } else { briefUnavailable = true }
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
    /// Set for lesson tests.
    var lessonId: String?
    /// Set for daily-brief steps.
    var briefDate: String?
    var stepIndex: Int?
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

// MARK: - Brief progress and streak

extension StudentStore {
    /// A Read step is done once the lecture is finished; the others once they've been scored.
    func isDone(step index: Int, of brief: DailyBrief, content: ContentStore) -> Bool {
        guard let step = brief.steps[safe: index] else { return false }
        if step.kind == .read, let lessonId = step.lessonId {
            let parts = content.lesson(id: lessonId)?.parts.count ?? 0
            return parts > 0 && (partsCompleted[lessonId] ?? 0) >= parts
        }
        return attempts.contains { $0.briefDate == brief.date && $0.stepIndex == index }
    }

    /// The first step not yet done, or nil when the brief is complete.
    func currentStep(of brief: DailyBrief, content: ContentStore) -> Int? {
        brief.steps.indices.first { !isDone(step: $0, of: brief, content: content) }
    }

    var streak: Streak { Streak(activeDays: activeDays, today: .now) }
}

/// The weekly target (PRD: "active on 4 days of 7 ... The count is in weeks, not days").
/// Never punishes a missed day: the copy only ever says what keeps the week.
struct Streak {
    static let lookbackWeeks: Double = 26
    /// Until the student can set it in Settings (Phase 15).
    static let target = 4

    /// Monday to Sunday of this week, and whether each was active.
    let week: [(date: Date, active: Bool)]
    let todayIndex: Int
    /// Weeks in a row that met the target, before this one.
    let previousWeeks: Int

    init(activeDays: Set<String>, today: Date) {
        let calendar = UKDate.calendar
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        week = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            return (date, activeDays.contains(UKDate.key(for: date)))
        }
        todayIndex = max(0, min(6, (calendar.dateComponents([.day], from: monday, to: today).day ?? 0)))

        var weeks = 0
        var start = calendar.date(byAdding: .weekOfYear, value: -1, to: monday) ?? monday
        while weeks < Int(Self.lookbackWeeks) {
            let active = (0..<7).count { offset in
                calendar.date(byAdding: .day, value: offset, to: start).map { activeDays.contains(UKDate.key(for: $0)) } ?? false
            }
            guard active >= Self.target else { break }
            weeks += 1
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
        }
        previousWeeks = weeks
    }

    var daysThisWeek: Int { week.count { $0.active } }

    var message: String {
        let remaining = Self.target - daysThisWeek
        let daysLeft = 7 - todayIndex - (week[todayIndex].active ? 1 : 0)
        if remaining <= 0 { return "Week done. Anything more is a bonus." }
        if remaining > daysLeft { return "A fresh week starts on Monday." }
        return remaining == 1 ? "One more day keeps the week." : "\(remaining) more days keep the week."
    }
}
