import SwiftUI

/// screens/25-pathway.png — each chosen module as a map of its lessons, grouped by
/// topic, with the student's state on every lesson (PRD: "Pathway"). Tap a lesson to
/// open it; press and hold to peek at its topic scores.
struct PathwayView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @State private var selected: Module?
    @State private var peeking: String?

    private var modules: [Module] { student.profile.modules ?? Module.allCases }
    private var module: Module { selected ?? modules.first ?? .crime }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pathway.").ratioFont(.display)
                    Text([student.profile.year.map { "Year \($0)" }, "Ordered by your modules"].compactMap { $0 }.joined(separator: " · "))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                }
                .padding(.horizontal, 24)

                moduleCards

                VStack(alignment: .leading, spacing: 20) {
                    contentsHeader
                    let lessons = content.lessons(in: module)
                    if lessons.isEmpty {
                        planned
                    } else {
                        Text("Press and hold a lesson to see its topic scores")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                        ForEach(Array(TopicGroup.groups(of: lessons).enumerated()), id: \.element.id) { index, group in
                            groupSection(group, index: index)
                        }
                        if let date = lessons.first?.lawStatedDate {
                            Text("Law stated as at \(date) · Educational, not legal advice")
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .sensoryFeedback(.impact(weight: .light), trigger: peeking) { _, new in new != nil }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Modules

    private var moduleCards: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(modules) { module in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selected = module
                            peeking = nil
                        }
                    } label: {
                        ModuleCard(module: module, mastery: student.mastery(of: content.lessons(in: module)), isSelected: module == self.module)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private var contentsHeader: some View {
        let lessons = content.lessons(in: module)
        let count = lessons.isEmpty ? Spine.lessons(in: module).count : lessons.count
        let topics = TopicGroup.groups(of: lessons).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(module.title) \(Text("contents").italic().foregroundStyle(Color.ratioInk2))").ratioFont(.h2)
                Spacer()
                Text(lessons.isEmpty ? "\(count) lessons planned" : "\(topics) topics · \(count) lessons")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
            }
            Rectangle().fill(Color.ratioInk).frame(height: 1)
        }
    }

    // MARK: Lessons

    private func groupSection(_ group: TopicGroup, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(Self.numeral(index + 1)).ratioFont(.h2).italic().foregroundStyle(Color.ratioOxblood).frame(width: 36, alignment: .leading)
                Text(group.title).ratioFont(.h2).italic()
                Spacer()
                Text(group.lessons.count == 1 ? "1 lesson" : "\(group.lessons.count) lessons")
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
            }
            .padding(.vertical, 14)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(group.lessons.enumerated()), id: \.element.id) { lessonIndex, lesson in
                Divider().overlay(Color.ratioRule)
                lessonRow(lesson, number: "\(index + 1).\(lessonIndex + 1)", group: group)
            }
            Rectangle().fill(Color.ratioRule).frame(height: 1)
        }
    }

    private func lessonRow(_ lesson: Lesson, number: String, group: TopicGroup) -> some View {
        let state = student.state(of: lesson)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(width: 32, alignment: .leading)
                Text(lesson.title).ratioFont(.body).layoutPriority(1)
                DottedLeader()
                LessonStateLabel(state: state)
            }
            if peeking == lesson.id {
                TopicPeek(title: group.title, scores: student.topics[lesson.topicId])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture { navigator.pathwayPath.append(.overview(lesson.id)) }
        .onLongPressGesture(minimumDuration: 0.35) { togglePeek(lesson) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: peeking == lesson.id ? "Hide topic scores" : "Show topic scores") { togglePeek(lesson) }
    }

    private func togglePeek(_ lesson: Lesson) {
        withAnimation(.easeInOut(duration: 0.2)) {
            peeking = peeking == lesson.id ? nil : lesson.id
        }
    }

    /// Lessons for a module still being written, from the spine: visible, locked, no scores.
    private var planned: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In preparation. These are the lessons planned for \(module.title); they open as each one is reviewed.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
                .padding(.bottom, 12)
            ForEach(Spine.lessons(in: module)) { lesson in
                Divider().overlay(Color.ratioRule)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(lesson.number)").ratioFont(.monoData).frame(width: 32, alignment: .leading)
                    Text(lesson.title).ratioFont(.body)
                    Spacer(minLength: 8)
                    Image(systemName: "lock").imageScale(.small).accessibilityLabel("Locked")
                }
                .foregroundStyle(Color.ratioInk2)
                .padding(.vertical, 14)
            }
        }
    }

    private static func numeral(_ n: Int) -> String {
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return numerals.indices.contains(n - 1) ? numerals[n - 1] : "\(n)"
    }
}

private struct ModuleCard: View {
    let module: Module
    let mastery: Int?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RatioSpotArt.for(module).view
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            Spacer(minLength: 0)
            Text(module.title).ratioFont(.h3)
            if let mastery {
                Text("\(mastery)%").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            } else {
                Text("In preparation").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(16)
        .frame(width: 150, height: 200, alignment: .leading)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? Color.ratioInk : Color.ratioRule, lineWidth: isSelected ? 2 : 1)
        }
        .foregroundStyle(Color.ratioInk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.title), \(mastery.map { "\($0)% secure" } ?? "in preparation")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Status word plus icon, never colour alone.
struct LessonStateLabel: View {
    let state: LessonState

    var body: some View {
        Label(title, systemImage: icon)
            .ratioFont(.monoLabel)
            .foregroundStyle(color)
            .fixedSize()
    }

    private var title: String {
        switch state {
        case .notStarted: "Not started"
        case .inProgress: "In progress"
        case .secure: "Secure"
        case .needsReview: "Review"
        }
    }

    private var icon: String {
        switch state {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .secure: "checkmark"
        case .needsReview: "arrow.counterclockwise"
        }
    }

    private var color: Color {
        switch state {
        case .notStarted: .ratioInk2
        case .inProgress: .ratioInk
        case .secure: .ratioVerdigris
        case .needsReview: .ratioOxblood
        }
    }
}

private struct DottedLeader: View {
    var body: some View {
        Line()
            .stroke(Color.ratioInk2.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .frame(minWidth: 12, maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// "PEEK · TOPIC SCORES · MENS REA" with K/U/A tracks.
private struct TopicPeek: View {
    let title: String
    let scores: TopicScores?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peek · Topic scores · \(title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if let scores, Skill.allCases.contains(where: { scores[$0] != nil }) {
                ForEach(Skill.allCases) { skill in
                    SkillRow(title: String(skill.title.prefix(1)), estimate: scores[skill], compact: true)
                }
            } else {
                Text("Not assessed yet. Take this lesson's tests to see scores here.").ratioFont(.small)
            }
        }
        .padding(16)
        .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
