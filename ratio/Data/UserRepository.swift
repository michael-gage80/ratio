import FirebaseAuth
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
    /// Written only by the scoring Functions once the diagnostic is done (or skipped),
    /// then after every test.
    var headline: Headline?
    var headlineUpdatedAt: Date?
    /// Set by the moderateAvatar Function when an approved photo goes live.
    var avatarVersion: Int?
    /// Written only by Functions: the App Store subscription, a university licence, and
    /// the module a free student studies in full.
    var subscription: Subscription?
    var licence: Licence?
    var freeModule: Module?
    var freeModuleChanges: Int?
    var settings: StudySettings?
    var consents: Consents?

    nonisolated struct Subscription: Decodable, Equatable {
        var plan: String
        var expiresAt: Date
        var revoked: Bool?
    }

    nonisolated struct Licence: Decodable, Equatable {
        var universityName: String
        var expiresAt: Date
        var revoked: Bool?
    }

    nonisolated struct Consents: Codable, Equatable {
        var analytics: Bool?
        var universitySharing: Bool?
    }
}

/// Study and notification preferences (Settings → Study), on users/{uid}.settings.
nonisolated struct StudySettings: Codable, Equatable {
    /// Days a week (PRD: "e.g. active on 4 days of 7, with the goal set by the student").
    var weeklyTarget: Int?
    /// Mondays (UK date keys) of weeks paused for exams — up to 3 a year (PRD).
    var pausedWeeks: [String]?
    var briefReminder: Bool?
    /// "08:30".
    var briefTime: String?
    var streakReminder: Bool?
    /// "19:00".
    var streakTime: String?
    /// Today's cards in the student's order, and the ones they've hidden.
    var homeOrder: [String]?
    var homeHidden: [String]?
    var quietStart: String?
    var quietEnd: String?
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

/// Reads the student's per-topic skill estimates, written by the scoring Function.
struct SkillRepository {
    /// The estimate for one skill in a topic, or `nil` if it hasn't been assessed yet.
    func estimate(topicId: String, skill: Skill) async -> Estimate? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snapshot = try? await Firestore.firestore()
            .collection("users").document(uid).collection("skills").document(topicId)
            .getDocument()
        guard let map = snapshot?.data()?[skill.rawValue] as? [String: Double],
              let theta = map["theta"], let sigma = map["sigma"] else { return nil }
        return Estimate(theta: theta, sigma: sigma)
    }
}
