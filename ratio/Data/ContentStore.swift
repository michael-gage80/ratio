import CryptoKit
import FirebaseStorage
import Foundation
import OSLog

/// The lessons the app can show (PRD: "Content bundles"). Starts from the lessons
/// bundled in the app, overlays any newer module bundle already downloaded, and on
/// `refresh()` checks Cloud Storage for newer ones — so a content fix reaches students
/// without an App Store release, and lessons still work offline.
@Observable
final class ContentStore {
    private struct ModuleContent {
        var version: String
        var lessons: [Lesson]
    }

    /// The published bundle format — see content-tools/publish.mjs.
    private struct ModuleBundle: Decodable {
        let moduleId: Module
        let version: String
        let lessons: [Lesson]
    }

    private struct Manifest: Decodable {
        struct Entry: Decodable {
            let version: String
            let path: String
            let sha256: String
        }
        let modules: [String: Entry]
    }

    private var modules: [Module: ModuleContent] = [:]
    private let logger = Logger(subsystem: "com.mg.ratio", category: "ContentStore")

    /// Bundled lessons count as version 0.0.0, so any published bundle supersedes them.
    private static let bundledVersion = "0.0.0"

    init() {
        modules = Self.loadBundled()
        for module in Module.allCases {
            if let cached = Self.loadCached(module), Self.isNewer(cached.version, than: modules[module]?.version) {
                modules[module] = ModuleContent(version: cached.version, lessons: cached.lessons)
            }
        }
    }

    func lessons(in module: Module) -> [Lesson] {
        modules[module]?.lessons ?? []
    }

    func lesson(id: String) -> Lesson? {
        modules.values.lazy.flatMap(\.lessons).first { $0.id == id }
    }

    /// A test item and its lesson, for brief steps that draw items from anywhere.
    func testItem(id: String) -> (item: Item, lesson: Lesson)? {
        for lesson in modules.values.lazy.flatMap(\.lessons) {
            if let item = lesson.testPool.first(where: { $0.id == id }) { return (item, lesson) }
        }
        return nil
    }

    /// Fact and rule decoys for an IRAC item: real facts and rules from the other IRAC
    /// problems in the same module, picked in a stable order for the item.
    func iracDecoys(for itemId: String, in module: Module) -> (facts: [String], rules: [String]) {
        let others = lessons(in: module)
            .flatMap { $0.parts.map(\.interaction) + $0.testPool }
            .filter { $0.id != itemId }
            .compactMap { item -> (facts: [String], rule: String)? in
                if case .irac(let facts, let answer) = item.kind { return (facts, answer.rule) }
                return nil
            }
        var generator = SeededGenerator(seed: itemId)
        return (others.flatMap(\.facts).shuffled(using: &generator).prefix(2).map { $0 },
                others.map(\.rule).shuffled(using: &generator).prefix(2).map { $0 })
    }

    /// Downloads any module bundle newer than what's loaded. Call once signed in (the
    /// bucket only serves signed-in students). Failures leave current content in place.
    func refresh() async {
        let storage = Storage.storage()
        do {
            let manifestData = try await storage.reference(withPath: "content/manifest.json").data(maxSize: 1 << 20)
            let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
            for (id, entry) in manifest.modules {
                guard let module = Module(rawValue: id), Self.isNewer(entry.version, than: modules[module]?.version) else { continue }
                let data = try await storage.reference(withPath: entry.path).data(maxSize: 20 << 20)
                guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == entry.sha256 else {
                    logger.error("Bundle \(entry.path, privacy: .public) failed its checksum")
                    continue
                }
                let bundle = try JSONDecoder().decode(ModuleBundle.self, from: data)
                try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
                try data.write(to: Self.cacheURL(module), options: .atomic)
                modules[module] = ModuleContent(version: bundle.version, lessons: bundle.lessons.sorted { $0.lessonNumber < $1.lessonNumber })
                logger.info("Updated \(id, privacy: .public) to \(entry.version, privacy: .public)")
            }
        } catch {
            // No manifest yet (nothing published), offline, or a bad bundle: keep what we have.
            logger.info("Content refresh skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Loading

    private static func loadBundled() -> [Module: ModuleContent] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let lessons = urls
            .filter { $0.lastPathComponent.firstMatch(of: /^[a-z]+-\d{2}-/) != nil }
            .compactMap { url -> Lesson? in
                do {
                    return try JSONDecoder().decode(Lesson.self, from: Data(contentsOf: url))
                } catch {
                    Logger(subsystem: "com.mg.ratio", category: "ContentStore")
                        .error("Couldn't decode \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                    return nil
                }
            }
        return Dictionary(grouping: lessons, by: \.moduleId).mapValues {
            ModuleContent(version: bundledVersion, lessons: $0.sorted { $0.lessonNumber < $1.lessonNumber })
        }
    }

    private static func loadCached(_ module: Module) -> ModuleBundle? {
        guard let data = try? Data(contentsOf: cacheURL(module)) else { return nil }
        return try? JSONDecoder().decode(ModuleBundle.self, from: data)
    }

    private static var cacheDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Content", directoryHint: .isDirectory)
    }

    private static func cacheURL(_ module: Module) -> URL {
        cacheDirectory.appending(path: "\(module.rawValue).json")
    }

    /// Semantic-version comparison; anything is newer than nothing.
    private static func isNewer(_ candidate: String, than current: String?) -> Bool {
        guard let current else { return true }
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }
}
