import FirebaseAnalytics
import UserNotifications
import SwiftUI

/// Where the student is in the app: the selected tab and each tab's navigation stack.
@Observable
final class AppNavigator {
    enum Tab: Hashable {
        case today, pathway, duel, boards, me
    }

    var tab: Tab = .today
    var todayPath: [Route] = []
    var pathwayPath: [Route] = []
    var mePath: [Route] = []
    /// Set from Settings to replay the duel tutorial.
    var showsDuelTutorial = false
    /// A friend-lobby code from a shared link (ratio://lobby/K7MP4X).
    var lobbyCode: String?
    /// Set to open the Ratio Plus sheet, with why ("Contract is part of Ratio Plus.").
    var paywall: String?

    /// Opens the paywall for a module the student can't study on the free plan.
    func showPaywall(for module: Module, freeModule: Module?) {
        paywall = "\(module.title) is part of Ratio Plus." + (freeModule.map { " Your free module is \($0.title)." } ?? "")
    }

    /// Handles ratio:// links; returns whether it was one.
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "ratio", url.host() == "lobby", let code = url.pathComponents.dropFirst().first, code.count == 6 else { return false }
        lobbyCode = code.uppercased()
        tab = .duel
        return true
    }

    /// Pushes onto the current tab's stack.
    func push(_ route: Route) {
        switch tab {
        case .today: todayPath.append(route)
        case .me: mePath.append(route)
        default: pathwayPath.append(route)
        }
    }

    /// Opens a lesson's overview on the Pathway.
    func open(_ lesson: Lesson) {
        pathwayPath = [.overview(lesson.id)]
        tab = .pathway
    }

    /// "Back to Today" at the end of a debrief.
    func backToToday() {
        todayPath = []
        pathwayPath = []
        mePath = []
        tab = .today
    }
}

/// Pushed onto the Pathway and Me stacks.
enum Route: Hashable {
    case brief
    case news
    case settings
    case module(Module)
    case overview(String)
    case lecture(String)
}

/// The five tabs (PRD: "Today · Pathway · Duel · Boards · Me"; screens/00-design-system/
/// 02-components.png cell 19). The system tab bar gives Liquid Glass on iOS 26.
struct MainTabView: View {
    @State private var student: StudentStore
    @State private var navigator = AppNavigator()
    @Environment(DeepLinks.self) private var links

    init(uid: String, profile: UserProfile) {
        _student = State(initialValue: StudentStore(uid: uid, profile: profile))
    }

    /// Reminders are re-planned when anything they depend on changes.
    private var notificationKey: String {
        "\(student.activeDays.count)-\(student.items.count)-\(String(describing: student.settings))-\(UKDate.key())"
    }

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Today", systemImage: "house", value: .today) {
                NavigationStack(path: $navigator.todayPath) {
                    TodayView().withRoutes()
                }
            }
            Tab("Pathway", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: .pathway) {
                NavigationStack(path: $navigator.pathwayPath) {
                    PathwayView().withRoutes()
                }
            }
            Tab("Duel", systemImage: "bolt", value: .duel) {
                NavigationStack {
                    DuelView()
                }
            }
            Tab("Boards", systemImage: "chart.bar", value: .boards) {
                NavigationStack {
                    BoardsView()
                }
            }
            Tab("Me", systemImage: "person", value: .me) {
                NavigationStack(path: $navigator.mePath) {
                    MeView().withRoutes()
                }
            }
        }
        .tint(Color.ratioInk)
        .sheet(isPresented: Binding(get: { navigator.paywall != nil }, set: { if !$0 { navigator.paywall = nil } })) {
            PaywallView(reason: navigator.paywall?.isEmpty == false ? navigator.paywall : nil)
        }
        .environment(student)
        .environment(navigator)
        .task(id: notificationKey) { await RatioNotifications.reschedule(for: student) }
        .onChange(of: student.profile.consents?.analytics, initial: true) { _, consent in
            Analytics.setAnalyticsCollectionEnabled(consent == true)
        }
        .onAppear {
            AppDelegate.openChallenge = { [navigator] _ in navigator.tab = .duel }
            // Keep this phone's push token current once permission has been given.
            Task {
                if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        .onChange(of: links.pending, initial: true) { _, url in
            guard let url else { return }
            links.pending = nil
            _ = navigator.handle(url)
        }
        .onAppear { student.start() }
        .onDisappear { student.stop() }
    }
}

private struct RouteDestination: View {
    let route: Route

    @Environment(ContentStore.self) private var content
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        switch route {
        case .brief:
            BriefStepView()
        case .news:
            NewsCentreView()
        case .settings:
            SettingsView()
        case .module(let module):
            ModuleDrillDownView(module: module)
        case .overview(let id):
            if let lesson = content.lesson(id: id) {
                LessonOverviewView(lesson: lesson, headline: student.profile.headline) {
                    if student.canStudy(lesson.moduleId) {
                        navigator.push(.lecture(id))
                    } else {
                        navigator.showPaywall(for: lesson.moduleId, freeModule: student.freeModule)
                    }
                }
            }
        case .lecture(let id):
            if let lesson = content.lesson(id: id) {
                LectureView(lesson: lesson, headline: student.profile.headline) { navigator.backToToday() }
            }
        }
    }
}

private extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
