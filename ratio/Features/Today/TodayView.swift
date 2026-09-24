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
                VStack(alignment: .leading, spacing: 16) {
                    header.padding(.bottom, 12)
                    briefCard.tourAnchor(.brief)
                    ForEach(cards) { card in
                        switch card {
                        case .duel: duelCard.tourAnchor(.more)
                        case .streak: streakCard.tourAnchor(.streak)
                        case .boards: boardsCard
                        case .news: newsCard
                        }
                    }
                    Button("Edit home") { editingHome = true }
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(24)
            }
            .onChange(of: tourStop) { _, stop in
                guard let stop else { return }
                withAnimation(.easeInOut(duration: 0.3)) { scroll.scrollTo(stop, anchor: .center) }
            }
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("\(greeting),\n\(student.profile.displayName ?? "there").").ratioFont(.display)
            }
            Spacer()
            Button { navigator.todayPath.append(.notifications) } label: {
                Image(systemName: "bell")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .topTrailing) {
                        if student.hasUnreadNotifications(content: content) {
                            Circle().fill(Color.ratioOxblood).frame(width: 9, height: 9).offset(x: -8, y: 9)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(student.hasUnreadNotifications(content: content) ? "Notifications, unread" : "Notifications")
            Button { navigator.tab = .me } label: {
                ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 56)
            }
            .accessibilityLabel("Your profile")
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
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Brief").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                if student.briefUnavailable {
                    Text("Your modules' lessons are still in preparation. Your brief starts as soon as the first one is ready.")
                        .ratioFont(.body)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Building today's brief…").ratioFont(.body)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeBlock(Color.ratioPaper)
        }
    }

    // MARK: Blocks

    private var streakCard: some View {
        let streak = student.streak
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week")
                if streak.previousWeeks > 0 { Spacer(); Text("Week \(streak.previousWeeks + 1)") }
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            Text("\(streak.daysThisWeek) of \(student.streak.target) days").ratioFont(.h2)
            HStack(spacing: 5) {
                ForEach(Array(streak.week.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(day.active ? (index == streak.todayIndex ? Color.ratioOxblood : Color.ratioInk) : Color.ratioRule)
                            .frame(height: 8)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .ratioFont(.monoLabel)
                            .foregroundStyle(index == streak.todayIndex ? Color.ratioOxblood : Color.ratioInk2)
                    }
                }
            }
            .accessibilityHidden(true)
            Text(streak.message).ratioFont(.small).italic().foregroundStyle(Color.ratioInk2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeBlock(Color.ratioVWash)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week: \(streak.daysThisWeek) of \(student.streak.target) days. \(streak.message)")
    }

    /// Dark ink, horizontal: who's online and the challenges waiting on the student.
    private var duelCard: some View {
        let yourGo = student.challenges.filter { $0.done[student.uid] != true }
        return Button { navigator.tab = .duel } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duel").ratioFont(.monoLabel).opacity(0.7)
                    Text("Find an opponent").ratioFont(.h2)
                    if let online = student.online, online > 0 {
                        Label {
                            Text("\(online.formatted()) online")
                        } icon: {
                            Circle().fill(Color.ratioVerdigris).frame(width: 8, height: 8)
                        }
                        .ratioFont(.monoLabel)
                    }
                }
                Spacer(minLength: 8)
                if !yourGo.isEmpty {
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: -12) {
                            ForEach(yourGo.prefix(3)) { challenge in
                                let opponent = challenge.opponent(of: student.uid)
                                ProfilePhoto(uid: opponent.uid, initial: String(opponent.name.prefix(1)), version: nil, size: 36)
                                    .overlay(Circle().strokeBorder(Color.ratioInk, lineWidth: 2))
                            }
                        }
                        Text("Your go").ratioFont(.monoLabel)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(yourGo.count) \(yourGo.count == 1 ? "challenge" : "challenges"), your go")
                } else {
                    Image(systemName: "arrow.right").opacity(0.7)
                }
            }
            .padding(18)
            .foregroundStyle(Color.ratioOnInk)
            .homeBlock(Color.ratioInk, bordered: false)
        }
        .buttonStyle(.plain)
    }

    private var boardsCard: some View {
        Button { navigator.tab = .boards } label: {
            WeeklyBoardSummary()
                .padding(18)
                .homeBlock(Color.ratioOchre.opacity(0.16))
        }
        .buttonStyle(.plain)
    }

    /// The top story — or, on Sundays, the weekly quiz (PRD: "On Sundays it shows the weekly quiz instead").
    private var newsCard: some View {
        Button { navigator.todayPath.append(.news) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(Color.ratioInk).frame(height: 1).padding(.bottom, 4)
                let isSunday = UKDate.calendar.component(.weekday, from: .now) == 1
                if isSunday, let quiz = student.quiz {
                    Text("Sunday quiz · The week in law").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("\(quiz.questions.count) questions on this week's stories.").ratioFont(.h3)
                } else if let story = student.news.first(where: { $0.whyItMatters != nil }) ?? student.news.first {
                    HStack(alignment: .top) {
                        Text("The week in law · \(story.source) · \(story.publishedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))")
                            .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(Color.ratioInk2)
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
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeBlock(Color.ratioParchment)
        }
        .buttonStyle(.plain)
    }

    // MARK: Tour

    private func advanceTour() {
        withAnimation(.easeInOut(duration: 0.25)) {
            tourStop = tourStop.flatMap { TourStop(rawValue: $0.rawValue + 1) }
        }
        if tourStop == nil { finishTour() }
    }

    private func endTour() {
        withAnimation(.easeInOut(duration: 0.25)) { tourStop = nil }
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
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("This week's board · Everyone").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                if let entry, entry.wins > 0 {
                    Text("\(rank.map { "\($0.formatted(.number))\(Ordinal.suffix($0)) · " } ?? "")\(Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins") in human duels").italic())")
                        .ratioFont(.h3)
                } else {
                    Text("Win a human duel to get on this week's board.").ratioFont(.body).italic()
                }
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Brief · \(brief.minutes) min").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer(minLength: 8)
                RatioTag(topicChip)
            }
            Text(brief.title).ratioFont(.h1)
            Text(brief.reason).ratioFont(.body)
            VStack(alignment: .trailing, spacing: 6) {
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
                HStack(alignment: .top, spacing: 14) {
                    Text("R\(Text(".").foregroundStyle(Color.ratioOxblood))")
                        .ratioFont(.h3)
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.ratioRule))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From your tutor").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Text(note).ratioFont(.body)
                    }
                }
            }
        }
        .padding(24)
        .homeBlock(Color.ratioPaper, cornerRadius: 28)
    }

    private var anyDone: Bool { brief.steps.indices.contains { student.isDone(step: $0, of: brief, content: content) } }

    /// The area of law: "Crime".
    private var topicChip: String { Module(rawValue: brief.moduleId)?.title ?? brief.moduleId }

    /// "Read ✓ · Drill · Build · Review", done steps struck through, the current one underlined.
    private func tracker(current: Int?) -> some View {
        HStack(spacing: 10) {
            ForEach(brief.steps.indices, id: \.self) { index in
                if index > 0 { Text("·").foregroundStyle(Color.ratioRule) }
                let done = student.isDone(step: index, of: brief, content: content)
                HStack(spacing: 4) {
                    Text(brief.steps[index].kind.title)
                        .strikethrough(done, color: .ratioVerdigris)
                        .underline(index == current, color: .ratioOxblood)
                        .italic(index == current)
                        .foregroundStyle(done ? Color.ratioInk2 : index == current ? Color.ratioOxblood : Color.ratioInk)
                    if done { Image(systemName: "checkmark").imageScale(.small).foregroundStyle(Color.ratioVerdigris) }
                }
            }
        }
        .ratioFont(.h3)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(brief.steps.enumerated().map { index, step in
            "\(step.kind.title)\(student.isDone(step: index, of: brief, content: content) ? ", done" : index == current ? ", next" : "")"
        }.joined(separator: "; "))
    }
}

private extension View {
    /// A solid colour-coded block.
    func homeBlock(_ fill: Color, cornerRadius: CGFloat = 24, bordered: Bool = true) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                if bordered { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.ratioRule) }
            }
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
                .padding(.horizontal, 24)
                .padding(below ? .top : .bottom, below ? min(highlight.maxY + 16, size.height - 240) : max(size.height - highlight.minY + 16, 16))
        }
        .frame(width: size.width, height: size.height, alignment: below ? .top : .bottom)
        .transition(.opacity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(stop.rawValue + 1) / \(TourStop.allCases.count) · Your \(stop == .brief ? "brief" : stop == .streak ? "week" : "day")")
                Spacer()
                Button("Skip", action: skip)
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
                        .foregroundStyle(Color.ratioOnInk)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 48)
                        .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
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
        VStack(alignment: .leading, spacing: 18) {
            Text("Help improve Ratio?").ratioFont(.h1)
            Text("Share anonymous usage data — which screens and features you use, never your answers or scores — so we can see what's working. Crash reports are always on so we can fix problems.")
                .ratioFont(.body)
            Text("You can change this any time in Settings → Privacy.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            Spacer()
            RatioButton("Share usage data", style: .secondary) { decide(true) }
            RatioButton("No thanks", style: .tertiary) { decide(false) }
        }
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }
}
