import FirebaseAuth
import FirebaseFirestore
import OSLog

/// How far through each lesson's lecture the student is, at `users/{uid}/lessons/{lessonId}`
/// (PRD: "Progress saves after every part, and lessons work offline").
struct LessonProgressRepository {
    private let logger = Logger(subsystem: "com.mg.ratio", category: "LessonProgress")

    private func document(_ lessonId: String) -> DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("lessons").document(lessonId)
    }

    /// Parts of the lecture completed so far (0 if never started, or unreadable offline).
    func partsCompleted(lessonId: String) async -> Int {
        guard let ref = document(lessonId) else { return 0 }
        return (try? await ref.getDocument().data()?["partsCompleted"] as? Int) ?? 0
    }

    /// Saved to the local cache immediately and synced when there's a connection, so it
    /// doesn't wait on the network (or fail) offline.
    func save(lessonId: String, partsCompleted: Int) {
        document(lessonId)?.setData(
            ["partsCompleted": partsCompleted, "updatedAt": FieldValue.serverTimestamp()],
            merge: true
        ) { [logger] error in
            if let error { logger.error("Couldn't save progress for \(lessonId, privacy: .public): \(error.localizedDescription, privacy: .public)") }
        }
        ActivityRepository.markToday()
    }
}

/// Marks today (UK time) as an active day at `users/{uid}/activity/{date}`, for the
/// weekly streak target (PRD: "active on 4 days of 7"). Local-first, like progress.
enum ActivityRepository {
    static func markToday() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).collection("activity").document(UKDate.key())
            .setData(["at": FieldValue.serverTimestamp()]) { error in
                if let error {
                    Logger(subsystem: "com.mg.ratio", category: "Activity").error("Couldn't mark today active: \(error.localizedDescription, privacy: .public)")
                }
            }
    }
}
