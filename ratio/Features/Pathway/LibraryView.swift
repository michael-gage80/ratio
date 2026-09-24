import SwiftUI

/// One case, statute or doctrine map from the lectures, with the lessons it appears in.
struct LibraryEntry: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case cases = "Cases"
        case legislation = "Legislation"
        case maps = "Doctrine maps"

        var id: String { rawValue }
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let module: Module
    let component: LessonComponent
    var lessons: [Lesson]
}

extension ContentStore {
    /// Every case, statute and doctrine map in the lectures, once each, A–Z.
    func library() -> [LibraryEntry] {
        var entries: [String: LibraryEntry] = [:]
        for module in Module.allCases {
            for lesson in lessons(in: module) {
                for component in lesson.parts.flatMap(\.components) {
                    let entry: LibraryEntry? = switch component {
                    case .caseCard(let card):
                        LibraryEntry(id: "case:\(card.caseName)", kind: .cases, title: card.caseName,
                                     subtitle: "\(card.citation) · \(card.court)", module: module, component: component, lessons: [])
                    case .statute(let citation, _, _):
                        LibraryEntry(id: "statute:\(citation)", kind: .legislation, title: citation,
                                     subtitle: module.title, module: module, component: component, lessons: [])
                    case .doctrineMap(let map):
                        LibraryEntry(id: "map:\(module.rawValue):\(map.title)", kind: .maps, title: map.title,
                                     subtitle: module.title, module: module, component: component, lessons: [])
                    default: nil
                    }
                    guard let entry else { continue }
                    if entries[entry.id, default: entry].lessons.last?.id != lesson.id {
                        entries[entry.id, default: entry].lessons.append(lesson)
                    }
                }
            }
        }
        return entries.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// The Library in Lessons: every case, piece of legislation and doctrine map, searchable
/// and filtered by module, each linking back to its lessons. Everything is listed for
/// everyone; opening one outside a free student's module needs Plus.
struct LibraryView: View {
    @Environment(ContentStore.self) private var content
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @State private var kind: LibraryEntry.Kind = .cases
    @State private var module: Module?
    @State private var query = ""
    @State private var entries: [LibraryEntry] = []

    private var shown: [LibraryEntry] {
        entries.filter { entry in
            entry.kind == kind && (module == nil || entry.module == module)
                && (query.isEmpty || entry.title.localizedStandardContains(query) || entry.subtitle.localizedStandardContains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $kind) {
                    ForEach(LibraryEntry.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if shown.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet for this module." : "No matches for “\(query)”.")
                        .ratioFont(.body)
                        .foregroundStyle(Color.ratioInk2)
                }
                ForEach(shown) { entry in
                    Button { open(entry) } label: { row(entry) }
                        .buttonStyle(.plain)
                }
            } footer: {
                Text("\(shown.count) \(shown.count == 1 ? "entry" : "entries")").ratioFont(.monoLabel)
            }
            .listRowBackground(Color.ratioPaper)
        }
        .scrollContentBackground(.hidden)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .searchable(text: $query, prompt: "Search the library")
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Module", selection: $module) {
                        Text("All modules").tag(Module?.none)
                        ForEach(Module.allCases) { Text($0.title).tag(Module?.some($0)) }
                    }
                } label: {
                    Image(systemName: module == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by module")
            }
        }
        .task { if entries.isEmpty { entries = content.library() } }
    }

    private func row(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if entry.kind == .cases { CaseName.text(entry.title) } else { Text(entry.title) }
                }
                .ratioFont(.h3)
                .multilineTextAlignment(.leading)
                Text(entry.subtitle).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            Spacer(minLength: 8)
            if !student.canStudy(entry.module) {
                Image(systemName: "lock").imageScale(.small).foregroundStyle(Color.ratioInk2).accessibilityLabel("Ratio Plus")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func open(_ entry: LibraryEntry) {
        if student.canStudy(entry.module) {
            navigator.pathwayPath.append(.libraryEntry(entry.id))
        } else {
            navigator.showPaywall(for: entry.module, freeModule: student.freeModule)
        }
    }
}

/// One library entry in full, with links to the lessons it's taught in.
struct LibraryEntryView: View {
    let id: String

    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        ScrollView {
            if let entry = content.library().first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(entry.kind.rawValue) · \(entry.module.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    LessonComponentView(component: entry.component, moduleTitle: entry.module.title)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("In \(entry.lessons.count == 1 ? "this lesson" : "these lessons")").ratioFont(.h3).padding(.bottom, 8)
                        ForEach(entry.lessons) { lesson in
                            Divider().overlay(Color.ratioRule)
                            Button { navigator.pathwayPath.append(.overview(lesson.id)) } label: {
                                HStack {
                                    Text("\(lesson.moduleId.title) \(lesson.lessonNumber) · \(lesson.title)").ratioFont(.body).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbarTitleDisplayMode(.inline)
    }
}
