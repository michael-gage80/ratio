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
/// everyone; opening one outside a free student's module needs Plus. On iPad the list
/// sits on the left and the selected entry on the right.
struct LibraryView: View {
    @Environment(ContentStore.self) private var content
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var kind: LibraryEntry.Kind = .cases
    @State private var module: Module?
    @State private var query = ""
    /// Nil until built (once, on first appearance).
    @State private var entries: [LibraryEntry]?
    /// iPad: the entry shown beside the list.
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.ratioWidth) private var width

    private var shown: [LibraryEntry] {
        (entries ?? []).filter { entry in
            entry.kind == kind && (module == nil || entry.module == module)
                && (query.isEmpty || entry.title.localizedStandardContains(query) || entry.subtitle.localizedStandardContains(query))
        }
    }

    var body: some View {
        Group {
            if width.isCompact {
                ScrollView { list(shown) }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView { list(shown) }
                        .frame(maxWidth: 440)
                    Rectangle().fill(Color.ratioRule).frame(width: 1).ignoresSafeArea(edges: .bottom)
                    ScrollView {
                        if let entry = (entries ?? []).first(where: { $0.id == selectedID }) {
                            LibraryEntryDetail(entry: entry)
                                .ratioReadableWidth()
                                .padding(RatioSpace.l)
                        } else {
                            RatioEmptyState(art: .openBook, message: "Choose a case, statute or doctrine map to read it here.")
                                .padding(.top, RatioSpace.xl)
                        }
                    }
                }
            }
        }
        .ratioPage()
        .scrollDismissesKeyboard(.interactively)
        .toolbar(.hidden, for: .navigationBar)
        .task { if entries == nil { entries = content.library() } }
        // ⌘F: search, on a hardware keyboard.
        .background {
            Button("Search") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func list(_ shown: [LibraryEntry]) -> some View {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    RatioPageHeader(eyebrow: "Lessons", title: "Library") { moduleFilter }
                    searchField
                    RatioSegmentedControl(options: LibraryEntry.Kind.allCases.map { ($0, $0.rawValue) }, selection: $kind)
                }
                .padding(.bottom, RatioSpace.m)

                if entries == nil {
                    ForEach(0..<6, id: \.self) { _ in
                        Divider().overlay(Color.ratioRule)
                        row(LibraryEntry.placeholder)
                    }
                    .ratioSkeleton()
                } else if shown.isEmpty {
                    RatioEmptyState(art: .openBook,
                                    message: query.isEmpty ? "Nothing here yet for \(module?.title ?? "this module")." : "No matches for “\(query)”.",
                                    actionTitle: query.isEmpty && module != nil ? "Show all modules" : (query.isEmpty ? nil : "Clear the search"),
                                    action: { query.isEmpty ? (module = nil) : (query = "") })
                } else {
                    Text("\(module.map { "\($0.title) · " } ?? "")\(shown.count) \(shown.count == 1 ? "entry" : "entries")")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .padding(.bottom, RatioSpace.xs)
                    ForEach(shown) { entry in
                        Divider().overlay(Color.ratioRule)
                        Button { open(entry) } label: {
                            row(entry)
                                .padding(.horizontal, width.isCompact ? 0 : RatioSpace.xs)
                                .background {
                                    if !width.isCompact && selectedID == entry.id {
                                        RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).fill(Color.ratioSunk)
                                    }
                                }
                        }
                        .buttonStyle(.ratioPress)
                        .contextMenu {
                            if let lesson = entry.lessons.first, student.canStudy(entry.module) {
                                Button("Open the lesson", systemImage: "book") { navigator.pathwayPath.append(.overview(lesson.id)) }
                            }
                            if supportsMultipleWindows, student.canStudy(entry.module) {
                                Button("Open in new window", systemImage: "macwindow.badge.plus") { openWindow(id: "item", value: SceneItem.libraryEntry(entry.id)) }
                            }
                        }
                    }
                    Divider().overlay(Color.ratioRule)
                }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.s)
            .padding(.bottom, RatioSpace.xl)
    }

    private var moduleFilter: some View {
        Menu {
            Picker("Module", selection: $module) {
                Text("All modules").tag(Module?.none)
                ForEach(student.programme.modules) { Text($0.title).tag(Module?.some($0)) }
            }
        } label: {
            Image(systemName: module == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Filter by module")
        .accessibilityValue(module?.title ?? "All modules")
    }

    private var searchField: some View {
        HStack(spacing: RatioSpace.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            TextField("Search the library", text: $query).ratioFont(.body).autocorrectionDisabled()
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ratioInk2)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, RatioSpace.s)
        .padding(.trailing, query.isEmpty ? RatioSpace.s : 0)
        .frame(minHeight: 48)
        .background(Color.ratioPaper, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ratioRule))
    }

    private func row(_ entry: LibraryEntry) -> some View {
        HStack(spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Group {
                    if entry.kind == .cases { CaseName.text(entry.title) } else { Text(entry.title) }
                }
                .ratioFont(.h3)
                .multilineTextAlignment(.leading)
                Text(entry.subtitle).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            Spacer(minLength: RatioSpace.xs)
            if student.canStudy(entry.module) {
                Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            } else {
                Image(systemName: "lock").foregroundStyle(Color.ratioInk2).accessibilityLabel("Ratio Plus")
            }
        }
        .padding(.vertical, RatioSpace.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func open(_ entry: LibraryEntry) {
        if student.canStudy(entry.module) {
            if width.isCompact {
                navigator.pathwayPath.append(.libraryEntry(entry.id))
            } else {
                withAnimation(RatioMotion.tap) { selectedID = entry.id }
            }
        } else {
            navigator.showPaywall(for: entry.module, freeModule: student.freeModule)
        }
    }
}

private extension LibraryEntry {
    /// Shaped like a real row, for the loading skeleton.
    static let placeholder = LibraryEntry(id: "placeholder", kind: .cases, title: "R v Placeholder Case",
                                          subtitle: "[1999] 1 AC 000 · House of Lords", module: .crime,
                                          component: .keyConcept(term: "", definition: ""), lessons: [])
}

/// One library entry in full, with links to the lessons it's taught in.
struct LibraryEntryView: View {
    let id: String

    @Environment(ContentStore.self) private var content
    /// Found once, rather than rebuilding the whole library on every render.
    @State private var entry: LibraryEntry?
    @State private var missing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                if let entry {
                    LibraryEntryDetail(entry: entry)
                } else if missing {
                    RatioEmptyState(message: "This entry isn't in the library any more.")
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.s)
            .padding(.bottom, RatioSpace.xl)
        }
        .ratioPage()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: id) {
            entry = content.library().first { $0.id == id }
            missing = entry == nil
        }
    }
}

/// An entry's component and the lessons it's taught in: a page on iPhone, the right-hand
/// side of the Library on iPad.
struct LibraryEntryDetail: View {
    let entry: LibraryEntry

    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            Text("\(entry.kind.rawValue) · \(entry.module.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            LessonComponentView(component: entry.component, moduleTitle: entry.module.title)
            lessons(entry)
        }
    }

    private func lessons(_ entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Taught in").ratioFont(.h3).padding(.bottom, RatioSpace.xs)
            ForEach(entry.lessons) { lesson in
                Divider().overlay(Color.ratioRule)
                Button { navigator.pathwayPath.append(.overview(lesson.id)) } label: {
                    HStack(spacing: RatioSpace.s) {
                        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                            Text("\(lesson.moduleId.title) · Lesson \(lesson.lessonNumber)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Text(lesson.title).ratioFont(.body).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: RatioSpace.xs)
                        Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
                    }
                    .padding(.vertical, RatioSpace.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
                .accessibilityElement(children: .combine)
            }
            Divider().overlay(Color.ratioRule)
        }
    }
}
