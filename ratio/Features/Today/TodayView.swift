import SwiftUI

/// screens/11-today.png (and 12–14, glass and dark) — the greeting, today's brief, the
/// weekly streak, and cards for duels, boards and the news (PRD: "Today screen and
/// daily brief"). The layout is fixed. A three-stop tour runs the first time.
struct TodayView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tour.today.seen") private var tourSeen = false
    @State private var tourStop: TourStop?

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header.padding(.bottom, 12)
                    briefCard.tourAnchor(.brief)
                    HStack(alignment: .top, spacing: 16) {
                        streakCard.tourAnchor(.streak)
                        duelCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 16) {
                        boardsCard
                        newsCard
                    }
                    .tourAnchor(.more)
                    Text("Educational, not legal advice")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(24)
            }
            .background { TodayBackdrop() }
            .onChange(of: tourStop) { _, stop in
                guard let stop else { return }
                withAnimation(.easeInOut(duration: 0.3)) { scroll.scrollTo(stop, anchor: .center) }
            }
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar(.hidden, for: .navigationBar)
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
            .todayCard()
        }
    }

    // MARK: Smaller cards

    private var streakCard: some View {
        let streak = student.streak
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week")
                if streak.previousWeeks > 0 { Spacer(); Text("Week \(streak.previousWeeks + 1)") }
            }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            Text("\(streak.daysThisWeek) of \(Streak.target) days").ratioFont(.h2)
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
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .todayCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This week: \(streak.daysThisWeek) of \(Streak.target) days. \(streak.message)")
    }

    private var duelCard: some View {
        Button { navigator.tab = .duel } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Duel · Sparring").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text("Find an opponent").ratioFont(.h2)
                Text("Spar with a labelled partner while live duels are on their way.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .todayCard()
        }
        .buttonStyle(.plain)
    }

    private var boardsCard: some View {
        Button { navigator.tab = .boards } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This week's board · Soon").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("Your place appears after your first human duel.").ratioFont(.body).italic()
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
            }
            .padding(18)
            .todayCard()
        }
        .buttonStyle(.plain)
    }

    private var newsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The week in law · Soon").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("Headlines from the courts, with why they matter for your modules.").ratioFont(.h3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .todayCard()
    }

    // MARK: Tour

    private func advanceTour() {
        withAnimation(.easeInOut(duration: 0.25)) {
            tourStop = tourStop.flatMap { TourStop(rawValue: $0.rawValue + 1) }
        }
        if tourStop == nil { tourSeen = true }
    }

    private func endTour() {
        withAnimation(.easeInOut(duration: 0.25)) { tourStop = nil }
        tourSeen = true
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
                Button(action: open) {
                    Label("Brief complete", systemImage: "checkmark")
                        .ratioFont(.h3)
                        .foregroundStyle(Color.ratioVerdigris)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.ratioRule) }
                }
                .buttonStyle(.plain)
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
        .todayCard(cornerRadius: 28)
    }

    private var anyDone: Bool { brief.steps.indices.contains { student.isDone(step: $0, of: brief, content: content) } }

    /// "Crime · Mens rea"
    private var topicChip: String {
        let module = Module(rawValue: brief.moduleId)?.title ?? brief.moduleId
        return "\(module) · \(TopicGroup.title(forGroup: TopicGroup.groupId(of: brief.topicId)))"
    }

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
    /// Today's cards are Liquid Glass (screens 12 and 14), solid with Reduce Transparency.
    func todayCard(cornerRadius: CGFloat = 24) -> some View {
        ratioGlassCard(cornerRadius: cornerRadius)
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.ratioRule) }
    }
}

/// Faint engraved rings behind the cards, so the glass has something to refract (screen 12).
private struct TodayBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .stroke(Color.ratioOxblood.opacity(0.25), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.9)
                    .position(x: proxy.size.width * 0.95, y: 180)
                Circle()
                    .fill(Color.ratioOxblood.opacity(0.08))
                    .frame(width: proxy.size.width * 0.8)
                    .position(x: proxy.size.width * 0.05, y: 700)
                Circle()
                    .fill(Color.ratioInk.opacity(0.05))
                    .frame(width: proxy.size.width * 0.7)
                    .position(x: proxy.size.width, y: 480)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        case .streak: "The target is \(Streak.target) active days a week. A missed day costs nothing; only the week counts."
        case .more: "Spar against a labelled partner, see where you stand this week, and catch up on the law. Boards and news arrive in later builds."
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
