import SwiftUI

/// Where the student is in the app: the selected tab and each tab's navigation stack.
@Observable
final class AppNavigator {
    enum Tab: Hashable {
        case today, pathway, duel, boards, me
    }

    var tab: Tab = .today
    var pathwayPath: [Route] = []
    var mePath: [Route] = []

    /// Opens a lesson's overview on the Pathway.
    func open(_ lesson: Lesson) {
        pathwayPath = [.overview(lesson.id)]
        tab = .pathway
    }

    /// "Back to Today" at the end of a debrief.
    func backToToday() {
        pathwayPath = []
        mePath = []
        tab = .today
    }
}

/// Pushed onto the Pathway and Me stacks.
enum Route: Hashable {
    case module(Module)
    case overview(String)
    case lecture(String)
}

/// The five tabs (PRD: "Today · Pathway · Duel · Boards · Me"; screens/00-design-system/
/// 02-components.png cell 19). The system tab bar gives Liquid Glass on iOS 26.
struct MainTabView: View {
    @State private var student: StudentStore
    @State private var navigator = AppNavigator()

    init(uid: String, profile: UserProfile) {
        _student = State(initialValue: StudentStore(uid: uid, profile: profile))
    }

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Today", systemImage: "house", value: .today) {
                TodayPlaceholderView()
            }
            Tab("Pathway", systemImage: "point.topleft.down.to.point.bottomright.curvepath", value: .pathway) {
                NavigationStack(path: $navigator.pathwayPath) {
                    PathwayView().withRoutes()
                }
            }
            Tab("Duel", systemImage: "bolt", value: .duel) {
                ComingSoonView(title: "Duel", art: .scales, detail: "Head-to-head rounds against other students and sparring partners arrive in a later build.")
            }
            Tab("Boards", systemImage: "chart.bar", value: .boards) {
                ComingSoonView(title: "Boards", art: .pediment, detail: "Daily, weekly and monthly boards arrive with duels.")
            }
            Tab("Me", systemImage: "person", value: .me) {
                NavigationStack(path: $navigator.mePath) {
                    MeView().withRoutes()
                }
            }
        }
        .tint(Color.ratioInk)
        .environment(student)
        .environment(navigator)
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
        case .module(let module):
            ModuleDrillDownView(module: module)
        case .overview(let id):
            if let lesson = content.lesson(id: id) {
                LessonOverviewView(lesson: lesson, headline: student.profile.headline) {
                    switch navigator.tab {
                    case .me: navigator.mePath.append(.lecture(id))
                    default: navigator.pathwayPath.append(.lecture(id))
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

/// Today until the daily brief lands (Phase 10): a greeting and a way back into lessons.
private struct TodayPlaceholderView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("\(greeting), \(Text("\(student.profile.displayName ?? "there").").italic())")
                    .ratioFont(.display)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Daily brief").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("Your daily brief arrives in the next build. Until then, carry on from the Pathway.")
                        .ratioFont(.body)
                    if let lesson = student.nextLesson(in: student.profile.modules ?? Module.allCases, content: content) {
                        RatioButton("Continue: \(lesson.title)", style: .secondary) { navigator.open(lesson) }
                    }
                }
                .padding(20)
                .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.ratioRule) }
            }
            .padding(24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

private struct ComingSoonView: View {
    let title: String
    let art: RatioSpotArt
    let detail: String

    var body: some View {
        VStack(spacing: 20) {
            art.view.frame(width: 120).foregroundStyle(Color.ratioInk)
            Text(title + ".").ratioFont(.display)
            Text(detail).ratioFont(.body).multilineTextAlignment(.center).foregroundStyle(Color.ratioInk2)
            RatioTag("Soon")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }
}
