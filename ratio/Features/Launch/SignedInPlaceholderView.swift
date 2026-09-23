import SwiftUI

/// Temporary home after onboarding: a plain list of lessons by module, so the lesson
/// engine can be tried before the Pathway (Phase 9) and Today (Phase 10) exist.
struct SignedInPlaceholderView: View {
    let profile: UserProfile

    @Environment(SessionStore.self) private var session
    @Environment(ContentStore.self) private var content
    @State private var path: [Route] = []
    @State private var showsCatalog = false

    enum Route: Hashable {
        case overview(String)
        case lecture(String)
        case gallery
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        RatioMark(size: 44)
                        Text("Lessons").ratioFont(.h1)
                        Text("A preview list until the Pathway arrives.")
                            .ratioFont(.small)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(profile.modules ?? Module.allCases) { module in
                    Section {
                        let lessons = content.lessons(in: module)
                        if lessons.isEmpty {
                            Text("In preparation").ratioFont(.small).italic().foregroundStyle(Color.ratioInk2)
                        }
                        ForEach(lessons) { lesson in
                            NavigationLink(value: Route.overview(lesson.id)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(lesson.lessonNumber) · \(lesson.title)").ratioFont(.body)
                                    Text("\(lesson.estimatedMinutes) min").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                                }
                            }
                        }
                    } header: {
                        Text(module.title).ratioFont(.monoLabel)
                    }
                }
                Section {
                    #if DEBUG
                    NavigationLink("Interaction gallery", value: Route.gallery)
                    Button("Design system catalog") { showsCatalog = true }
                    #endif
                    Button("Log out", role: .destructive) { session.signOut() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ratioParchment.ignoresSafeArea())
            .foregroundStyle(Color.ratioInk)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .overview(let id):
                    if let lesson = content.lesson(id: id) {
                        LessonOverviewView(lesson: lesson, headline: profile.headline) {
                            path.append(.lecture(id))
                        }
                    }
                case .lecture(let id):
                    if let lesson = content.lesson(id: id) {
                        LectureView(lesson: lesson, headline: profile.headline) { path.removeAll() }
                    }
                case .gallery:
                    #if DEBUG
                    InteractionGalleryView()
                    #endif
                }
            }
        }
        #if DEBUG
        .sheet(isPresented: $showsCatalog) { DesignSystemCatalogView() }
        #endif
    }
}
