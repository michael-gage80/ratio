/// The six LLB modules at launch (PRD: "Launch content"). Raw values are the
/// `moduleId`s used in the lesson JSON and on the student's profile; case order is
/// the order they're offered in and, by default, their order on the Pathway.
enum Module: String, CaseIterable, Identifiable, Codable {
    case crime
    case contract
    case tort
    case publicLaw = "public-law"
    case landLaw = "land-law"
    case equityTrusts = "equity-trusts"

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
}
