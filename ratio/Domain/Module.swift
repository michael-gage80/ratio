import Foundation

/// The modules: the six LLB core modules at launch (PRD: "Launch content"), the LLB
/// options added since — Company law, EU law, Human rights, Jurisprudence, Employment
/// law and Family law — then the SQE1 Functioning Legal Knowledge subjects
/// (Ratio-Lesson-Spine.md, part two). Raw values are the module
/// IDs used throughout the content — lesson `moduleId`s, topic ID prefixes
/// ("public.judicial-review…") and the diagnostic bank — and on the student's profile.
/// Case order is the order they're offered in and, by default, their Pathway order.
enum Module: String, CaseIterable, Identifiable, Codable {
    case crime
    case contract
    case tort
    case publicLaw = "public"
    case landLaw = "land"
    case equityTrusts = "equity"
    case companyLaw = "companylaw"
    case euLaw = "eulaw"
    case humanRights = "humanrights"
    case jurisprudence
    case employmentLaw = "employmentlaw"
    case familyLaw = "familylaw"
    case sqeDisputeResolution = "sqe1-dispute-resolution"
    case sqeLegalSystem = "sqe1-legal-system-legal-services"
    case sqeBusinessLaw = "sqe1-business-law-practice"
    case sqePropertyPractice = "sqe1-property-practice"
    case sqeWills = "sqe1-wills-estates"
    case sqeAccounts = "sqe1-solicitors-accounts"
    case sqeCriminalPractice = "sqe1-criminal-law-practice"

    var id: String { rawValue }

    var programme: Programme { rawValue.hasPrefix("sqe1-") ? .sqe1 : .llb }

    /// Which SQE1 paper examines it (Functioning Legal Knowledge 1 or 2).
    var paper: String? {
        switch self {
        case .sqeDisputeResolution, .sqeLegalSystem, .sqeBusinessLaw: "FLK1"
        case .sqePropertyPractice, .sqeWills, .sqeAccounts, .sqeCriminalPractice: "FLK2"
        default: nil
        }
    }

    var title: String {
        switch self {
        case .crime: "Crime"
        case .contract: "Contract"
        case .tort: "Tort"
        case .publicLaw: "Public law"
        case .landLaw: "Land law"
        case .equityTrusts: "Equity & Trusts"
        case .companyLaw: "Company law"
        case .euLaw: "EU law"
        case .humanRights: "Human rights"
        case .jurisprudence: "Jurisprudence"
        case .employmentLaw: "Employment law"
        case .familyLaw: "Family law"
        case .sqeDisputeResolution: "Dispute resolution"
        case .sqeLegalSystem: "Legal system & services"
        case .sqeBusinessLaw: "Business law & practice"
        case .sqePropertyPractice: "Property practice"
        case .sqeWills: "Wills & estates"
        case .sqeAccounts: "Solicitors accounts"
        case .sqeCriminalPractice: "Criminal law & practice"
        }
    }

    /// The module a topic ID belongs to, e.g. "crime.homicide.murder" → `.crime`, and
    /// "sqe1.dispute-resolution.limitation" → `.sqeDisputeResolution`.
    init?(topicId: String) {
        let parts = topicId.split(separator: ".")
        guard let first = parts.first else { return nil }
        if first == "sqe1", parts.count > 1 {
            self.init(sqeSubject: String(parts[1]))
        } else {
            self.init(rawValue: String(first))
        }
    }

    /// SQE1 topic IDs name the subject in their second part, which may be shorter than
    /// the module ID ("dispute-resolution" in "sqe1-dispute-resolution").
    private init?(sqeSubject subject: String) {
        guard let module = Module.allCases.first(where: { $0.programme == .sqe1 && $0.rawValue.dropFirst(5).hasPrefix(subject) }) else { return nil }
        self = module
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Early test profiles (before the IDs were aligned with the content) stored
        // "public-law", "land-law" and "equity-trusts".
        let legacy = ["public-law": "public", "land-law": "land", "equity-trusts": "equity"]
        guard let module = Module(rawValue: legacy[raw] ?? raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown module \(raw)"))
        }
        self = module
    }
}

/// The route a student is studying for. Each has its own modules; a student sees their
/// programme's modules and can switch programme in Settings.
enum Programme: String, CaseIterable, Identifiable {
    case llb
    case sqe1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llb: "LLB"
        case .sqe1: "SQE1"
        }
    }

    var detail: String {
        switch self {
        case .llb: "Bachelor of Laws · undergraduate"
        case .sqe1: "Solicitors Qualifying Examination, stage 1"
        }
    }

    var modules: [Module] { Module.allCases.filter { $0.programme == self } }

    /// The programme stored on a profile ("llb" if it isn't set yet).
    init(profile value: String?) {
        self = value.flatMap(Programme.init(rawValue:)) ?? .llb
    }
}

/// An SQE1 sitting ("2027-01"): the exam runs in January and July. Stored on the profile
/// as `sqeSitting`; shown on Me with how long is left.
enum SQESitting {
    /// The next four sittings.
    static func upcoming(from date: Date = .now) -> [String] {
        let calendar = UKDate.calendar
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let all = (year...year + 2).flatMap { ["\($0)-01", "\($0)-07"] }
        let current = String(format: "%04d-%02d", year, month)
        return Array(all.filter { $0 > current }.prefix(4))
    }

    /// "January 2027".
    static func title(_ sitting: String) -> String {
        guard let start = start(of: sitting) else { return sitting }
        return start.formatted(.dateTime.month(.wide).year())
    }

    /// "18 weeks to go", or nil once it has passed.
    static func countdown(_ sitting: String, from date: Date = .now) -> String? {
        guard let start = start(of: sitting), start > date else { return nil }
        let weeks = UKDate.calendar.dateComponents([.weekOfYear], from: date, to: start).weekOfYear ?? 0
        return weeks < 1 ? "This month" : "\(weeks) \(weeks == 1 ? "week" : "weeks") to go"
    }

    private static func start(of sitting: String) -> Date? {
        UKDate.date(fromKey: sitting + "-01")
    }
}
