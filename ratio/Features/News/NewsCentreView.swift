import SwiftUI

/// screens/43-news-centre.png — "The Week in Law": UK legal news from the last 7 days,
/// headline and link only, the lead story with its "Why it matters" note, a day-by-day
/// list filtered by module, and the Sunday quiz (PRD: "Legal awareness centre").
struct NewsCentreView: View {
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @State private var module: Module?
    @State private var takingQuiz = false

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
                    LeadStory(story: lead) { open(lesson: $0) }
                }
                if stories.isEmpty {
                    RatioEmptyState(art: .pediment, message: student.news.isEmpty
                        ? "The week's headlines appear here as they're published."
                        : "No stories for \(module?.title ?? "this module") this week.",
                        actionTitle: module == nil ? nil : "Show all modules") { module = nil }
                } else {
                    Text("From the week · Headline and link only").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    ForEach(days, id: \.title) { day in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(day.title).ratioFont(.h2).italic()
                            Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.top, RatioSpace.xs)
                            ForEach(day.stories) { story in
                                StoryRow(story: story) { open(lesson: $0) }
                                Divider().overlay(Color.ratioRule)
                            }
                        }
                    }
                }
                if let quiz = student.quiz {
                    QuizCard(quiz: quiz) { takingQuiz = true }
                }
                Text("Headlines link to the publisher.")
                    .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(RatioSpace.m)
        }
        .ratioPage()
        // No back button: swipe from the left edge to go back.
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $takingQuiz) {
            if let quiz = student.quiz { QuizView(quiz: quiz) }
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
                ForEach(Module.allCases) { m in
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
                .foregroundStyle(selected ? Color.ratioOnInk : Color.ratioInk)
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
    let openLesson: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(alignment: .top) {
                Text("Lead · \(story.source) · \(story.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))")
                    .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer(minLength: RatioSpace.xs)
                if let module = story.modules.first.flatMap(Module.init(rawValue:)) { RatioTag(module.title) }
            }
            Text(story.title).ratioFont(.h1)
            if let why = story.whyItMatters {
                WhyItMattersBox(why: why, openLesson: openLesson)
            }
            if let link = story.link {
                Link(destination: link) {
                    Label("Read at source", systemImage: "arrow.up.right").labelStyle(TrailingIconLabel())
                        .ratioFont(.monoLabel)
                }
                .foregroundStyle(Color.ratioInk)
                .frame(minHeight: 44)
            }
        }
        .ratioCard()
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
    let openLesson: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Link(destination: story.link ?? URL(fileURLWithPath: "/")) {
                HStack(alignment: .top, spacing: RatioSpace.s) {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Text(story.title).ratioFont(.h3).multilineTextAlignment(.leading)
                        Text(([story.source, story.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))]
                              + story.modules.prefix(1).compactMap { Module(rawValue: $0)?.title }).joined(separator: " · "))
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    Spacer(minLength: RatioSpace.xs)
                    Image(systemName: "arrow.up.right").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.ratioPress)
            .disabled(story.link == nil)
            .accessibilityHint("Opens the story at \(story.source)")
            if let why = story.whyItMatters {
                WhyItMattersBox(why: why, openLesson: openLesson)
            }
        }
        .padding(.vertical, RatioSpace.s)
    }
}

private struct QuizCard: View {
    let quiz: SundayQuiz
    let start: () -> Void

    @AppStorage private var score: Int

    init(quiz: SundayQuiz, start: @escaping () -> Void) {
        self.quiz = quiz
        self.start = start
        _score = AppStorage(wrappedValue: -1, "quiz.score.\(quiz.sunday)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text(sundayTitle).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("Sunday quiz · \(Text("\(quiz.questions.count) questions").italic().foregroundStyle(Color.ratioOxblood)) on the week").ratioFont(.h2)
            if score >= 0 {
                Text("You scored \(score) of \(quiz.questions.count). Counts as practice.").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                RatioButton("Take it again", style: .tertiary, action: start)
            } else {
                Text("Each question ties a story to the law you already know. Counts as practice.").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                RatioButton("Take the quiz →", style: .secondary, action: start)
            }
        }
        .ratioCard()
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
