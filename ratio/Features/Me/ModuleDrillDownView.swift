import Charts
import SwiftUI

/// screens/29-module-drill-down.png — a module's topics with their three scores; tap
/// one to see how each score and its band have moved (PRD: "Tap a module to see its
/// topics, each with trend lines for all three scores and bands over time"). Filters
/// narrow the list to growth edges or topics with reviews due. On iPad
/// (screens/iPad/4-pathway-me-settings/03-module-drill-down.png) the module summary sits
/// on the left, and the selected topic's trends beside the table.
struct ModuleDrillDownView: View {
    let module: Module

    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width
    @State private var expanded: String?
    @State private var filter: Filter = .all

    private struct Topic: Identifiable {
        let id: String
        let title: String
        let lesson: Lesson?
    }

    private enum Filter: CaseIterable {
        case all, growth, review

        var title: String {
            switch self {
            case .all: "All topics"
            case .growth: "Growth edges"
            case .review: "Review due"
            }
        }
    }

    /// The module's lesson topics in teaching order, then any other topic with scores
    /// (e.g. from the diagnostic).
    private var topics: [Topic] {
        let lessons = content.lessons(in: module)
        let lessonTopics = lessons.map { Topic(id: $0.topicId, title: $0.title, lesson: $0) }
        let others = student.topics.keys
            .filter { Module(topicId: $0) == module && !lessons.map(\.topicId).contains($0) }
            .sorted()
            .map { Topic(id: $0, title: TopicGroup.title(forTopic: $0), lesson: nil) }
        return lessonTopics + others
    }

    /// Topics whose weakest score is below 50 or in the module's bottom third.
    private func growthEdges(_ topics: [Topic]) -> Set<String> {
        let weakest: [(id: String, score: Int)] = topics.compactMap { topic in
            guard let scores = student.topics[topic.id],
                  let low = Skill.allCases.compactMap({ scores[$0]?.displayScore }).min() else { return nil }
            return (topic.id, low)
        }
        let third = weakest.sorted { $0.score < $1.score }.prefix(weakest.count / 3).map(\.id)
        return Set(weakest.filter { $0.score < 50 }.map(\.id) + third)
    }

    /// Topics with a review item due now.
    private var reviewDue: Set<String> {
        let now = Date.now
        return Set(student.items.filter { $0.due <= now }.map(\.topicId))
    }

    var body: some View {
        let topics = topics
        let growth = growthEdges(topics)
        let due = reviewDue
        let shown = switch filter {
        case .all: topics
        case .growth: topics.filter { growth.contains($0.id) }
        case .review: topics.filter { due.contains($0.id) }
        }
        let counts: [Filter: Int] = [.all: topics.count, .growth: growth.count, .review: topics.count { due.contains($0.id) }]
        ScrollView {
            if width.isCompact {
                VStack(alignment: .leading, spacing: 0) {
                    RatioPageHeader(eyebrow: "Me", title: module.title, subtitle: summary)
                        .padding(.bottom, RatioSpace.m)

                    if topics.isEmpty {
                        noTopics
                    } else {
                        filters(counts)
                            .padding(.bottom, RatioSpace.s)
                        header
                        topicList(shown, inline: true)
                        legend
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, RatioSpace.m)
                    }
                }
                .padding(.horizontal, RatioSpace.m)
                .padding(.vertical, RatioSpace.s)
            } else {
                wide(topics: topics, shown: shown, counts: counts)
            }
        }
        .ratioPage()
        .toolbarTitleDisplayMode(.inline)
    }

    // MARK: iPad

    private func wide(topics: [Topic], shown: [Topic], counts: [Filter: Int]) -> some View {
        // The topic whose trends show: the chosen one, else the first with scores.
        let selected = topics.first { $0.id == expanded } ?? topics.first { student.topics[$0.id] != nil } ?? topics.first
        return ColumnsLayout(fraction: 0.38, spacing: RatioSpace.l) {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                ModuleIllustration(module: module)
                    .frame(height: 160)
                    .padding(RatioSpace.m)
                    .frame(maxWidth: .infinity)
                    .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous).strokeBorder(Color.ratioRule) }
                RatioPageHeader(eyebrow: "Me", title: module.title, subtitle: summary)
                if let mastery = student.mastery(of: content.lessons(in: module)) {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        HStack {
                            Text("Mastery").ratioFont(.monoLabel)
                            Spacer()
                            Text("\(mastery)%").ratioFont(.monoData)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ratioRule)
                                Capsule().fill(Color.ratioInk).frame(width: proxy.size.width * Double(mastery) / 100)
                            }
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
                acrossTheModule(topics)
                legend
            }
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                if topics.isEmpty {
                    noTopics
                } else {
                    filters(counts)
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        topicList(shown, inline: false, selected: selected?.id)
                    }
                    if let selected {
                        trendPanel(selected)
                    }
                }
            }
        }
        .padding(.horizontal, RatioSpace.l)
        .padding(.vertical, RatioSpace.m)
    }

    /// The module's scores averaged across its assessed topics.
    @ViewBuilder
    private func acrossTheModule(_ topics: [Topic]) -> some View {
        let scored = topics.compactMap { student.topics[$0.id] }
        if !scored.isEmpty {
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Across the module").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Spacer()
                    RatioTag("Hypothesis")
                }
                ForEach(Skill.allCases) { skill in
                    let estimates = scored.compactMap { $0[skill] }
                    SkillRow(title: skill.title, estimate: estimates.isEmpty ? nil : Estimate(
                        theta: estimates.map(\.theta).reduce(0, +) / Double(estimates.count),
                        sigma: estimates.map(\.sigma).reduce(0, +) / Double(estimates.count)
                    ))
                }
                Text("Bands narrow as you answer more. A wide band means we're less sure.")
                    .ratioFont(.small)
                    .italic()
                    .foregroundStyle(Color.ratioInk2)
            }
            .ratioCard()
        }
    }

    /// The selected topic's trends, the lessons in its group, and Practise.
    private func trendPanel(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text(topic.title).ratioFont(.h1).italic().foregroundStyle(Color.ratioOxblood)
            trends(topic)
            if let lesson = topic.lesson {
                let group = TopicGroup.groupId(of: lesson.topicId)
                let set = content.lessons(in: module).filter { TopicGroup.groupId(of: $0.topicId) == group }
                if set.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Drill set · \(TopicGroup.title(forGroup: group))")
                            Spacer()
                            Text("\(set.count) lessons")
                        }
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .padding(.bottom, RatioSpace.xs)
                        Rectangle().fill(Color.ratioInk).frame(height: 1)
                        ForEach(set) { item in
                            NavigationLink(value: Route.overview(item.id)) {
                                HStack(spacing: RatioSpace.s) {
                                    Text(item.title).ratioFont(.body).multilineTextAlignment(.leading)
                                    Spacer(minLength: RatioSpace.xs)
                                    LessonStateLabel(state: student.state(of: item))
                                }
                                .padding(.vertical, RatioSpace.s)
                            }
                            .buttonStyle(.ratioPress)
                            Divider().overlay(Color.ratioRule)
                        }
                    }
                }
            }
        }
        .ratioCard()
    }

    // MARK: Shared

    private var noTopics: some View {
        Text("No topics assessed yet. \(module.title) lessons are in preparation.")
            .ratioFont(.small)
            .italic()
            .foregroundStyle(Color.ratioInk2)
    }

    private var legend: some View {
        Text("K knowledge · U understanding · A application")
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
    }

    /// All topics · Growth edges · Review due, each with its count.
    private func filters(_ counts: [Filter: Int]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: RatioSpace.xs) {
                ForEach(Filter.allCases, id: \.self) { option in
                    let selected = option == filter
                    Button {
                        withAnimation(RatioMotion.tap) { filter = option }
                    } label: {
                        HStack(spacing: RatioSpace.xs) {
                            Text(option.title).ratioFont(.body)
                            Text("\(counts[option] ?? 0)").ratioFont(.monoData).opacity(0.75)
                        }
                        .padding(.horizontal, RatioSpace.s)
                        .frame(minHeight: 44)
                        // Parchment on ink flips with the theme (ink turns light in dark mode).
                        .foregroundStyle(selected ? Color.ratioParchment : Color.ratioInk)
                        .background(selected ? Color.ratioInk : Color.ratioPaper, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.ratioRule))
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func topicList(_ shown: [Topic], inline: Bool, selected: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                Text(filter == .review ? "Nothing due for review in \(module.title)." : "No growth edges in \(module.title) right now.")
                    .ratioFont(.small)
                    .italic()
                    .foregroundStyle(Color.ratioInk2)
                    .padding(.vertical, RatioSpace.s)
            }
            ForEach(shown) { topic in
                topicRow(topic, inline: inline, isSelected: topic.id == selected)
                Divider().overlay(Color.ratioRule)
            }
        }
    }

    private var summary: String {
        let lessons = content.lessons(in: module)
        guard !lessons.isEmpty else { return "Scores from your diagnostic, where you answered \(module.title) questions." }
        let secure = lessons.count { student.state(of: $0) == .secure }
        return "\(secure) of \(lessons.count) lessons secure. Tap a topic to see how each score has moved."
    }

    private var header: some View {
        VStack(spacing: RatioSpace.xs) {
            if !typeSize.isAccessibilitySize {
                HStack(spacing: RatioSpace.xs) {
                    Text("Topic")
                    Spacer()
                    ForEach(Skill.allCases) { Text(String($0.title.prefix(1))).frame(width: 40) }
                    Color.clear.frame(width: 24)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .accessibilityHidden(true)
            }
            Rectangle().fill(Color.ratioInk).frame(height: 1)
        }
    }

    /// `inline`: the trends open under the row (iPhone); otherwise the row selects the
    /// topic for the trend panel (iPad).
    private func topicRow(_ topic: Topic, inline: Bool, isSelected: Bool = false) -> some View {
        let scores = student.topics[topic.id]
        let isExpanded = inline ? expanded == topic.id : isSelected
        let title = Text(topic.title)
            .ratioFont(.h3)
            .italic(isExpanded)
            .foregroundStyle(isExpanded ? Color.ratioOxblood : Color.ratioInk)
            .multilineTextAlignment(.leading)
        let chevron = Image(systemName: inline ? "chevron.down" : "chevron.right")
            .rotationEffect(.degrees(inline && isExpanded ? 180 : 0))
            .foregroundStyle(isExpanded && !inline ? Color.ratioOxblood : Color.ratioInk2)
            .frame(width: 24)
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            Button {
                withAnimation(RatioMotion.tap) { expanded = inline && isExpanded ? nil : topic.id }
            } label: {
                Group {
                    if typeSize.isAccessibilitySize {
                        // Title on its own line, then the scores spelt out.
                        VStack(alignment: .leading, spacing: RatioSpace.xs) {
                            HStack(alignment: .firstTextBaseline) {
                                title
                                Spacer(minLength: RatioSpace.xs)
                                chevron
                            }
                            Text(Skill.allCases.map { skill in "\(skill.title.prefix(1)) \(scores?[skill].map { "\($0.displayScore)" } ?? "–")" }.joined(separator: " · "))
                                .ratioFont(.monoData)
                                .foregroundStyle(Color.ratioInk2)
                        }
                    } else {
                        HStack(spacing: RatioSpace.xs) {
                            title
                            Spacer(minLength: RatioSpace.xs)
                            ForEach(Skill.allCases) { skill in
                                Text(scores?[skill].map { "\($0.displayScore)" } ?? "–")
                                    .ratioFont(.monoData)
                                    .frame(width: 40)
                            }
                            chevron
                        }
                    }
                }
                .padding(.vertical, RatioSpace.s)
                .padding(.horizontal, inline ? 0 : RatioSpace.xs)
                .background(!inline && isSelected ? Color.ratioPaper : Color.clear, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
            }
            .buttonStyle(.ratioPress)
            .accessibilityLabel(accessibilityLabel(topic, scores: scores))
            .accessibilityHint(inline ? (isExpanded ? "Hides the trends" : "Shows how each score has moved") : "Shows how each score has moved")
            .accessibilityAddTraits(!inline && isSelected ? .isSelected : [])

            if inline && isExpanded {
                trends(topic)
                    .padding(.bottom, RatioSpace.s)
                    .transition(.opacity)
            }
        }
    }

    /// Each skill's trend card, and Practise.
    private func trends(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            if let scores = student.topics[topic.id] {
                ForEach(Skill.allCases) { skill in
                    TrendCard(skill: skill, scores: scores)
                }
                Text("Bands narrow as you answer more. A wide band means we're less sure.")
                    .ratioFont(.small)
                    .italic()
                    .foregroundStyle(Color.ratioInk2)
            } else {
                Text("Not assessed yet. Take this lesson's tests to start the trend.").ratioFont(.small)
            }
            if let lesson = topic.lesson {
                NavigationLink(value: Route.overview(lesson.id)) {
                    HStack(spacing: RatioSpace.xs) {
                        Text("Practise \(topic.title)").multilineTextAlignment(.center)
                        Image(systemName: "arrow.right")
                    }
                    .ratioFont(.h3)
                    .padding(.horizontal, RatioSpace.s)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule) }
                }
                .buttonStyle(.ratioPress)
            }
        }
    }

    private func accessibilityLabel(_ topic: Topic, scores: TopicScores?) -> String {
        let values = Skill.allCases.map { skill in
            scores?[skill].map { "\(skill.title) \($0.displayScore)" } ?? "\(skill.title) not assessed"
        }
        return ([topic.title] + values).joined(separator: ", ")
    }
}

/// One skill's score over time, with its band shaded (screen 29).
private struct TrendCard: View {
    let skill: Skill
    let scores: TopicScores

    private struct Point: Identifiable {
        let date: Date
        let estimate: Estimate
        var id: Date { date }
    }

    /// Snapshots from each scored attempt; topics scored before history was kept show
    /// their current estimate alone.
    private var points: [Point] {
        let history = (scores.history ?? []).compactMap { snapshot in snapshot[skill].map { Point(date: snapshot.at, estimate: $0) } }
        if !history.isEmpty { return history }
        return scores[skill].map { [Point(date: scores.updatedAt ?? .now, estimate: $0)] } ?? []
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack {
                Text(skill.title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer()
                if let current = scores[skill] {
                    Text("\(current.displayScore) ±\(current.band)").ratioFont(.monoData)
                }
            }
            if let first = points.first {
                chart(points)
                HStack {
                    Text(first.date.formatted(.dateTime.day().month(.abbreviated)))
                    Spacer()
                    Text("Now")
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            } else {
                Text("Not assessed yet.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            }
        }
        .ratioCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func chart(_ points: [Point]) -> some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Low", max(0, point.estimate.displayScore - point.estimate.band)),
                    yEnd: .value("High", min(100, point.estimate.displayScore + point.estimate.band)),
                    series: .value("Series", "band")
                )
                .foregroundStyle(Color.ratioOxblood.opacity(0.16))
                LineMark(x: .value("Date", point.date), y: .value("Score", point.estimate.displayScore), series: .value("Series", "score"))
                    .foregroundStyle(Color.ratioInk)
            }
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value("Score", last.estimate.displayScore))
                    .foregroundStyle(Color.ratioInk)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [25, 50, 75]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Color.ratioRule)
            }
        }
        .frame(height: 96)
    }

    private var accessibilityText: String {
        guard let first = points.first?.estimate, let last = points.last?.estimate else { return "\(skill.title): not assessed yet" }
        return "\(skill.title): \(last.displayScore) plus or minus \(last.band), from \(first.displayScore) plus or minus \(first.band) at first."
    }
}
