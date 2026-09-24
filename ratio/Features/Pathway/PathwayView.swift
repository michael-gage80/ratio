import SwiftUI

/// screens/25-pathway.png — the Lessons tab: every module as a map of its lessons,
/// grouped by topic, with the student's state on every lesson. The student's own modules
/// come first; the rest follow, dimmed, to add. Tap a lesson to open it; press and hold
/// to peek at its topic scores. The Library sits at the top.
struct PathwayView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Module?
    @State private var peeking: String?

    private var mine: [Module] { student.profile.modules ?? [] }
    /// The student's modules, then every other module.
    private var modules: [Module] { mine + Module.allCases.filter { !mine.contains($0) } }
    private var module: Module { selected ?? modules.first ?? .crime }

    var body: some View {
        let lessons = content.lessons(in: module)
        let groups = TopicGroup.groups(of: lessons)
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                RatioPageHeader(eyebrow: [student.profile.year.map { "Year \($0)" }, "Your modules first"].compactMap { $0 }.joined(separator: " · "),
                                title: "Lessons")
                    .padding(.horizontal, RatioSpace.m)

                libraryLink.padding(.horizontal, RatioSpace.m)

                moduleCards

                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    contentsHeader(lessons: lessons, topics: groups.count)
                    if lessons.isEmpty {
                        planned
                    } else {
                        Text("Press and hold a lesson to see its topic scores")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            groupSection(group, index: index)
                        }
                        if let date = lessons.first?.lawStatedDate {
                            Text("Law stated as at \(date)")
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, RatioSpace.m)
            }
            .padding(.top, RatioSpace.s)
            .padding(.bottom, RatioSpace.xl)
        }
        .ratioPage()
        .ratioFeedback(.impact(weight: .light), trigger: peeking) { _, new in new != nil }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Modules

    private var moduleCards: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: RatioSpace.s) {
                ForEach(modules) { module in
                    let isMine = mine.contains(module)
                    Button {
                        withAnimation(RatioMotion.tap) {
                            selected = module
                            peeking = nil
                        }
                    } label: {
                        ModuleCard(module: module, mastery: student.mastery(of: content.lessons(in: module)), isSelected: module == self.module,
                                   plan: student.isPlus || !isMine ? nil : (student.canStudy(module) ? "Free" : "Ratio Plus"),
                                   isMine: isMine)
                    }
                    .buttonStyle(.ratioPress)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, RatioSpace.m, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private func contentsHeader(lessons: [Lesson], topics: Int) -> some View {
        let count = lessons.isEmpty ? Spine.lessons(in: module).count : lessons.count
        let title = Text("\(module.title) \(Text("contents").italic().foregroundStyle(Color.ratioInk2))").ratioFont(.h2)
        let summary = Text(lessons.isEmpty ? "\(count) lessons planned" : "\(topics) topics · \(count) lessons")
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
        return VStack(alignment: .leading, spacing: RatioSpace.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: RatioSpace.xs)
                    summary
                }
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    title
                    summary
                }
            }
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            if !mine.contains(module) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        notMine
                        Spacer(minLength: RatioSpace.xs)
                        addButton
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        notMine
                        addButton
                    }
                }
            }
        }
    }

    private var notMine: some View {
        Text("Not one of your modules.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
    }

    private var addButton: some View {
        RatioButton("Add to my modules", style: .link) { add(module) }
    }

    private func add(_ module: Module) {
        Task { try? await UserRepository().update(uid: student.uid, ["modules": (mine + [module]).map(\.rawValue)]) }
    }

    private var libraryLink: some View {
        Button { navigator.pathwayPath.append(.library) } label: {
            HStack(spacing: RatioSpace.s) {
                Image(systemName: "books.vertical")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text("Library").ratioFont(.h3)
                    Text("Cases, legislation and doctrine maps").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: RatioSpace.xs)
                Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            }
            .ratioCard(padding: RatioSpace.s)
        }
        .buttonStyle(.ratioPress)
        .accessibilityElement(children: .combine)
    }

    // MARK: Lessons

    private func groupSection(_ group: TopicGroup, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                Text(Self.numeral(index + 1)).ratioFont(.h2).italic().foregroundStyle(Color.ratioOxblood).frame(minWidth: 40, alignment: .leading)
                Text(group.title).ratioFont(.h2).italic()
                Spacer(minLength: RatioSpace.xs)
                if !typeSize.isAccessibilitySize {
                    Text(group.lessons.count == 1 ? "1 lesson" : "\(group.lessons.count) lessons")
                        .ratioFont(.monoData)
                        .foregroundStyle(Color.ratioInk2)
                }
            }
            .padding(.vertical, RatioSpace.s)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(group.lessons.enumerated()), id: \.element.id) { lessonIndex, lesson in
                Divider().overlay(Color.ratioRule)
                lessonRow(lesson, number: "\(index + 1).\(lessonIndex + 1)", group: group)
            }
            Rectangle().fill(Color.ratioRule).frame(height: 1)
        }
    }

    private func lessonRow(_ lesson: Lesson, number: String, group: TopicGroup) -> some View {
        let canStudy = student.canStudy(lesson.moduleId)
        let state = student.state(of: lesson)
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            if typeSize.isAccessibilitySize {
                // Large text: the title gets the full width, the status goes under it.
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text(number).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                    Text(lesson.title).ratioFont(.body)
                    status(canStudy: canStudy, state: state)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                    Text(number).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(minWidth: 32, alignment: .leading)
                    Text(lesson.title).ratioFont(.body).layoutPriority(1)
                    DottedLeader()
                    status(canStudy: canStudy, state: state)
                }
            }
            if peeking == lesson.id {
                TopicPeek(title: group.title, scores: student.topics[lesson.topicId])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, RatioSpace.s)
        .contentShape(Rectangle())
        .onTapGesture {
            if canStudy {
                navigator.pathwayPath.append(.overview(lesson.id))
            } else {
                navigator.showPaywall(for: lesson.moduleId, freeModule: student.freeModule)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) { togglePeek(lesson) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: peeking == lesson.id ? "Hide topic scores" : "Show topic scores") { togglePeek(lesson) }
    }

    @ViewBuilder
    private func status(canStudy: Bool, state: LessonState) -> some View {
        if canStudy {
            LessonStateLabel(state: state)
        } else {
            Label("Plus", systemImage: "lock").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).fixedSize()
        }
    }

    private func togglePeek(_ lesson: Lesson) {
        withAnimation(RatioMotion.tap) {
            peeking = peeking == lesson.id ? nil : lesson.id
        }
    }

    /// Lessons for a module still being written, from the spine: visible, locked, no scores.
    private var planned: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In preparation. These are the lessons planned for \(module.title); each opens once it's been reviewed.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
                .padding(.bottom, RatioSpace.s)
            ForEach(Spine.lessons(in: module)) { lesson in
                Divider().overlay(Color.ratioRule)
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                    Text("\(lesson.number)").ratioFont(.monoData).frame(minWidth: 32, alignment: .leading)
                    Text(lesson.title).ratioFont(.body)
                    Spacer(minLength: RatioSpace.xs)
                    Image(systemName: "lock").imageScale(.small).accessibilityLabel("Locked")
                }
                .foregroundStyle(Color.ratioInk2)
                .padding(.vertical, RatioSpace.s)
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
    /// "Free" or "Ratio Plus" on the free plan (screen 25).
    var plan: String?
    /// Modules the student hasn't chosen are dimmed.
    var isMine = true

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            ModuleIllustration(module: module)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .padding(.vertical, RatioSpace.xs)
            Spacer(minLength: 0)
            Text(module.title).ratioFont(.h3).fixedSize(horizontal: false, vertical: true)
            if let mastery {
                // The plan tag drops under the percentage rather than squeezing it.
                ViewThatFits(in: .horizontal) {
                    HStack {
                        percent(mastery)
                        Spacer(minLength: RatioSpace.xxs)
                        planTag
                    }
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        percent(mastery)
                        planTag
                    }
                }
            } else {
                Text("In preparation").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(RatioSpace.s)
        // Grows with the text instead of clipping it.
        .frame(width: typeSize.isAccessibilitySize ? 240 : 160, alignment: .leading)
        .frame(minHeight: 208, alignment: .top)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous)
                .strokeBorder(isSelected ? Color.ratioInk : Color.ratioRule, lineWidth: isSelected ? 2 : 1)
        }
        .foregroundStyle(Color.ratioInk)
        .opacity(isMine ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.title), \(isMine ? mastery.map { "\($0)% secure" } ?? "in preparation" : "not one of your modules")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func percent(_ mastery: Int) -> some View {
        Text("\(mastery)%").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
    }

    @ViewBuilder private var planTag: some View {
        if let plan { RatioTag(plan, icon: plan == "Free" ? nil : "lock") }
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
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Peek · Topic scores · \(title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if let scores, Skill.allCases.contains(where: { scores[$0] != nil }) {
                ForEach(Skill.allCases) { skill in
                    SkillRow(title: String(skill.title.prefix(1)), estimate: scores[skill], compact: true)
                }
            } else {
                Text("Not assessed yet. Take this lesson's tests to see scores here.").ratioFont(.small)
            }
        }
        .ratioPanel()
    }
}
