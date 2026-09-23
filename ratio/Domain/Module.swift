/// The six LLB modules at launch (PRD: "Launch content"). Raw values are the module
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crime: "Crime"
        case .contract: "Contract"
        case .tort: "Tort"
        case .publicLaw: "Public law"
        case .landLaw: "Land law"
        case .equityTrusts: "Equity & Trusts"
        }
    }

    /// The module a topic ID belongs to, e.g. "crime.homicide.murder" → `.crime`.
    init?(topicId: String) {
        guard let prefix = topicId.split(separator: ".").first else { return nil }
        self.init(rawValue: String(prefix))
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
