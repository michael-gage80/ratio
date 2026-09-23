import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// A lesson's tests (PRD: lesson stage 3): `testServedPerAttempt` items from the pool,
/// weighted towards the student's weakest skill for the topic, never repeating an
/// earlier attempt's items while fresh ones remain ("a retake draws new items").
/// Answers are graded, scored and scheduled for review by the `submitTest` Function.
@Observable
final class TestModel {
    let lesson: Lesson
    let attemptId = UUID().uuidString
    private(set) var items: [Item] = []
    private(set) var responses: [ItemResponse] = []
    private(set) var weakestSkill: Skill = .application

    init(lesson: Lesson) {
        self.lesson = lesson
    }

    var current: Item? { items[safe: responses.count] }
    var isFinished: Bool { !items.isEmpty && responses.count == items.count }

    func answer(_ response: ItemResponse) {
        guard !isFinished else { return }
        responses.append(response)
    }

    /// Chooses this attempt's items.
    func prepare(headline: Headline?) async {
        var estimates: [Skill: Estimate] = [:]
        for skill in Skill.allCases {
            estimates[skill] = await SkillRepository().estimate(topicId: lesson.topicId, skill: skill)
        }
        weakestSkill = Skill.allCases.min {
            (estimates[$0] ?? headline?[$0] ?? .prior).score < (estimates[$1] ?? headline?[$1] ?? .prior).score
        } ?? .application
        items = Self.select(from: lesson.testPool, count: lesson.itemCounts.testServedPerAttempt,
                            weakest: weakestSkill, alreadyServed: await previouslyServed())
    }

    /// One of each skill where the pool allows (weakest first), then the rest from the
    /// weakest skill, then anything — drawing unseen items before repeating any.
    static func select(from pool: [Item], count: Int, weakest: Skill, alreadyServed: Set<String>) -> [Item] {
        let fresh = pool.filter { !alreadyServed.contains($0.id) }.shuffled()
        let seen = pool.filter { alreadyServed.contains($0.id) }.shuffled()
        let candidates = fresh.count >= count ? fresh : fresh + seen

        var chosen: [Item] = []
        let skillOrder = [weakest] + Skill.allCases.filter { $0 != weakest }
        for skill in skillOrder where chosen.count < count {
            if let item = candidates.first(where: { $0.skill == skill && !chosen.map(\.id).contains($0.id) }) {
                chosen.append(item)
            }
        }
        let rest = candidates.filter { item in !chosen.contains { $0.id == item.id } }
        chosen += (rest.filter { $0.skill == weakest } + rest.filter { $0.skill != weakest }).prefix(count - chosen.count)
        return chosen.shuffled()
    }

    private func previouslyServed() async -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot = try? await Firestore.firestore()
            .collection("users").document(uid).collection("testAttempts")
            .whereField("lessonId", isEqualTo: lesson.id)
            .getDocuments()
        return Set(snapshot?.documents.flatMap { $0.data()["itemIds"] as? [String] ?? [] } ?? [])
    }

    // MARK: Submission

    nonisolated struct Result: Decodable {
        nonisolated struct ItemResult: Decodable { let itemId: String; let correct: Bool }
        nonisolated struct Review: Decodable { let itemId: String; let dueAt: String }

        let results: [ItemResult]
        let topicBefore: [String: Estimate]
        let topicAfter: [String: Estimate]
        let headline: Headline
        let reviews: [Review]

        func correct(_ itemId: String) -> Bool { results.first { $0.itemId == itemId }?.correct ?? false }

        /// The server sends JavaScript ISO dates, which include milliseconds.
        func dueDate(_ itemId: String) -> Date? {
            reviews.first { $0.itemId == itemId }.flatMap {
                try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0.dueAt)
            }
        }
    }

    private nonisolated struct Request: Encodable {
        let attemptId: String
        let lessonId: String
        let responses: [ItemResponse]
    }

    func submit() async throws -> Result {
        let function = Functions.functions(region: "europe-west2")
            .httpsCallable("submitTest", requestAs: Request.self, responseAs: Result.self)
        let result = try await function.call(Request(attemptId: attemptId, lessonId: lesson.id, responses: responses))
        ActivityRepository.markToday()
        return result
    }
}
