import FirebaseFunctions
import Foundation

/// The onboarding diagnostic (PRD: "10 adaptive questions… from the student's chosen
/// modules"). Item selection follows `selectionLogic` in the diagnostic bank and runs
/// on the device, so there's no network wait between questions; the answers are then
/// re-graded and scored by the `submitDiagnostic` Function, which writes the profile.
@Observable
final class DiagnosticModel {
    private(set) var current: Item?
    /// 1-based position of the current question.
    private(set) var number = 0
    /// Six questions (the bank serves up to ten; Mike cut it to six to get students in faster).
    static let questions = 6

    let total: Int
    /// Set when the current item is locked in; cleared on `advance()`.
    private(set) var lastAnswerCorrect: Bool?
    private(set) var responses: [ItemResponse] = []

    private var slots: [Module]
    private var remaining: [Module: [Item]]
    private var served: [Module: Int] = [:]
    private var lastAnswer: [Module: (difficulty: Double, correct: Bool)] = [:]
    private var nextSkill: [Module: Int] = [:]
    private var currentModule: Module?

    init(modules: [Module], seed: String, bank: DiagnosticBank) {
        let pools = Dictionary(uniqueKeysWithValues: modules.map { ($0, bank.items(for: $0)) })
        remaining = pools
        total = min(Self.questions, pools.values.reduce(0) { $0 + $1.count })
        slots = Self.slotPlan(modules: modules, total: total, seed: seed)
        advance()
    }

    var isFinished: Bool { responses.count == total }

    func lock(_ response: ItemResponse) {
        guard let item = current, let module = currentModule, lastAnswerCorrect == nil else { return }
        let correct = item.isCorrect(response)
        responses.append(response)
        lastAnswer[module] = (item.difficulty, correct)
        lastAnswerCorrect = correct
    }

    func advance() {
        lastAnswerCorrect = nil
        guard responses.count < total else {
            current = nil
            return
        }
        let module = moduleWithItems(preferring: slots[responses.count])
        currentModule = module
        current = pick(from: module)
        number = responses.count + 1
    }

    // MARK: Selection (diagnostic bank → selectionLogic)

    /// Steps 1–2: spread the slots as evenly as possible, rotating which modules get the
    /// extra ones by student so no module is systematically shortchanged, then
    /// interleave them so questions mix modules.
    private static func slotPlan(modules: [Module], total: Int, seed: String) -> [Module] {
        guard !modules.isEmpty else { return [] }
        let base = total / modules.count
        let extras = total % modules.count
        let offset = seed.unicodeScalars.reduce(0) { $0 + Int($1.value) } % modules.count
        var counts = modules.map { _ in base }
        for i in 0..<extras { counts[(offset + i) % modules.count] += 1 }

        var plan: [Module] = []
        while plan.count < total {
            for (i, module) in modules.enumerated() where counts[i] > 0 {
                plan.append(module)
                counts[i] -= 1
            }
        }
        return plan
    }

    /// Step 5: if a module has run out, spill to the least-served module that hasn't.
    private func moduleWithItems(preferring module: Module) -> Module {
        if remaining[module]?.isEmpty == false { return module }
        return remaining
            .filter { !$0.value.isEmpty }
            .keys
            .min { served[$0, default: 0] < served[$1, default: 0] } ?? module
    }

    /// Steps 3–4: rotate through the skills so each module covers knowledge,
    /// understanding and application before repeating one; within a skill, start at the
    /// median difficulty and step up after a correct answer, down after a wrong one.
    private func pick(from module: Module) -> Item? {
        guard var pool = remaining[module], !pool.isEmpty else { return nil }
        let skills = Skill.allCases
        let start = nextSkill[module, default: 0]
        let skillIndex = (0..<skills.count)
            .map { (start + $0) % skills.count }
            .first { index in pool.contains { $0.skill == skills[index] } } ?? start
        nextSkill[module] = skillIndex + 1

        let candidates = pool.filter { $0.skill == skills[skillIndex] }.sorted { $0.difficulty < $1.difficulty }
        let chosen: Item
        if candidates.isEmpty {
            chosen = pool[0]
        } else if let last = lastAnswer[module] {
            chosen = last.correct
                ? candidates.first { $0.difficulty > last.difficulty } ?? candidates.last!
                : candidates.last { $0.difficulty < last.difficulty } ?? candidates.first!
        } else {
            chosen = candidates[candidates.count / 2]
        }

        pool.removeAll { $0.id == chosen.id }
        remaining[module] = pool
        served[module, default: 0] += 1
        return chosen
    }
}

/// The onboarding banks, bundled at Resources/Content: diagnostic-bank.json (LLB, 48
/// items) and sqe1-diagnostic-bank.json (SQE1, 56 items), merged by module. The
/// scoring Function holds the same files.
struct DiagnosticBank: Decodable {
    private let totalItemsServedPerAttempt: Int
    private let modules: [String: Section]

    private struct Section: Decodable { let items: [Item] }

    var itemsPerAttempt: Int { totalItemsServedPerAttempt }

    func items(for module: Module) -> [Item] {
        modules[module.rawValue]?.items ?? []
    }

    static let files = ["diagnostic-bank", "sqe1-diagnostic-bank"]

    private init(totalItemsServedPerAttempt: Int, modules: [String: Section]) {
        self.totalItemsServedPerAttempt = totalItemsServedPerAttempt
        self.modules = modules
    }

    static func load() throws -> DiagnosticBank {
        let banks = try files.map { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            return try JSONDecoder().decode(DiagnosticBank.self, from: Data(contentsOf: url))
        }
        return DiagnosticBank(totalItemsServedPerAttempt: banks[0].totalItemsServedPerAttempt,
                              modules: banks.reduce(into: [:]) { $0.merge($1.modules) { first, _ in first } })
    }
}

/// Calls the `submitDiagnostic` Function (functions/src/index.ts).
enum DiagnosticService {
    private nonisolated struct Request: Encodable {
        var skipped: Bool?
        var responses: [ItemResponse]?
    }

    private nonisolated struct Response: Decodable {
        let headline: Headline
    }

    static func submit(_ responses: [ItemResponse]) async throws -> Headline {
        try await call(Request(responses: responses))
    }

    static func skip() async throws -> Headline {
        try await call(Request(skipped: true))
    }

    private static func call(_ request: Request) async throws -> Headline {
        let function = Functions.functions(region: "europe-west2")
            .httpsCallable("submitDiagnostic", requestAs: Request.self, responseAs: Response.self)
        return try await function.call(request).headline
    }
}
