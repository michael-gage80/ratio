import FirebaseAuth
import SwiftUI

/// Something opened in its own window beside the main one (iPad Stage Manager or Split
/// View): "Open in new window" on a lesson or a library entry.
nonisolated enum SceneItem: Codable, Hashable {
    case lesson(String)
    case libraryEntry(String)
}

/// A second window showing one lesson or library entry, with its own navigation so the
/// lesson's overview can go on to its lecture. The main window keeps its tabs.
struct ItemWindow: View {
    let item: SceneItem?

    @Environment(SessionStore.self) private var session
    @State private var student: StudentStore?
    @State private var navigator: AppNavigator = {
        let navigator = AppNavigator()
        // Pushes go to the Lessons stack, which this window shows.
        navigator.tab = .pathway
        return navigator
    }()

    var body: some View {
        @Bindable var navigator = navigator
        Group {
            if let student, let item {
                NavigationStack(path: $navigator.pathwayPath) {
                    root(item).withRoutes()
                }
                .environment(student)
                .environment(navigator)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ratioMeasuresWidth()
        .ratioPage()
        .task(id: session.state) { await load() }
        .onDisappear { student?.stop() }
    }

    @ViewBuilder
    private func root(_ item: SceneItem) -> some View {
        switch item {
        case .lesson(let id): RouteDestination(route: .overview(id))
        case .libraryEntry(let id): LibraryEntryView(id: id)
        }
    }

    /// The signed-in student's store, as the main window has.
    private func load() async {
        guard student == nil, case .signedIn(let uid) = session.state,
              let profile = try? await UserRepository().loadProfile(uid: uid) else { return }
        let store = StudentStore(uid: uid, profile: profile)
        store.start()
        student = store
    }
}
