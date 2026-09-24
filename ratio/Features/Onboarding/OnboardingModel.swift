import FirebaseFirestore
import Foundation

/// Drives onboarding (PRD: "Onboarding, splash and diagnostic"). Each step saves to
/// `users/{uid}` as soon as it's completed, so a student who leaves part-way picks up
/// at the first step they haven't finished.
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case dateOfBirth = 1, name, programme, university, modules, diagnostic
    }

    /// Shown in the step counter ("02 / 06").
    static var totalSteps: Int { Step.allCases.count }

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

    func saveUniversity(id: String) async {
        await save(["universityId": id, "universityOther": FieldValue.delete()]) {
            $0.universityId = id
            $0.universityOther = nil
        }
    }

    func saveUniversity(other name: String) async {
        await save(["universityOther": name, "universityId": FieldValue.delete()]) {
            $0.universityOther = name
            $0.universityId = nil
        }
    }

    /// Modules are stored in canonical order, which is also their order in Lessons.
    func saveModules(_ modules: Set<Module>) async {
        let ordered = Module.allCases.filter(modules.contains)
        await save(["modules": ordered.map(\.rawValue)]) {
            $0.modules = ordered
        }
    }

    /// The scoring Function has already saved the headline; this just moves on.
    func finishDiagnostic(headline: Headline) {
        profile.headline = headline
        step = nil
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
        if profile.universityId == nil && profile.universityOther == nil { return .university }
        if (profile.modules ?? []).isEmpty { return .modules }
        if profile.headline == nil { return .diagnostic }
        return nil
    }
}
