import FirebaseFirestore
import Foundation

/// Drives onboarding (PRD: "Onboarding, splash and diagnostic"). Each step saves to
/// `users/{uid}` as soon as it's completed, so a student who leaves part-way picks up
/// at the first step they haven't finished.
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case dateOfBirth = 1, name, programme
        // Phase 4 adds university and year + modules; Phase 5 the diagnostic.
    }

    /// Shown in the step counter ("02 / 06"), counting steps still to be built.
    static let totalSteps = 6

    enum AgeCheck { case adult, underage }

    let uid: String
    private(set) var profile: UserProfile
    private(set) var step: Step?
    private(set) var isSaving = false
    var errorMessage: String?

    private let users = UserRepository()

    init(uid: String, profile: UserProfile) {
        self.uid = uid
        self.profile = profile
        self.step = Self.firstIncompleteStep(in: profile)
    }

    var isComplete: Bool { step == nil }

    /// The date of birth can't be changed once saved, so the first step can't be revisited.
    var canGoBack: Bool {
        guard let step else { return false }
        return step.rawValue > Step.name.rawValue
    }

    func goBack() {
        guard canGoBack, let step else { return }
        self.step = Step(rawValue: step.rawValue - 1)
    }

    // MARK: Steps

    func saveDateOfBirth(_ date: Date) async -> AgeCheck {
        let age = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        guard age >= 18 else { return .underage }
        // Only the year is kept (PRD: "collects the minimum data it needs").
        let year = Calendar.current.component(.year, from: date)
        await save(["birthYear": year, "ageConfirmedAt": FieldValue.serverTimestamp()]) {
            $0.birthYear = year
        }
        return .adult
    }

    func saveName(firstName: String, initial: String?) async {
        var fields: [String: Any] = ["displayName": firstName]
        fields["initial"] = initial ?? FieldValue.delete()
        await save(fields) {
            $0.displayName = firstName
            $0.initial = initial
        }
    }

    func saveProgramme(waitlist: Set<String>) async {
        let list = waitlist.sorted()
        await save(["programme": "llb", "waitlist": list]) {
            $0.programme = "llb"
            $0.waitlist = list
        }
    }

    // MARK: Private

    private func save(_ fields: [String: Any], applying change: (inout UserProfile) -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await users.update(uid: uid, fields)
            change(&profile)
            step = step.flatMap { Step(rawValue: $0.rawValue + 1) }
        } catch {
            errorMessage = "We couldn't save that. Check your connection and try again."
        }
    }

    private static func firstIncompleteStep(in profile: UserProfile) -> Step? {
        if profile.birthYear == nil { return .dateOfBirth }
        if profile.displayName == nil { return .name }
        if profile.programme == nil { return .programme }
        return nil
    }
}
