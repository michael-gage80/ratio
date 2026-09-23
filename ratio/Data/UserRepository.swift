import FirebaseFirestore

/// The student's `users/{uid}` document (PRD: "Core Firestore collections"). Fields
/// are filled in step by step during onboarding; security rules only accept each one
/// once the age gate has been passed.
struct UserProfile: Decodable, Equatable {
    var birthYear: Int?
    var displayName: String?
    var initial: String?
    var programme: String?
    var waitlist: [String]?
    /// One of these is set: a listed university, or free text if it wasn't listed.
    var universityId: String?
    var universityOther: String?
    var year: Int?
    var modules: [Module]?
    /// Written only by the scoring Function once the diagnostic is done (or skipped).
    var headline: Headline?
}

/// Reads and writes `users/{uid}`.
struct UserRepository {
    private func document(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    /// Loads the profile, creating the document on first sign-in.
    func loadProfile(uid: String) async throws -> UserProfile {
        let ref = document(uid)
        let snapshot = try await ref.getDocument()
        guard snapshot.exists else {
            try await ref.setData(["createdAt": FieldValue.serverTimestamp()])
            return UserProfile()
        }
        return try snapshot.data(as: UserProfile.self)
    }

    func update(uid: String, _ fields: [String: Any]) async throws {
        try await document(uid).updateData(fields)
    }

    /// Only allowed by the rules while the age gate hasn't been passed, i.e. the
    /// document holds nothing but its creation time.
    func deleteProfile(uid: String) async throws {
        try await document(uid).delete()
    }
}
