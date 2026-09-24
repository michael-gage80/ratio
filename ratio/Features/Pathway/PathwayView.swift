import SwiftUI

/// screens/25-pathway.png — the Lessons tab: every module as a map of its lessons,
/// grouped by topic, with the student's state on every lesson. The student's own modules
/// come first; the rest follow, dimmed, to add. Tap a lesson to open it; press and hold
/// to peek at its topic scores. The Library sits at the top. On iPad (regular width) the
/// modules are a list beside the contents, and selecting a lesson shows its scores in an
/// inspector at the top of the contents (screens/iPad/4-pathway-me-settings/01).
struct PathwayView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width
    private var selected: Module? { navigator.lessonsModule }
    @State private var peeking: String?
    /// iPad: the lesson shown in the inspector.
    @State private var inspected: String?

    private var mine: [Module] { student.modules }
    /// The student's modules, then the rest of their programme's.
    private var modules: [Module] { mine + student.programme.modules.filter { !mine.contains($0) } }
    private var module: Module { selected ?? modules.first ?? .crime }

    private var header: some View {
        RatioPageHeader(eyebrow: [student.programme == .sqe1 ? "SQE1" : student.profile.year.map { "Year \($0)" }, "Your modules first"].compactMap { $0 }.joined(separator: " · "),
                        title: "Lessons")
    }

    var body: some View {
        let lessons = content.lessons(in: module)
        let groups = TopicGroup.groups(of: lessons)
        ScrollView {
            if width.isCompact {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    header.padding(.horizontal, RatioSpace.m)

                    libraryLink.padding(.horizontal, RatioSpace.m)

                    moduleCards

                    contents(lessons: lessons, groups: groups)
                        .padding(.horizontal, RatioSpace.m)
                }
                .padding(.top, RatioSpace.s)
                .padding(.bottom, RatioSpace.xl)
            } else {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    header
                    ColumnsLayout(fraction: 0.36, spacing: RatioSpace.l) {
                        VStack(alignment: .leading, spacing: RatioSpace.s) {
                            libraryLink
                            moduleList
                            Text("Select a module to open its contents. Select a lesson to see its topic scores.")
                                .ratioFont(.small)
                                .italic()
                                .foregroundStyle(Color.ratioInk2)
                        }
                        VStack(alignment: .leading, spacing: RatioSpace.m) {
                            if let lesson = inspectedLesson(in: lessons) {
                                LessonInspector(lesson: lesson, number: number(of: lesson, in: groups),
                                                groupTitle: TopicGroup.title(forGroup: TopicGroup.groupId(of: lesson.topicId))) {
                                    open(lesson)
                                }
                            }
                            contents(lessons: lessons, groups: groups)
                        }
                    }
                }
                .padding(.horizontal, RatioSpace.l)
                .padding(.top, RatioSpace.s)
                .padding(.bottom, RatioSpace.xl)
            }
        }
        .ratioPage()
        .ratioFeedback(.impact(weight: .light), trigger: peeking) { _, new in new != nil }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func contents(lessons: [Lesson], groups: [TopicGroup]) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            contentsHeader(lessons: lessons, topics: groups.count)
            if lessons.isEmpty {
                planned
            } else {
                if width.isCompact {
                    Text("Press and hold a lesson to see its topic scores")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                }
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
    }

    /// The inspected lesson if it's in this module; otherwise the one to carry on with.
    private func inspectedLesson(in lessons: [Lesson]) -> Lesson? {
        lessons.first { $0.id == inspected }
            ?? lessons.first { student.state(of: $0) == .inProgress }
            ?? lessons.first { student.state(of: $0) == .notStarted }
            ?? lessons.first
    }

    /// "2.2" — its topic group and place in it.
    private func number(of lesson: Lesson, in groups: [TopicGroup]) -> String {
        for (index, group) in groups.enumerated() {
            if let position = group.lessons.firstIndex(where: { $0.id == lesson.id }) { return "\(index + 1).\(position + 1)" }
        }
        return ""
    }

    private func open(_ lesson: Lesson) {
        if student.canStudy(lesson.moduleId) {
            navigator.pathwayPath.append(.overview(lesson.id))
        } else {
            navigator.showPaywall(for: lesson.moduleId, freeModule: student.freeModule)
        }
    }

    // MARK: Modules

    private func select(_ module: Module) {
        withAnimation(RatioMotion.tap) {
            navigator.lessonsModule = module
            // Keep the iPad sidebar's highlighted module in step.
            if case .module = navigator.tab { navigator.tab = .module(module) }
            peeking = nil
            inspected = nil
        }
    }

    /// iPad: the modules as a vertical list beside the contents.
    private var moduleList: some View {
        VStack(spacing: RatioSpace.s) {
            ForEach(modules) { module in
                let isMine = mine.contains(module)
                Button { select(module) } label: {
                    ModuleRow(module: module, mastery: student.mastery(of: content.lessons(in: module)), isSelected: module == self.module,
                              plan: student.isPlus || !isMine ? nil : (student.canStudy(module) ? "Free" : "Ratio Plus"),
                              isMine: isMine)
                }
                .buttonStyle(.ratioPress)
            }
        }
    }

    private var moduleCards: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: RatioSpace.s) {
                ForEach(modules) { module in
                    let isMine = mine.contains(module)
                    Button { select(module) } label: {
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
        let summary = Text(lessons.isEmpty ? (count == 0 ? "In preparation" : "\(count) lessons planned") : "\(topics) topics · \(count) lessons")
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
                    if !width.isCompact {
                        Button { open(lesson) } label: {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(inspected == lesson.id ? Color.ratioOxblood : Color.ratioInk2)
                                .frame(width: 44, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.ratioPress)
                        .accessibilityLabel("Open \(lesson.title)")
                    }
                }
            }
            if peeking == lesson.id {
                TopicPeek(title: group.title, scores: student.topics[lesson.topicId])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, RatioSpace.s)
        .padding(.horizontal, width.isCompact ? 0 : RatioSpace.xs)
        .background {
            if !width.isCompact && inspected == lesson.id {
                RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).fill(Color.ratioSunk)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // iPad: a tap shows it in the inspector; the arrow (or a second tap) opens it.
            if width.isCompact || inspected == lesson.id {
                open(lesson)
            } else {
                withAnimation(RatioMotion.tap) { inspected = lesson.id }
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) { if width.isCompact { togglePeek(lesson) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { open(lesson) }
        .accessibilityAction(named: peeking == lesson.id ? "Hide topic scores" : "Show topic scores") {
            if width.isCompact { togglePeek(lesson) } else { inspected = lesson.id }
        }
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
            Text(Spine.lessons(in: module).isEmpty
                 ? "In preparation. Lessons for \(module.title) open here as each one is written and reviewed."
                 : "In preparation. These are the lessons planned for \(module.title); each opens once it's been reviewed.")
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

/// iPad: a module in the vertical list — art, title, mastery and plan.
private struct ModuleRow: View {
    let module: Module
    let mastery: Int?
    let isSelected: Bool
    var plan: String?
    var isMine = true

    var body: some View {
        HStack(alignment: .top, spacing: RatioSpace.s) {
            ModuleIllustration(module: module)
                .frame(width: 48, height: 48)
                .padding(RatioSpace.xs)
                .background(Color.ratioParchment, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).strokeBorder(Color.ratioRule) }
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(module.title).ratioFont(.h3).multilineTextAlignment(.leading)
                    Spacer(minLength: RatioSpace.xs)
                    Text(mastery.map { "\($0)%" } ?? "").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                }
                if let mastery {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ratioRule)
                            Capsule().fill(Color.ratioInk).frame(width: proxy.size.width * Double(mastery) / 100)
                        }
                    }
                    .frame(height: 4)
                } else {
                    Text("In preparation").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                if let plan { RatioTag(plan, icon: plan == "Free" ? nil : "lock") }
            }
        }
        .padding(RatioSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
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
}

/// iPad: the selected lesson's state, its topic scores with bands, and a way in.
private struct LessonInspector: View {
    let lesson: Lesson
    let number: String
    let groupTitle: String
    let open: () -> Void

    @Environment(StudentStore.self) private var student

    var body: some View {
        let state = student.state(of: lesson)
        let scores = student.topics[lesson.topicId]
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Inspector · \(groupTitle)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer(minLength: RatioSpace.xs)
                LessonStateLabel(state: state)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: RatioSpace.s) {
                    title
                    Spacer(minLength: RatioSpace.xs)
                    button(state: state).frame(width: 180)
                }
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    title
                    button(state: state)
                }
            }
            Divider().overlay(Color.ratioRule)
            if let scores, Skill.allCases.contains(where: { scores[$0] != nil }) {
                ForEach(Skill.allCases) { skill in
                    SkillRow(title: skill.title, estimate: scores[skill], compact: true)
                }
                Text("The shaded band is our uncertainty. It narrows as you answer more.")
                    .ratioFont(.small)
                    .italic()
                    .foregroundStyle(Color.ratioInk2)
            } else {
                Text("Not assessed yet. Take this lesson's tests to see scores here.")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            KeyHint(keys: "⌘↩", label: "Open")
        }
        .ratioCard()
    }

    private var title: some View {
        Text("\(Text(number).foregroundStyle(Color.ratioInk2))  \(lesson.title)")
            .ratioFont(.h2)
    }

    private func button(state: LessonState) -> some View {
        let label = !student.canStudy(lesson.moduleId) ? "Ratio Plus" : state == .inProgress ? "Resume →" : state == .notStarted ? "Start →" : "Open →"
        return RatioButton(label, style: .secondary, action: open)
            .keyboardShortcut(.return, modifiers: .command)
    }
}
