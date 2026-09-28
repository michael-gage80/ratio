import SwiftUI

/// screens/43-news-centre.png — "The Week in Law": UK legal news from the last 7 days,
/// the lead story with its "Why it matters" note, a day-by-day list filtered by module,
/// and the Sunday quiz (PRD: "Legal awareness centre"). Stories open in Ratio's reader
/// where the source allows it, otherwise in Safari's Reader view in the app; subscriber-
/// only stories carry a lock and open in Safari (NewsReader.swift).
struct NewsCentreView: View {
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.ratioWidth) private var width
    @Environment(\.openURL) private var openURL
    @AppStorage(NewsReading.readKey) private var read = ""
    @State private var module: Module?
    @State private var takingQuiz = false
    @State private var safari: SafariLink?

    private var stories: [NewsStory] {
        guard let module else { return student.news }
        return student.news.filter { $0.modules.contains(module.rawValue) || $0.whyItMatters?.moduleId == module.rawValue }
    }

    /// The newest story with a note; failing that, the newest judgment; failing that, the newest story.
    private var lead: NewsStory? {
        stories.first { $0.whyItMatters != nil } ?? stories.first { $0.sourceId == "uksc" } ?? stories.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                masthead
                moduleChips
                if let lead {
                    LeadStory(story: lead, isRead: NewsReading.isRead(lead.id, in: read), open: { open(lead) }) { open(lesson: $0) }
                }
                if stories.isEmpty {
                    RatioEmptyState(art: .pediment, message: student.news.isEmpty
                        ? "The week's headlines appear here as they're published."
                        : "No stories for \(module?.title ?? "this module") this week.",
                        actionTitle: module == nil ? nil : "Show all modules") { module = nil }
                } else {
                    Text("From the week").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    if width.isCompact {
                        ForEach(days, id: \.title) { day in dayGroup(day) }
                    } else {
                        // iPad: the days side by side, like a newspaper's columns.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: RatioSpace.m, alignment: .top), count: 3),
                                  alignment: .leading, spacing: RatioSpace.m) {
                            ForEach(days, id: \.title) { day in dayGroup(day) }
                        }
                    }
                }
                if let quiz = student.quiz {
                    QuizCard(quiz: quiz) { takingQuiz = true }
                }
                Text("\(Image(systemName: "lock.fill")) Subscriber only: opens at the publisher.")
                    .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(RatioSpace.m)
        }
        .ratioPage()
        // No back button: swipe from the left edge to go back.
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $takingQuiz) {
            if let quiz = student.quiz { QuizView(quiz: quiz).ratioMeasuresWidth() }
        }
        .fullScreenCover(item: $safari) { SafariView(url: $0.url).ignoresSafeArea() }
    }

    private func open(_ story: NewsStory) {
        switch NewsOpening(story) {
        case .reader: navigator.push(.newsStory(story.id))
        case .inApp(let url):
            NewsReading.markRead(story.id, in: &read)
            safari = SafariLink(url: url)
        case .safari(let url):
            NewsReading.markRead(story.id, in: &read)
            openURL(url)
        case nil: break
        }
    }

    private func dayGroup(_ day: (title: String, stories: [NewsStory])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.title).ratioFont(.h2).italic()
            Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.top, RatioSpace.xs)
            ForEach(day.stories) { story in
                StoryRow(story: story, isRead: NewsReading.isRead(story.id, in: read), open: { open(story) }) { open(lesson: $0) }
                Divider().overlay(Color.ratioRule)
            }
        }
    }

    private var masthead: some View {
        // The deliberate exception to the page header: a newspaper masthead (screen 43).
        VStack(spacing: RatioSpace.s) {
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            Text("The Week \(Text("in").italic()) Law").ratioFont(.display).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            let monday = UKDate.calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            Text("Week of \(monday.formatted(.dateTime.day().month(.wide).year())) · UK law").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                .multilineTextAlignment(.center)
        }
        .padding(.top, RatioSpace.xs)
    }

    private var moduleChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: RatioSpace.xs) {
                chip("All", selected: module == nil) { module = nil }
                // Only modules with stories this week (news is tagged by LLB subject).
                ForEach(Module.allCases.filter { m in student.news.contains { $0.modules.contains(m.rawValue) || $0.whyItMatters?.moduleId == m.rawValue } }) { m in
                    chip(m.title, selected: module == m) { module = m }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Chips run to the screen edges rather than stopping at the page margin.
        .padding(.horizontal, -RatioSpace.m)
        .contentMargins(.horizontal, RatioSpace.m, for: .scrollContent)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .ratioFont(.body)
                .padding(.horizontal, RatioSpace.s)
                .frame(minHeight: 44)
                .foregroundStyle(selected ? Color.ratioParchment : Color.ratioInk)
                .background(selected ? Color.ratioInk : Color.ratioSunk, in: Capsule())
        }
        .buttonStyle(.ratioPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Stories after the lead, grouped by UK day: "Today", "Yesterday", then weekday names.
    private var days: [(title: String, stories: [NewsStory])] {
        let calendar = UKDate.calendar
        let rest = stories.filter { $0.id != lead?.id }
        let grouped = Dictionary(grouping: rest) { UKDate.key(for: $0.publishedAt) }
        return grouped.keys.sorted(by: >).map { key in
            let date = grouped[key]!.first!.publishedAt
            let title = calendar.isDateInToday(date) ? "Today" : calendar.isDateInYesterday(date) ? "Yesterday" : date.formatted(.dateTime.weekday(.wide))
            return (title, grouped[key]!)
        }
    }

    private func open(lesson lessonId: String) {
        navigator.push(.overview(lessonId))
    }
}

private struct LeadStory: View {
    let story: NewsStory
    let isRead: Bool
    let open: () -> Void
    let openLesson: (String) -> Void

    @Environment(\.ratioWidth) private var width

    var body: some View {
        Group {
            if width.isCompact {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    headline
                    if let why = story.whyItMatters {
                        WhyItMattersBox(why: why, openLesson: openLesson)
                    }
                    source
                }
            } else {
                // iPad: the headline on the left, why it matters beside it.
                ColumnsLayout(fraction: 0.58, spacing: RatioSpace.m) {
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        headline
                        source
                    }
                    if let why = story.whyItMatters {
                        WhyItMattersBox(why: why, openLesson: openLesson)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
            }
        }
        .ratioCard()
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(alignment: .top) {
                StoryMeta(story: story, isRead: isRead, lead: true)
                Spacer(minLength: RatioSpace.xs)
                if let module = story.modules.first.flatMap(Module.init(rawValue:)) { RatioTag(module.title) }
            }
            Text(story.title).ratioFont(.h1)
        }
    }

    @ViewBuilder
    private var source: some View {
        if let opening = NewsOpening(story) {
            Button(action: open) {
                Group {
                    switch opening {
                    case .reader:
                        Label("Read · \(story.reader?.minutes ?? 1) min", systemImage: "arrow.right")
                    case .inApp:
                        Label("Read", systemImage: "arrow.right")
                    case .safari:
                        Label("Read at \(story.source)", systemImage: "arrow.up.right")
                    }
                }
                .labelStyle(TrailingIconLabel())
                .ratioFont(.monoLabel)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.ratioPress)
            .foregroundStyle(Color.ratioInk)
        }
    }
}

/// "Law Society Gazette · 🔒 · 2h ago · Crime · ✓ Read"
private struct StoryMeta: View {
    let story: NewsStory
    let isRead: Bool
    var lead = false

    var body: some View {
        var parts: [Text] = []
        if lead { parts.append(Text("Lead")) }
        parts.append(Text(story.source))
        if story.paywalled == true { parts.append(Text(Image(systemName: "lock.fill")).accessibilityLabel("Subscriber only")) }
        parts.append(Text(story.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))))
        if !lead, let module = story.modules.first.flatMap(Module.init(rawValue:)) { parts.append(Text(module.title)) }
        if isRead { parts.append(Text("\(Image(systemName: "checkmark")) Read")) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
    }
}

struct WhyItMattersBox: View {
    let why: NewsStory.WhyItMatters
    let openLesson: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Why it matters").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
            Text(why.text).ratioFont(.body)
            Text("Links to \(Module(rawValue: why.moduleId)?.title ?? why.moduleId): \(why.lessonTitle).").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            Button { openLesson(why.lessonId) } label: {
                Text("Try the lesson →").ratioFont(.body).italic().underline().foregroundStyle(Color.ratioOxblood)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.ratioPress)
        }
        .ratioPanel()
    }
}

private struct StoryRow: View {
    let story: NewsStory
    let isRead: Bool
    let open: () -> Void
    let openLesson: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Button(action: open) {
                HStack(alignment: .top, spacing: RatioSpace.s) {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Text(story.title).ratioFont(.h3).multilineTextAlignment(.leading)
                        StoryMeta(story: story, isRead: isRead)
                    }
                    Spacer(minLength: RatioSpace.xs)
                    Image(systemName: icon).foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.ratioPress)
            .disabled(NewsOpening(story) == nil)
            .accessibilityHint(hint)
            if let why = story.whyItMatters {
                WhyItMattersBox(why: why, openLesson: openLesson)
            }
        }
        .padding(.vertical, RatioSpace.s)
    }

    private var icon: String {
        switch NewsOpening(story) {
        case .reader, .inApp: "arrow.right"
        default: "arrow.up.right"
        }
    }

    private var hint: String {
        switch NewsOpening(story) {
        case .reader: "Opens the story in Ratio"
        case .inApp: "Opens the story in the app"
        default: "Subscriber only. Opens the story at \(story.source) in Safari"
        }
    }
}

private struct QuizCard: View {
    let quiz: SundayQuiz
    let start: () -> Void

    @AppStorage private var score: Int
    @Environment(\.ratioWidth) private var width

    init(quiz: SundayQuiz, start: @escaping () -> Void) {
        self.quiz = quiz
        self.start = start
        _score = AppStorage(wrappedValue: -1, "quiz.score.\(quiz.sunday)")
    }

    var body: some View {
        Group {
            if width.isCompact {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    text
                    button
                }
            } else {
                // iPad: the button to the right of the text.
                HStack(alignment: .center, spacing: RatioSpace.m) {
                    VStack(alignment: .leading, spacing: RatioSpace.s) { text }
                    Spacer(minLength: 0)
                    button.frame(maxWidth: 320)
                }
            }
        }
        .ratioCard()
    }

    @ViewBuilder
    private var text: some View {
        Text(sundayTitle).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
        Text("Sunday quiz · \(Text("\(quiz.questions.count) questions").italic().foregroundStyle(Color.ratioOxblood)) on the week").ratioFont(.h2)
        Text(score >= 0 ? "You scored \(score) of \(quiz.questions.count). Counts as practice." : "Each question ties a story to the law you already know. Counts as practice.")
            .ratioFont(.body).foregroundStyle(Color.ratioInk2)
    }

    @ViewBuilder
    private var button: some View {
        if score >= 0 {
            RatioButton("Take it again", style: .tertiary, action: start)
        } else {
            RatioButton("Take the quiz →", style: .secondary, action: start)
        }
    }

    private var sundayTitle: String {
        let date = ISO8601DateFormatter().date(from: "\(quiz.sunday)T12:00:00Z") ?? .now
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RatioSpace.xs) {
            configuration.title
            configuration.icon
        }
    }
}
