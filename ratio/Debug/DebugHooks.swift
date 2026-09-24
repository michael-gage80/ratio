#if DEBUG
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Debug builds only, for checking screens in the simulator against the local Firebase
/// emulators (`firebase emulators:start`) with seeded test data. Launch arguments:
///   -emulators          use the emulators and sign in the test student
///   -user <email|none>  sign in someone else (e.g. newbie@ratio.test for onboarding)
///   -screen <name>      open a screen once signed in (see `DebugHooks.open`)
/// Nothing here is compiled into TestFlight or App Store builds.
enum DebugHooks {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var usesEmulators: Bool { arguments.contains("-emulators") }

    static var screen: String? {
        arguments.firstIndex(of: "-screen").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    static func configure() {
        guard usesEmulators else { return }
        let host = "127.0.0.1"
        Auth.auth().useEmulator(withHost: host, port: 9099)
        let settings = Firestore.firestore().settings
        settings.host = "\(host):8080"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        Functions.functions(region: "europe-west2").useEmulator(withHost: host, port: 5001)
        Realtime.database.useEmulator(withHost: host, port: 9000)
        Storage.storage().useEmulator(withHost: host, port: 9199)
        // "-user none" stays signed out (Welcome).
        let email = arguments.firstIndex(of: "-user").flatMap { arguments[safe: $0 + 1] } ?? "amara@ratio.test"
        if email == "none" {
            try? Auth.auth().signOut()
        } else {
            Task { _ = try? await Auth.auth().signIn(withEmail: email, password: "password") }
        }
    }

    /// Puts the app on a named screen.
    @MainActor
    static func open(_ navigator: AppNavigator) {
        guard let screen else { return }
        let lesson = "crime-03"
        switch screen {
        case "lessons": navigator.tab = .pathway
        case "overview": navigator.tab = .pathway; navigator.pathwayPath = [.overview(lesson)]
        case "lecture": navigator.tab = .pathway; navigator.pathwayPath = [.lecture(lesson)]
        case "library": navigator.tab = .pathway; navigator.pathwayPath = [.library]
        case "library-entry": navigator.tab = .pathway; navigator.pathwayPath = [.library, .libraryEntry("case:R v Woollin")]
        case "duel": navigator.tab = .duel
        case "duel-tutorial": navigator.tab = .duel; navigator.showsDuelTutorial = true
        case "boards": navigator.tab = .boards
        case "me": navigator.tab = .me
        case "settings": navigator.tab = .me; navigator.mePath = [.settings]
        case "module": navigator.tab = .me; navigator.mePath = [.module(.crime)]
        case "notifications": navigator.todayPath = [.notifications]
        case "news": navigator.todayPath = [.news]
        case "brief": navigator.todayPath = [.brief]
        case "paywall": navigator.paywall = "Contract is part of Ratio Plus."
        default: break
        }
    }
}
#endif
