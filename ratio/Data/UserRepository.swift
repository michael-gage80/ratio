import FirebaseFirestore
import OSLog

/// Reads and writes `users/{uid}` (PRD: "Core Firestore collections"). Onboarding
/// (Phase 3) adds the profile fields; for now the document only records that the
/// account exists.
struct UserRepository {
    private let logger = Logger(subsystem: "com.mg.ratio", category: "UserRepository")

    /// Creates the user's document the first time they sign in. Safe to call on every
    /// sign-in; a failure is logged and retried next launch, since nothing on screen
    /// depends on the document yet.
    func ensureUserDocument(uid: String) async {
        let ref = Firestore.firestore().collection("users").document(uid)
        do {
            guard try await !ref.getDocument().exists else { return }
            try await ref.setData(["createdAt": FieldValue.serverTimestamp()])
        } catch {
            logger.error("Couldn't create users/\(uid, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }
}
