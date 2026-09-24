import SwiftUI

/// screens/11-today.png — the greeting, today's brief, then colour-coded blocks for
/// duels, the week's streak, boards and the news (PRD: "Today screen and daily brief").
/// The student can reorder or hide the blocks after the brief. A three-stop tour runs
/// the first time.
struct TodayView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tour.today.seen") private var tourSeen = false
    @AppStorage("consent.asked") private var consentAsked = false
    @State private var tourStop: TourStop?
    @State private var askingConsent = false
    @State private var editingHome = false

    /// The blocks after the brief — the default layout while the tour runs, so every stop
    /// has something to point at.
    private var cards: [HomeCard] {
        tourStop == nil ? HomeCard.arranged(order: student.settings.homeOrder, hidden: student.settings.homeHidden) : HomeCard.allCases
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    header.padding(.bottom, RatioSpace.xs)
                    briefCard.tourAnchor(.brief)
                    ForEach(cards) { card in
                        switch card {
                        case .duel: duelCard.tourAnchor(.more)
                        case .streak: streakCard.tourAnchor(.streak)
                        case .boards: boardsCard
                        case .news: newsCard
                        }
                    }
                    Button { editingHome = true } label: {
                        Text("Edit home")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.ratioPress)
                }
                .padding(RatioSpace.m)
            }
            .onChange(of: tourStop) { _, stop in
                guard let stop else { return }
                withAnimation(RatioMotion.reveal) { scroll.scrollTo(stop, anchor: .center) }
            }
        }
        .ratioPage()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingHome) {
            EditHomeSheet(order: HomeCard.arranged(order: student.settings.homeOrder, hidden: nil),
                          hidden: Set((student.settings.homeHidden ?? []).compactMap(HomeCard.init(rawValue:)))) { order, hidden in
                Task {
                    try? await UserRepository().update(uid: student.uid, [
                        "settings.homeOrder": order.map(\.rawValue),
                        "settings.homeHidden": HomeCard.allCases.filter(hidden.contains).map(\.rawValue),
                    ])
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $askingConsent, onDismiss: { consentAsked = true }) {
            AnalyticsConsentSheet { share in
                consentAsked = true
                askingConsent = false
                Task { try? await UserRepository().update(uid: student.uid, ["consents.analytics": share]) }
            }
            .presentationDetents([.medium])
            .interactiveDismissDisabled()
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if let tourStop, let anchor = anchors[tourStop] {
                GeometryReader { proxy in
                    TourOverlay(stop: tourStop, target: proxy[anchor], size: proxy.size, next: advanceTour, skip: endTour)
                }
            }
        }
        .task {
            await student.ensureBrief()
            if !tourSeen { tourStop = .brief }
        }
        .onChange(of: tourSeen) { _, seen in
            if !seen { tourStop = .brief } // Replayed from Settings.
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await student.ensureBrief() } }
        }
    }

    // MARK: Header

    /// The greeting stands in for the page title; the bell and the student's photo sit
    /// on the eyebrow line, like the icons on every other page header.
    private var header: some View {
        // Once per render: the feed walks every challenge, item and story.
        let unread = student.hasUnreadNotifications(content: content)
        return VStack(alignment: .leading, spacing: RatioSpace.xs) {
            HStack(alignment: .center, spacing: RatioSpace.xxs) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Spacer(minLength: 0)
                Button { navigator.todayPath.append(.notifications) } label: {
                    Image(systemName: "bell")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            if unread {
                                Circle().fill(Color.ratioOxblood).frame(width: 8, height: 8).offset(x: -8, y: 8)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
                .accessibilityLabel(unread ? "Notifications, unread" : "Notifications")
                Button { navigator.tab = .me } label: {
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 48)
                }
                .buttonStyle(.ratioPress)
                .accessibilityLabel("Your profile")
            }
            Text("\(greeting),\n\(student.profile.displayName ?? "there")\(Text(".").foregroundStyle(Color.ratioOxblood))")
                .ratioFont(.display)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var greeting: String {
        switch UKDate.calendar.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Brief

    @ViewBuilder
    private var briefCard: some View {
        if let brief = student.brief {
            BriefCard(brief: brief) { navigator.todayPath.append(.brief) }
        } else if student.briefUnavailable {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text("Brief").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text("Your modules' lessons are still being written. Your brief starts as soon as the first one is ready.")
                    .ratioFont(.body)
            }
            .ratioCard()
        } else {
            // Shaped like the brief card, so nothing jumps when it arrives.
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                Text("Brief · 15 min").ratioFont(.monoLabel)
                Text("Today's brief is on its way").ratioFont(.h1)
                Text("Chosen from yesterday's answers and the reviews that have come due.").ratioFont(.body)
                RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).fill(Color.ratioSunk).frame(height: 56)
            }
            .ratioSkeleton()
            .ratioCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Building today's brief")
        }
    }

    // MARK: Blocks

    private var streakCard: some View {
        let streak = student.streak
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                HStack {
                    Text("This week")
                    if streak.previousWeeks > 0 { Spacer(); Text("Week \(streak.previousWeeks + 1)") }
                }
                .ratioFont(.monoLabel)
                .opacity(0.8)
                Text("\(streak.daysThisWeek) of \(student.streak.target) days").ratioFont(.h2)
            }
            HStack(spacing: RatioSpace.xxs) {
                ForEach(Array(streak.week.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: RatioSpace.xs) {
                        Capsule()
                            .fill(day.active ? Color.ratioOnInk : Color.clear)
                            .strokeBorder(Color.ratioOnInk.opacity(day.active ? 0 : 0.35))
                            .frame(height: 8)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .ratioFont(.monoLabel)
                            .opacity(index == streak.todayIndex ? 1 : 0.8)
                        // Today: a small dot under its letter.
                        Circle().fill(index == streak.todayIndex ? Color.ratioOnInk : Color.clear).frame(width: 4, height: 4)
                    }
                }
            }
            .accessibilityHidden(true)
            Text(streak.message).ratioFont(.small).italic().opacity(0.85)
        }
        .foregroundStyle(Color.ratioOnInk)
        .ratioCard(.ratioForest, bordered: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week: \(streak.daysThisWeek) of \(student.streak.target) days. \(streak.message)")
    }

    /// Dark ink (deep oxblood in dark mode), horizontal: who's online and the challenges waiting on the student.
    private var duelCard: some View {
        let yourGo = student.challenges.filter { $0.done[student.uid] != true }
        return Button { navigator.tab = .duel } label: {
            HStack(spacing: RatioSpace.s) {
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Duel").ratioFont(.monoLabel).opacity(0.8)
                    Text("Find an opponent").ratioFont(.h2).multilineTextAlignment(.leading)
                    if let online = student.online, online > 0 {
                        // A live marker in the block's own colour: green is kept for "correct".
                        Label {
                            Text("\(online.formatted()) online")
                        } icon: {
                            Circle().fill(Color.ratioOnInk).frame(width: 8, height: 8)
                        }
                        .ratioFont(.monoLabel)
                    }
                }
                Spacer(minLength: RatioSpace.xs)
                if !yourGo.isEmpty {
                    VStack(alignment: .trailing, spacing: RatioSpace.xs) {
                        HStack(spacing: -12) {
                            ForEach(yourGo.prefix(3)) { challenge in
                                let opponent = challenge.opponent(of: student.uid)
                                ProfilePhoto(uid: opponent.uid, initial: String(opponent.name.prefix(1)), version: nil, size: 36)
                                    .overlay(Circle().strokeBorder(Color.ratioDuelBlock, lineWidth: 2))
                            }
                        }
                        Text("Your go").ratioFont(.monoLabel)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(yourGo.count) \(yourGo.count == 1 ? "challenge" : "challenges"), your go")
                } else {
                    Image(systemName: "arrow.right").opacity(0.8)
                }
            }
            .foregroundStyle(Color.ratioOnInk)
            .ratioCard(.ratioDuelBlock, bordered: false)
        }
        .buttonStyle(.ratioPress)
    }

    private var boardsCard: some View {
        Button { navigator.tab = .boards } label: {
            WeeklyBoardSummary()
                .ratioCard(Color.ratioOchre.opacity(0.16))
        }
        .buttonStyle(.ratioPress)
    }

    /// The top story — or, on Sundays, the weekly quiz (PRD: "On Sundays it shows the weekly quiz instead").
    private var newsCard: some View {
        Button { navigator.todayPath.append(.news) } label: {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.bottom, RatioSpace.xs)
                let isSunday = UKDate.calendar.component(.weekday, from: .now) == 1
                if isSunday, let quiz = student.quiz {
                    Text("Sunday quiz · The week in law").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("\(quiz.questions.count) questions on this week's stories.").ratioFont(.h3)
                } else if let story = student.news.first(where: { $0.whyItMatters != nil }) ?? student.news.first {
                    HStack(alignment: .top) {
                        Text("The week in law · \(story.source) · \(story.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))")
                            .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Spacer(minLength: RatioSpace.xs)
                        Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
                    }
                    Text(story.title).ratioFont(.h3).multilineTextAlignment(.leading)
                    if let why = story.whyItMatters, let module = Module(rawValue: why.moduleId) {
                        RatioTag("Why it matters · \(module.title)", style: .tint(.ratioOxblood))
                    }
                } else {
                    Text("The week in law").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("Headlines from the courts, with why they matter for your modules.").ratioFont(.h3)
                }
            }
            .ratioCard(.ratioParchment)
        }
        .buttonStyle(.ratioPress)
    }

    // MARK: Tour

    private func advanceTour() {
        withAnimation(RatioMotion.tap) {
            tourStop = tourStop.flatMap { TourStop(rawValue: $0.rawValue + 1) }
        }
        if tourStop == nil { finishTour() }
    }

    private func endTour() {
        withAnimation(RatioMotion.tap) { tourStop = nil }
        finishTour()
    }

    /// After the tour, once: notifications (the system asks), then usage analytics —
    /// off unless the student opts in (PRD: "Analytics: opt-in").
    private func finishTour() {
        tourSeen = true
        if navigator.replayingTutorials {
            navigator.replayingTutorials = false
            navigator.tab = .duel
            navigator.showsDuelTutorial = true
            return
        }
        guard !consentAsked else { return }
        Task {
            await RatioNotifications.requestPermission()
            askingConsent = true
        }
    }
}

/// "This week's board · Everyone — 12th · 7 wins in human duels".
private struct WeeklyBoardSummary: View {
    @Environment(StudentStore.self) private var student
    @State private var entry: BoardEntry?
    @State private var rank: Int?

    var body: some View {
        HStack(spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                // Full ink at 80%: the muted grey falls below 4.5:1 on the ochre wash.
                Text("This week's board · Everyone").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk.opacity(0.8))
                if let entry, entry.wins > 0 {
                    Text("\(rank.map { "\($0.formatted(.number))\(Ordinal.suffix($0)) · " } ?? "")\(Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins") in human duels").italic())")
                        .ratioFont(.h3)
                } else {
                    Text("Win a human duel to get on this week's board.").ratioFont(.body).italic()
                }
            }
            Spacer(minLength: RatioSpace.xs)
            Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk.opacity(0.8))
        }
        .task(id: student.matches.count) {
            entry = await BoardService.entry(.weekly, uid: student.uid)
            if let entry, entry.wins > 0 { rank = await BoardService.rank(of: entry, period: .weekly, scope: .everyone) }
        }
    }
}

/// The brief card: title, topic, why it was chosen, the step tracker and Begin/Resume.
private struct BriefCard: View {
    let brief: DailyBrief
    let open: () -> Void

    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content

    var body: some View {
        let current = student.currentStep(of: brief, content: content)
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Brief · \(brief.minutes) min").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer(minLength: RatioSpace.xs)
                RatioTag(topicChip)
            }
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text(brief.title).ratioFont(.h1)
                Text(brief.reason).ratioFont(.body)
            }
            VStack(alignment: .trailing, spacing: RatioSpace.xs) {
                tracker(current: current)
                Text("\(current.map { $0 + 1 } ?? brief.steps.count) / \(brief.steps.count)")
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
            }
            if let current {
                let kind = brief.steps[current].kind.rawValue
                RatioButton(current == 0 && !anyDone ? "Begin — the \(kind) →" : "Resume — the \(kind) →", action: open)
            } else {
                Text("\(Text("Brief complete \(Image(systemName: "checkmark"))").foregroundStyle(Color.ratioVerdigris)) · a new one tomorrow")
                    .ratioFont(.h3)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            if let note = brief.tutorNote {
                Rectangle()
                    .stroke(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 1)
                HStack(alignment: .top, spacing: RatioSpace.s) {
                    Text("R\(Text(".").foregroundStyle(Color.ratioOxblood))")
                        .ratioFont(.h3)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Color.ratioRule))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text("From your tutor").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Text(note).ratioFont(.body)
                    }
                }
            }
        }
        .ratioCard()
    }

    private var anyDone: Bool { brief.steps.indices.contains { student.isDone(step: $0, of: brief, content: content) } }

    /// The area of law: "Crime".
    private var topicChip: String { Module(rawValue: brief.moduleId)?.title ?? brief.moduleId }

    /// "Read ✓ · Drill · Build · Review", done steps struck through, the current one
    /// underlined. One run of text, so it wraps at large sizes rather than shrinking.
    private func tracker(current: Int?) -> some View {
        let parts = brief.steps.indices.map { index -> Text in
            let done = student.isDone(step: index, of: brief, content: content)
            var step = Text(brief.steps[index].kind.title)
                .strikethrough(done, color: .ratioVerdigris)
                .underline(index == current, color: .ratioOxblood)
                .italic(index == current)
                .foregroundStyle(done ? Color.ratioInk2 : index == current ? Color.ratioOxblood : Color.ratioInk)
            if done { step = Text("\(step) \(Text(Image(systemName: "checkmark")).foregroundStyle(Color.ratioVerdigris))") }
            return index > 0 ? Text("\(Text("  ·  ").foregroundStyle(Color.ratioRule))\(step)") : step
        }
        return parts.reduce(Text("")) { Text("\($0)\($1)") }
        .ratioFont(.h3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(brief.steps.enumerated().map { index, step in
            "\(step.kind.title)\(student.isDone(step: index, of: brief, content: content) ? ", done" : index == current ? ", next" : "")"
        }.joined(separator: "; "))
    }
}

// MARK: - Tour

/// screens/10-today-tour.png — three coach marks, skippable and replayable from Settings.
enum TourStop: Int, CaseIterable {
    case brief, streak, more

    var title: String {
        switch self {
        case .brief: "One brief a day, built for you."
        case .streak: "Weeks, not days."
        case .more: "Duels, boards and the news."
        }
    }

    var detail: String {
        switch self {
        case .brief: "12 to 20 minutes. Rebuilt each night from yesterday's answers and the reviews that have come due."
        case .streak: "Aim for a few active days each week — four to start, or your own target in Settings. A missed day costs nothing; only the week counts."
        case .more: "Duel other students, see where you stand on this week's board, and catch up on the week in law — with a quiz on Sundays."
        }
    }
}

private struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourStop: Anchor<CGRect>], nextValue: () -> [TourStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func tourAnchor(_ stop: TourStop) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [stop: $0] }.id(stop)
    }
}

private struct TourOverlay: View {
    let stop: TourStop
    let target: CGRect
    let size: CGSize
    let next: () -> Void
    let skip: () -> Void

    var body: some View {
        let highlight = target.insetBy(dx: -8, dy: -8)
        let below = highlight.midY < size.height / 2
        ZStack(alignment: below ? .top : .bottom) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size).insetBy(dx: -200, dy: -200))
                path.addRoundedRect(in: highlight, cornerSize: CGSize(width: 32, height: 32), style: .continuous)
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .onTapGesture(perform: next)
            .accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.ratioPaper, lineWidth: 2)
                .frame(width: highlight.width, height: highlight.height)
                .position(x: highlight.midX, y: highlight.midY)
                .allowsHitTesting(false)
            card
                .padding(.horizontal, RatioSpace.m)
                .padding(below ? .top : .bottom, below ? min(highlight.maxY + RatioSpace.s, size.height - 240) : max(size.height - highlight.minY + RatioSpace.s, RatioSpace.s))
        }
        .frame(width: size.width, height: size.height, alignment: below ? .top : .bottom)
        .transition(.opacity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack {
                Text("\(stop.rawValue + 1) / \(TourStop.allCases.count) · Your \(stop == .brief ? "brief" : stop == .streak ? "week" : "day")")
                Spacer()
                Button("Skip", action: skip).frame(minHeight: 44)
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            Text(stop.title).ratioFont(.h2)
            Text(stop.detail).ratioFont(.body)
            HStack {
                Spacer()
                Button(action: next) {
                    Text(stop == .more ? "Done" : "Next →")
                        .ratioFont(.h3)
                        .foregroundStyle(Color.ratioParchment)
                        .padding(.horizontal, RatioSpace.m)
                        .frame(minHeight: 48)
                        .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                }
                .buttonStyle(.ratioPress)
            }
        }
        .ratioCard()
        .foregroundStyle(Color.ratioInk)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// The one-time analytics choice. Crash reports are always on (legitimate interest);
/// usage analytics only with consent, and can be changed in Settings.
private struct AnalyticsConsentSheet: View {
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Help improve Ratio?").ratioFont(.h1)
            Text("Share anonymous usage data — which screens and features you use, never your answers or scores — so we can see what's working. Crash reports are always on so we can fix problems.")
                .ratioFont(.body)
            Text("You can change this any time in Settings → Privacy.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            Spacer()
            RatioButton("Share usage data", style: .secondary) { decide(true) }
            RatioButton("No thanks", style: .tertiary) { decide(false) }
        }
        .padding(RatioSpace.m)
        .ratioPage()
    }
}
