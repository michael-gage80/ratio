import FirebaseDatabase
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
    /// Duel ratings, keyed by module or mixed.
    private(set) var ratings: [DuelScope: DuelRating] = [:]
    /// The last 20 duels, newest first.
    private(set) var matches: [MatchSummary] = []
    /// The last 30 days of async challenges, newest first, whatever became of them.
    private(set) var challengeHistory: [ChallengeSummary] = []
    /// Async challenges still open (PRD: "They have 24 h to play their half").
    var challenges: [ChallengeSummary] {
        challengeHistory.filter { $0.status == "open" && $0.expiresAt > .now }.sorted { $0.expiresAt < $1.expiresAt }
    }
    /// Students this student has duelled, for the Friends board.
    private(set) var friends: [String] = []
    /// UK legal news from the last 7 days, newest first.
    private(set) var news: [NewsStory] = []
    /// This week's Sunday quiz, from its Sunday for seven days.
    private(set) var quiz: SundayQuiz?
    /// Duels started today, for the free plan's allowance (kept by Functions).
    private(set) var duelsToday = 0
    /// Everyone has Plus during the beta — config/app.plusForEveryone, off at launch
    /// (same default as functions/src/entitlement.ts).
    private(set) var plusForEveryone = true

    /// Students with the app open, counted every five minutes (functions/src/online.ts).
    private(set) var online: Int?
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var onlineHandle: DatabaseHandle?
    @ObservationIgnored private var briefListener: ListenerRegistration?
    @ObservationIgnored private var briefDate: String?

    init(uid: String, profile: UserProfile) {
        self.uid = uid
        self.profile = profile
    }

    var headline: Headline { profile.headline ?? .prior }

    // MARK: Plan (functions/src/entitlement.ts)

    /// Ratio Plus: an active App Store subscription or a valid university licence.
    var isPlus: Bool {
        if plusForEveryone { return true }
        if let subscription = profile.subscription, subscription.revoked != true, subscription.expiresAt > .now { return true }
        if let licence = profile.licence, licence.revoked != true, licence.expiresAt > .now { return true }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.plus") { return true }
        #endif
        return false
    }

    /// The module a free student studies in full: their choice, else their first.
    var freeModule: Module? {
        let modules = profile.modules ?? []
        if let chosen = profile.freeModule, modules.contains(chosen) { return chosen }
        return modules.first
    }

    /// Whether the student can study this module in full.
    func canStudy(_ module: Module) -> Bool { isPlus || module == freeModule }

    var settings: StudySettings { profile.settings ?? StudySettings() }

    var programme: Programme { Programme(profile: profile.programme) }

    /// The student's modules in their programme (a student who switched keeps the old
    /// ones on file, but sees these).
    var modules: [Module] { (profile.modules ?? []).filter { $0.programme == programme } }

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
            Firestore.firestore().collection("ratings").whereField("uid", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let snapshot else { return }
                    self?.ratings = Dictionary(snapshot.documents.compactMap { document in
                        (try? document.data(as: DuelRating.self)).flatMap { rating in DuelScope(id: rating.moduleId).map { ($0, rating) } }
                    }, uniquingKeysWith: { first, _ in first })
                },
            Firestore.firestore().collection("matches").whereField("players", arrayContains: uid)
                .order(by: "createdAt", descending: true).limit(to: 20)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let snapshot else { return }
                    self?.matches = snapshot.documents.compactMap { document in
                        (try? document.data(as: MatchSummary.self)).map { var match = $0; match.id = document.documentID; return match }
                    }
                },
            Firestore.firestore().collection("news")
                .whereField("publishedAt", isGreaterThan: Timestamp(date: .now.addingTimeInterval(-7 * 86_400)))
                .order(by: "publishedAt", descending: true)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let snapshot else { return }
                    self?.news = snapshot.documents.compactMap { document in
                        (try? document.data(as: NewsStory.self)).map { var story = $0; story.id = document.documentID; return story }
                    }
                },
            Firestore.firestore().collection("quizzes")
                .whereField("sunday", isLessThanOrEqualTo: UKDate.key())
                .order(by: "sunday", descending: true).limit(to: 1)
                .addSnapshotListener { [weak self] snapshot, _ in
                    let latest = snapshot?.documents.first.flatMap { try? $0.data(as: SundayQuiz.self) }
                    let weekAgo = UKDate.key(for: .now.addingTimeInterval(-6 * 86_400))
                    self?.quiz = latest.flatMap { $0.sunday >= weekAgo ? $0 : nil }
                },
            Firestore.firestore().collection("config").document("app").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.plusForEveryone = snapshot.data()?["plusForEveryone"] as? Bool ?? true
            },
            user.collection("usage").document(UKDate.key()).addSnapshotListener { [weak self] snapshot, _ in
                self?.duelsToday = snapshot?.data()?["duels"] as? Int ?? 0
            },
            user.collection("friends").addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                self?.friends = snapshot.documents.map(\.documentID)
            },
            Firestore.firestore().collection("challenges").whereField("players", arrayContains: uid)
                .whereField("createdAt", isGreaterThan: Date.now.addingTimeInterval(-30 * 86_400))
                .order(by: "createdAt", descending: true).limit(to: 50)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let snapshot else { return }
                    self?.challengeHistory = snapshot.documents
                        .compactMap { document in (try? document.data(as: ChallengeSummary.self)).map { var c = $0; c.id = document.documentID; return c } }
                },
        ]
        onlineHandle = Realtime.database.reference(withPath: "stats/online/count").observe(.value) { [weak self] snapshot in
            self?.online = snapshot.value as? Int
        }
        listenToTodaysBrief()
    }

    /// Marks the student online while the app is in the foreground; the entry is removed
    /// if the connection drops.
    func setPresent(_ present: Bool) {
        let ref = Realtime.database.reference(withPath: "online/\(uid)")
        if present {
            ref.onDisconnectRemoveValue()
            ref.setValue(ServerValue.timestamp())
        } else {
            ref.removeValue()
        }
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        if let onlineHandle { Realtime.database.reference(withPath: "stats/online/count").removeObserver(withHandle: onlineHandle) }
        onlineHandle = nil
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

/// `ratings/{uid}_{moduleId}`: Glicko-2 for one module (PRD: "starting at 1,200").
nonisolated struct DuelRating: Decodable {
    var moduleId: String
    var rating: Double
    var rd: Double
    var duels: Int
    var wins: Int

    /// Below this deviation the rating reads as settled (functions/src/glicko.ts).
    var isSettled: Bool { rd <= 110 }
}

/// `matches/{matchId}` (the fields the lists need). Sparring keeps one `result`; a match
/// between students keeps `results` by player and their `names`.
nonisolated struct MatchSummary: Decodable, Identifiable {
    var id = ""
    var moduleId: String
    var status: String
    var isBot: Bool?
    var mode: String?
    var players: [String]?
    var names: [String: String]?
    var partner: Partner?
    var result: Result?
    var results: [String: Result]?
    var createdAt: Date?

    /// The result from `uid`'s side.
    func result(for uid: String) -> Result? { result ?? results?[uid] }

    func opponent(of uid: String) -> (uid: String, name: String)? {
        guard let other = players?.first(where: { $0 != uid }) else { return nil }
        return (other, names?[other] ?? "Student")
    }

    nonisolated struct Partner: Decodable {
        var level: Int
    }

    nonisolated struct Result: Decodable {
        var score: [Int]
        var winner: Int?
        var ratingBefore: Int
        var ratingAfter: Int
    }

    private enum CodingKeys: String, CodingKey {
        case moduleId, status, isBot, mode, players, names, partner, result, results, createdAt
    }
}

/// `challenges/{id}`: an async challenge between two students.
nonisolated struct ChallengeSummary: Decodable, Identifiable {
    var id = ""
    var players: [String]
    var names: [String: String]
    var moduleId: String
    var limitMs: Int
    var done: [String: Bool]
    var expiresAt: Date
    var createdAt: Date?
    /// "open", "complete", "expired" or "declined".
    var status: String
    var declinedAt: Date?
    var completedAt: Date?
    /// Each player's result once both halves are in; their `winner` 0 is them.
    var results: [String: Outcome]?

    nonisolated struct Outcome: Decodable {
        var winner: Int?
        var score: [Int]
    }

    func opponent(of uid: String) -> (uid: String, name: String) {
        let other = players.first { $0 != uid } ?? ""
        return (other, names[other] ?? "Student")
    }

    /// The student who sent it is always players[0].
    func isFrom(_ uid: String) -> Bool { players.first == uid }

    private enum CodingKeys: String, CodingKey {
        case players, names, moduleId, limitMs, done, expiresAt, createdAt, status, declinedAt, completedAt, results
    }
}

/// `news/{id}`: a headline and link (never article text), with an optional hand-written note.
nonisolated struct NewsStory: Decodable, Identifiable, Equatable {
    var id = ""
    var sourceId: String
    var source: String
    var title: String
    var url: String
    var publishedAt: Date
    var modules: [String]
    var whyItMatters: WhyItMatters?

    var link: URL? { URL(string: url) }

    nonisolated struct WhyItMatters: Decodable, Equatable {
        var text: String
        var lessonId: String
        var lessonTitle: String
        var moduleId: String
    }

    private enum CodingKeys: String, CodingKey {
        case sourceId, source, title, url, publishedAt, modules, whyItMatters
    }
}

/// `quizzes/{sunday}`: the weekly current-affairs quiz (PRD: "7 questions based on the week's stories").
nonisolated struct SundayQuiz: Decodable, Equatable {
    var sunday: String
    var questions: [Question]

    nonisolated struct Question: Decodable, Equatable {
        var prompt: String
        var options: [String]
        var correctIndex: Int
        var explanation: String
        var story: Story
    }

    nonisolated struct Story: Decodable, Equatable {
        var id: String
        var title: String
        var source: String
        var url: String
        var whyItMatters: NewsStory.WhyItMatters?

        var link: URL? { URL(string: url) }
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
        let lessons = modules.filter(canStudy).flatMap { content.lessons(in: $0) }
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

    var streak: Streak {
        Streak(activeDays: activeDays, today: .now, target: settings.weeklyTarget ?? Streak.defaultTarget, pausedWeeks: Set(settings.pausedWeeks ?? []))
    }
}

/// The weekly target (PRD: "active on 4 days of 7 ... The count is in weeks, not days").
/// Never punishes a missed day: the copy only ever says what keeps the week.
struct Streak {
    static let lookbackWeeks: Double = 26
    static let defaultTarget = 4
    /// PRD: "Exam pause: up to 3 weeks a year".
    static let pausesPerYear = 3

    let target: Int
    /// This week is paused for exams: nothing is asked of it.
    let isPaused: Bool

    /// Monday to Sunday of this week, and whether each was active.
    let week: [(date: Date, active: Bool)]
    let todayIndex: Int
    /// Weeks in a row that met the target, before this one.
    let previousWeeks: Int

    init(activeDays: Set<String>, today: Date, target: Int = Streak.defaultTarget, pausedWeeks: Set<String> = []) {
        self.target = target
        let calendar = UKDate.calendar
        let monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        isPaused = pausedWeeks.contains(UKDate.key(for: monday))
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
            // A paused week keeps the run going without asking anything of it.
            guard active >= target || pausedWeeks.contains(UKDate.key(for: start)) else { break }
            weeks += 1
            start = calendar.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
        }
        previousWeeks = weeks
    }

    var daysThisWeek: Int { week.count { $0.active } }

    var message: String {
        if isPaused { return "Paused for exams. Good luck." }
        let remaining = target - daysThisWeek
        let daysLeft = 7 - todayIndex - (week[todayIndex].active ? 1 : 0)
        if remaining <= 0 { return "Week done. Anything more is a bonus." }
        if remaining > daysLeft { return "A fresh week starts on Monday." }
        return remaining == 1 ? "One more day keeps the week." : "\(remaining) more days keep the week."
    }
}
