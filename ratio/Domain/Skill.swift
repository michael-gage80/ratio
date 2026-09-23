import Foundation

/// The three core skills every item is tagged with (PRD: "Student profile and scoring
/// model").
enum Skill: String, Codable, CaseIterable, Identifiable {
    case knowledge, understanding, application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .knowledge: "Knowledge"
        case .understanding: "Understanding"
        case .application: "Application"
        }
    }

    /// How the skill reads in a sentence: "Strong recall; application is your growth edge."
    var phrase: String {
        switch self {
        case .knowledge: "recall"
        case .understanding: "understanding"
        case .application: "application"
        }
    }
}

/// A rating θ and uncertainty σ on the logit scale, as written by the scoring Function
/// (functions/src/scoring.ts). Shown as a 0–100 score with a ± band.
nonisolated struct Estimate: Codable, Equatable {
    var theta: Double
    var sigma: Double

    static let prior = Estimate(theta: 0, sigma: 1)

    var score: Int { Int((100 * logistic(theta)).rounded()) }

    /// Half the width of the likely range on the 0–100 scale.
    var band: Int { Int((100 * (logistic(theta + sigma) - logistic(theta - sigma)) / 2).rounded()) }

    /// Never show 100 unless the band is narrow (PRD).
    var displayScore: Int { band > 6 ? min(score, 99) : score }

    private func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
}

/// The headline estimate per skill on `users/{uid}`.
nonisolated struct Headline: Codable, Equatable {
    var knowledge: Estimate
    var understanding: Estimate
    var application: Estimate

    subscript(skill: Skill) -> Estimate {
        switch skill {
        case .knowledge: knowledge
        case .understanding: understanding
        case .application: application
        }
    }
}

/// A plain-English summary of the three scores (PRD: "Archetypes"): named for the
/// strongest skill, with the weakest framed as the growth edge. Always a hypothesis.
struct Archetype: Equatable {
    let name: String
    let summary: String

    init(_ headline: Headline) {
        let bySkill = Skill.allCases.map { ($0, headline[$0]) }
        if bySkill.allSatisfy({ $0.1 == .prior }) {
            name = "Open Book"
            summary = "You skipped the diagnostic, so every band starts wide. Your profile takes shape as you answer."
            return
        }
        let ranked = bySkill.sorted { $0.1.score > $1.1.score }
        let (strongest, weakest) = (ranked.first!, ranked.last!)
        if strongest.1.score - weakest.1.score < 5 {
            name = "All-rounder"
            summary = "Recall, understanding and application are evenly matched. This will sharpen as you play."
            return
        }
        switch strongest.0 {
        case .knowledge: name = "Recogniser"
        case .understanding: name = "Analyst"
        case .application: name = "Advocate"
        }
        summary = "Strong \(strongest.0.phrase); \(weakest.0.phrase) is your growth edge. This will change as you play."
    }

    /// The skill to lead with when there's a clear gap, e.g. to highlight in the chart.
    static func growthEdge(_ headline: Headline) -> Skill? {
        let ranked = Skill.allCases.sorted { headline[$0].score < headline[$1].score }
        guard let weakest = ranked.first, let strongest = ranked.last,
              headline[strongest].score - headline[weakest].score >= 5 else { return nil }
        return weakest
    }
}
