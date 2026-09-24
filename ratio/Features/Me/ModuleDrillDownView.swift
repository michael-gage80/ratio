import Charts
import SwiftUI

/// screens/29-module-drill-down.png — a module's topics with their three scores; tap
/// one to see how each score and its band have moved (PRD: "Tap a module to see its
/// topics, each with trend lines for all three scores and bands over time").
struct ModuleDrillDownView: View {
    let module: Module

    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded: String?

    private struct Topic: Identifiable {
        let id: String
        let title: String
        let lesson: Lesson?
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

    var body: some View {
        let topics = topics
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RatioPageHeader(eyebrow: "Me", title: module.title, subtitle: summary)
                    .padding(.bottom, RatioSpace.m)

                if topics.isEmpty {
                    Text("No topics assessed yet. \(module.title) lessons are in preparation.")
                        .ratioFont(.small)
                        .italic()
                        .foregroundStyle(Color.ratioInk2)
                } else {
                    header
                    ForEach(topics) { topic in
                        topicRow(topic)
                        Divider().overlay(Color.ratioRule)
                    }
                    Text("K knowledge · U understanding · A application")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, RatioSpace.m)
                }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.vertical, RatioSpace.s)
        }
        .ratioPage()
        .toolbarTitleDisplayMode(.inline)
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

    private func topicRow(_ topic: Topic) -> some View {
        let scores = student.topics[topic.id]
        let isExpanded = expanded == topic.id
        let title = Text(topic.title)
            .ratioFont(.h3)
            .italic(isExpanded)
            .foregroundStyle(isExpanded ? Color.ratioOxblood : Color.ratioInk)
            .multilineTextAlignment(.leading)
        let chevron = Image(systemName: "chevron.down")
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .foregroundStyle(Color.ratioInk2)
            .frame(width: 24)
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            Button {
                withAnimation(RatioMotion.tap) { expanded = isExpanded ? nil : topic.id }
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
            }
            .buttonStyle(.ratioPress)
            .accessibilityLabel(accessibilityLabel(topic, scores: scores))
            .accessibilityHint(isExpanded ? "Hides the trends" : "Shows how each score has moved")

            if isExpanded {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    if let scores {
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
                .padding(.bottom, RatioSpace.s)
                .transition(.opacity)
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
