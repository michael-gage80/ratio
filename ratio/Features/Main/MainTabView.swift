import FirebaseAnalytics
import UserNotifications
import SwiftUI

/// Where the student is in the app: the selected tab and each tab's navigation stack.
@Observable
final class AppNavigator {
    enum Tab: Hashable {
        case today, pathway, duel, boards, me
        /// A module in the iPad sidebar's "Your modules": Lessons, open on that module.
        case module(Module)
    }

    var tab: Tab = .today
    var todayPath: [Route] = []
    var pathwayPath: [Route] = []
    var mePath: [Route] = []
    /// The module open in Lessons (set by the module cards, or the sidebar on iPad).
    var lessonsModule: Module?
    /// Set from Settings to replay the duel tutorial.
    var showsDuelTutorial = false
    /// "Replay tutorials" in Settings: the Today tour, then the duel tutorial.
    var replayingTutorials = false
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
    case notifications
    case library
    case libraryEntry(String)
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var network = NetworkMonitor()

    init(uid: String, profile: UserProfile) {
        _student = State(initialValue: StudentStore(uid: uid, profile: profile))
    }

    @Environment(ContentStore.self) private var content

    /// "Your modules" in the iPad sidebar, each with its mastery.
    @TabContentBuilder<AppNavigator.Tab>
    private var moduleTabs: some TabContent<AppNavigator.Tab> {
        TabSection(student.programme == .sqe1 ? "Your subjects" : "Your modules") {
            ForEach(student.modules) { module in
                Tab(value: AppNavigator.Tab.module(module)) {
                    lessons
                } label: {
                    Text(module.title)
                }
                .badge(Text(masteryLabel(module)))
                .tabPlacement(.sidebarOnly)
            }
        }
        .tabPlacement(.sidebarOnly)
    }

    private func masteryLabel(_ module: Module) -> String {
        student.mastery(of: content.lessons(in: module)).map { "\($0)%" } ?? ""
    }

    /// Lessons, reached from its tab or a module in the sidebar.
    private var lessons: some View {
        @Bindable var navigator = navigator
        return NavigationStack(path: $navigator.pathwayPath) {
            PathwayView().withRoutes()
        }
        .ratioMeasuresWidth()
    }

    /// "UCL · Year 2", or "SQE1 · January 2027" under the name in the sidebar.
    private var profileDetail: String {
        let profile = student.profile
        let university = UniversityDirectory.shortName(id: profile.universityId) ?? profile.universityOther
        let stage = student.programme == .sqe1 ? profile.sqeSitting.map { SQESitting.title($0) } : profile.year.map { "Year \($0)" }
        return [university, stage].compactMap { $0 }.joined(separator: " · ")
    }

    /// Reminders are re-planned when anything they depend on changes.
    private var notificationKey: String {
        "\(student.activeDays.count)-\(student.items.count)-\(String(describing: student.settings))-\(UKDate.key())"
    }

    var body: some View {
        @Bindable var navigator = navigator
        // A tab bar on iPhone and in narrow windows; a sidebar on iPad (iOS 26
        // sidebar-adaptable), with the student's modules under the five sections.
        TabView(selection: $navigator.tab) {
            Tab("Today", systemImage: "house", value: .today) {
                NavigationStack(path: $navigator.todayPath) {
                    TodayView().withRoutes()
                }
                .ratioMeasuresWidth()
            }
            Tab("Lessons", systemImage: "book", value: .pathway) {
                lessons
            }
            Tab("Duel", systemImage: "bolt", value: .duel) {
                NavigationStack {
                    DuelView()
                }
                .ratioMeasuresWidth()
            }
            Tab("Boards", systemImage: "chart.bar", value: .boards) {
                NavigationStack {
                    BoardsView()
                }
                .ratioMeasuresWidth()
            }
            Tab("Me", systemImage: "person", value: .me) {
                NavigationStack(path: $navigator.mePath) {
                    MeView().withRoutes()
                }
                .ratioMeasuresWidth()
            }
            // Sidebar only (iPad, regular width): on iPhone they'd push Me into "More".
            if horizontalSizeClass == .regular {
                moduleTabs
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader {
            Text("Ratio\(Text(".").foregroundStyle(Color.ratioOxblood))")
                .ratioFont(.h1)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tabViewSidebarBottomBar {
            Button { navigator.tab = .me } label: {
                HStack(spacing: RatioSpace.s) {
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 40)
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text([student.profile.displayName, student.profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " "))
                            .ratioFont(.h3)
                        Text(profileDetail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(RatioSpace.s)
            }
            .buttonStyle(.ratioPress)
        }
        .onChange(of: navigator.tab) { _, tab in
            if case .module(let module) = tab { navigator.lessonsModule = module }
        }
        .tint(Color.ratioInk)
        .overlay(alignment: .top) {
            if !network.isOnline {
                OfflineBanner()
                    .padding(.top, RatioSpace.xxs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(RatioMotion.reveal, value: network.isOnline)
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
        .onAppear {
            student.start()
            #if DEBUG
            DebugHooks.open(navigator)
            #endif
        }
        .onDisappear {
            student.setPresent(false)
            student.stop()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in student.setPresent(phase == .active) }
    }
}

struct RouteDestination: View {
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
        case .notifications:
            NotificationsView()
        case .library:
            LibraryView()
        case .libraryEntry(let id):
            LibraryEntryView(id: id)
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

extension View {
    /// Pushes `Route`s on the enclosing NavigationStack.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteDestination(route: $0) }
    }
}
