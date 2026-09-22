import FirebaseRemoteConfig
import Foundation

struct University: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    var aliases: [String]?

    /// Case- and accent-insensitive match on name, city or a common abbreviation
    /// ("KCL", "UWE").
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([name, city] + (aliases ?? [])).contains {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// The university list lives in Remote Config (PRD: "The list is kept in Remote
/// Config"), so it can be corrected without an App Store release. The bundled copy
/// is registered as the default, so the app works offline and before the first fetch.
/// To change the list, add a JSON parameter `universities` in the Firebase console
/// with the same shape as Resources/Content/universities.json.
enum UniversityDirectory {
    private static let key = "universities"

    /// Call once at launch, after `FirebaseApp.configure()`.
    static func configure() {
        let config = RemoteConfig.remoteConfig()
        if let bundled {
            config.setDefaults([key: bundled as NSData])
        }
        Task { _ = try? await config.fetchAndActivate() }
    }

    /// Sorted for scanning: "University of Leeds" files under L, not U.
    static var all: [University] {
        let data = RemoteConfig.remoteConfig().configValue(forKey: key).dataValue
        let list = (try? JSONDecoder().decode([University].self, from: data))
            ?? bundled.flatMap { try? JSONDecoder().decode([University].self, from: $0) }
            ?? []
        return list.sorted { sortKey($0.name) < sortKey($1.name) }
    }

    private static let bundled: Data? = Bundle.main
        .url(forResource: "universities", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }

    private static func sortKey(_ name: String) -> String {
        var key = name
        for prefix in ["The ", "University of the ", "University of "] where key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
        }
        return key.lowercased()
    }
}
