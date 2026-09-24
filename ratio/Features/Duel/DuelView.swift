import SwiftUI

/// screens/31-duel.png — the Duel tab: rating per module (or mixed), ranked play against
/// other students, friend lobbies, async challenges waiting for you, sparring, the
/// tutorial, and recent matches.
struct DuelView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @AppStorage("duel.tutorialSeen") private var tutorialSeen = false
    /// 0 for standard time, or 30 for extra time (Settings → Accessibility).
    @AppStorage("duel.extendedSeconds") private var extendedSeconds = 0
    @State private var selected: DuelScope = .mixed
    @State private var showsMatchmaking = false
    @State private var choosingLevel = false
    @State private var lobbyEntry: LobbyEntry?
    @State private var cover: Cover?
    @State private var notice: String?
    /// A challenge swiped away: declined once the undo window passes.
    @State private var declining: (id: String, task: Task<Void, Never>)?

    /// Everything that takes over the screen.
    private enum Cover: Identifiable {
        case sparring(DuelScope, level: Int, tutorial: Bool)
        case live(String)
        case lobby(String)
        case challenge(ChallengeSummary)

        var id: String {
            switch self {
            case .sparring(let scope, let level, let tutorial): "sparring-\(scope.id)-\(level)-\(tutorial)"
            case .live(let id): "live-\(id)"
            case .lobby(let code): "lobby-\(code)"
            case .challenge(let challenge): "challenge-\(challenge.id)"
            }
        }
    }

    private struct LobbyEntry: Identifiable {
        let id = UUID()
        let code: String?
    }

    /// Modules with lessons to draw duel questions from.
    private var modules: [Module] {
        (student.profile.modules ?? Module.allCases).filter { !content.lessons(in: $0).isEmpty }
    }

    /// Mixed first, then each module.
    private var scopes: [DuelScope] { modules.isEmpty ? [] : [.mixed] + modules.map { .module($0) } }
    private var scope: DuelScope? { scopes.contains(selected) ? selected : scopes.first }
    private var seconds: Int { DuelTime.seconds(extended: extendedSeconds) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let scope {
                    scopeChips(selected: scope)
                    ratingCard(scope)
                    waitingForYou
                    VStack(spacing: 12) {
                        row(icon: "number", title: "Friend lobby", detail: "Play with a code") { lobbyEntry = LobbyEntry(code: nil) }
                        row(mark: true, title: "Sparring partner", detail: "Practise against a labelled bot, 5 levels") { startSparring() }
                        row(icon: "questionmark", title: "How duels work", detail: "Replay the tutorial") { play(scope, level: 1, tutorial: true) }
                    }
                    recentMatches
                    if !student.isPlus {
                        let left = max(0, 3 - student.duelsToday)
                        VStack(spacing: 8) {
                            Text("\(left) free \(left == 1 ? "duel" : "duels") left today").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Button("Go unlimited →") { navigator.paywall = "Duels are unlimited with Ratio Plus." }
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioOxblood)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                } else {
                    Text("Duels draw on your modules' lessons, which are still in preparation.")
                        .ratioFont(.body)
                        .foregroundStyle(Color.ratioInk2)
                }
            }
            .padding(24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsMatchmaking) {
            if let scope {
                MatchmakingView(scope: scope, seconds: seconds) { matchId in
                    showsMatchmaking = false
                    cover = .live(matchId)
                } spar: {
                    choosingLevel = true
                }
            }
        }
        .sheet(isPresented: $choosingLevel) {
            if let scope {
                LevelPicker(scope: scope, rating: student.ratings[scope]?.rating) { level in
                    choosingLevel = false
                    play(scope, level: level, tutorial: false)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $lobbyEntry) { entry in
            LobbyEntryView(scope: scope ?? .mixed, seconds: seconds, initialCode: entry.code) { code in
                lobbyEntry = nil
                cover = .lobby(code)
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $cover) { cover in
            switch cover {
            case .sparring(let scope, let level, let tutorial):
                DuelMatchView(scope: scope, level: level, seconds: seconds, isTutorial: tutorial)
            case .live(let matchId):
                LiveMatchView(matchId: matchId)
            case .lobby(let code):
                LobbyView(code: code)
            case .challenge(let challenge):
                ChallengeView(challenge: challenge)
            }
        }
        .onChange(of: navigator.showsDuelTutorial, initial: true) { _, shows in
            guard shows, let scope else { return }
            navigator.showsDuelTutorial = false
            play(scope, level: 1, tutorial: true)
        }
        .onChange(of: navigator.lobbyCode, initial: true) { _, code in
            guard let code else { return }
            navigator.lobbyCode = nil
            lobbyEntry = LobbyEntry(code: code)
        }
        .alert("Challenge", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: Async challenges

    /// Open challenges, minus one being declined, then the student's own challenges turned
    /// down in the last day.
    private var shownChallenges: [ChallengeSummary] {
        let open = student.challenges.filter { $0.id != declining?.id }
        let declined = student.challengeHistory.filter {
            $0.status == "declined" && $0.isFrom(student.uid) && ($0.declinedAt ?? .distantPast) > .now.addingTimeInterval(-86_400)
        }
        return open + declined
    }

    @ViewBuilder
    private var waitingForYou: some View {
        if !shownChallenges.isEmpty || declining != nil {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Waiting for you").ratioFont(.h2)
                    Spacer()
                    let toPlay = student.challenges.count { $0.done[student.uid] != true && $0.id != declining?.id }
                    if toPlay > 0 {
                        Text("\(toPlay) \(toPlay == 1 ? "challenge" : "challenges")").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(shownChallenges.enumerated()), id: \.element.id) { index, challenge in
                        if index > 0 { Divider().overlay(Color.ratioRule) }
                        if canDecline(challenge) {
                            SwipeToDecline { decline(challenge) } content: { challengeRow(challenge) }
                                .accessibilityAction(named: "Decline") { decline(challenge) }
                        } else {
                            challengeRow(challenge)
                        }
                    }
                    if declining != nil {
                        if !shownChallenges.isEmpty { Divider().overlay(Color.ratioRule) }
                        HStack {
                            Text("Challenge declined").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                            Spacer()
                            Button("Undo") { undoDecline() }.ratioFont(.h3).foregroundStyle(Color.ratioOxblood).frame(minHeight: 44)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .clipped()
                .padding(.horizontal, 18)
                .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
            }
        }
    }

    /// Only a challenge sent to the student, before they've started it.
    private func canDecline(_ challenge: ChallengeSummary) -> Bool {
        challenge.status == "open" && !challenge.isFrom(student.uid) && challenge.done[student.uid] != true
    }

    /// Hides the challenge now and declines it after 5 s unless undone.
    private func decline(_ challenge: ChallengeSummary) {
        if let previous = declining { commitDecline(previous.id) }
        let id = challenge.id
        let task = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commitDecline(id)
        }
        withAnimation { declining = (id, task) }
        AccessibilityNotification.Announcement("Challenge declined. Undo available for 5 seconds.").post()
    }

    private func undoDecline() {
        declining?.task.cancel()
        withAnimation { declining = nil }
    }

    private func commitDecline(_ id: String) {
        declining?.task.cancel()
        if declining?.id == id { declining = nil }
        Task {
            do { try await DuelService.declineChallenge(id: id) } catch { notice = (error as NSError).localizedDescription }
        }
    }

    private func challengeRow(_ challenge: ChallengeSummary) -> some View {
        let opponent = challenge.opponent(of: student.uid)
        let declined = challenge.status == "declined"
        let myTurn = challenge.done[student.uid] != true && !declined
        let hours = max(1, Int(challenge.expiresAt.timeIntervalSinceNow / 3600))
        return HStack(spacing: 14) {
            ProfilePhoto(uid: opponent.uid, initial: String(opponent.name.prefix(1)), version: nil, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(opponent.name) · \(DuelScope.title(of: challenge.moduleId))").ratioFont(.h3)
                Text(declined ? "Declined" : myTurn
                     ? (challenge.isFrom(student.uid) ? "Your challenge · play your half" : (challenge.done[opponent.uid] == true ? "Played their half" : "Challenged you"))
                     : "Waiting for their half")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                if !declined {
                    Text("\(hours) h left").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
            }
            Spacer()
            if myTurn {
                Button { cover = .challenge(challenge) } label: {
                    Text("Play").ratioFont(.h3).foregroundStyle(Color.ratioOnInk).padding(.horizontal, 20).frame(minHeight: 44)
                        .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .background(Color.ratioPaper)
    }

    private func challenge(_ match: MatchSummary) {
        guard let opponent = match.opponent(of: student.uid), let scope = DuelScope(id: match.moduleId) else { return }
        Task {
            do {
                try await DuelService.createChallenge(opponent: opponent.uid, scope: scope, seconds: seconds)
                notice = "\(opponent.name) has 24 hours to play their half. It's under Waiting for you."
            } catch {
                notice = (error as NSError).localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Human duels · Ranked").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text("Duel\(Text(".").foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            }
            Spacer()
            ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 56)
        }
    }

    private func scopeChips(selected current: DuelScope) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(scopes) { option in
                    Button { selected = option } label: {
                        Text(option.title)
                            .ratioFont(.body)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .foregroundStyle(option == current ? Color.ratioOnInk : Color.ratioInk)
                            .background(option == current ? Color.ratioInk : Color.ratioPaper, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.ratioRule))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == current ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ratingCard(_ scope: DuelScope) -> some View {
        let rating = student.ratings[scope]
        return VStack(alignment: .leading, spacing: 16) {
            Text(scope == .mixed ? "Ranked · Mixed · questions from your modules" : "Ranked · \(scope.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your rating").ratioFont(.body)
                Text(Int((rating?.rating ?? 1200).rounded()).formatted())
                    .font(.custom("NewsreaderDisplay-Regular", size: 56, relativeTo: .largeTitle))
                Text(rating.map { "\($0.isSettled ? "Settled" : "Provisional") · \($0.duels) \($0.duels == 1 ? "duel" : "duels")" } ?? "Provisional · no duels yet")
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
            }
            Divider().overlay(Color.ratioRule)
            Text("First to 3 · \(seconds) s a question").ratioFont(.h3)
            RatioButton("Find an opponent →") {
                if tutorialSeen { showsMatchmaking = true } else { play(scope, level: 1, tutorial: true) }
            }
        }
        .padding(22)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    private func row(icon: String? = nil, mark: Bool = false, title: String, detail: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Group {
                    if mark {
                        SparringMark(size: 40)
                    } else {
                        Image(systemName: icon ?? "circle")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(width: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).ratioFont(.h3)
                    Text(detail).ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
            }
            .padding(16)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.ratioRule) }
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var recentMatches: some View {
        let finished = student.matches.filter { $0.status == "complete" && $0.result(for: student.uid) != nil }
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent matches").ratioFont(.h2)
                VStack(spacing: 0) {
                    ForEach(Array(finished.prefix(5).enumerated()), id: \.element.id) { index, match in
                        if index > 0 { Divider().overlay(Color.ratioRule) }
                        MatchRow(match: match, uid: student.uid)
                            .contextMenu {
                                if match.isBot == false, let opponent = match.opponent(of: student.uid) {
                                    Button("Challenge \(opponent.name) to a rematch", systemImage: "arrow.uturn.right") { challenge(match) }
                                }
                            }
                    }
                }
                .padding(.horizontal, 18)
                .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
            }
        }
    }

    private func startSparring() {
        if tutorialSeen { choosingLevel = true } else if let scope { play(scope, level: 1, tutorial: true) }
    }

    private func play(_ scope: DuelScope, level: Int, tutorial: Bool) {
        cover = .sparring(scope, level: level, tutorial: tutorial)
    }
}

/// "Won 3–1 · v Omar S. · Yesterday · Crime   +10" — sparring rows say they're practice.
struct MatchRow: View {
    let match: MatchSummary
    let uid: String

    var body: some View {
        if let result = match.result(for: uid) {
            let won = result.winner == 0
            let delta = result.ratingAfter - result.ratingBefore
            let sparring = match.isBot != false
            HStack(spacing: 14) {
                Image(systemName: won ? "checkmark" : result.winner == nil ? "equal" : "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(won ? Color.ratioVerdigris : Color.ratioInk2))
                    .foregroundStyle(won ? Color.ratioVerdigris : Color.ratioInk2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(won ? "Won" : result.winner == nil ? "Drew" : "Lost") \(result.score[0])–\(result.score[1]) · v \(sparring ? "Sparring partner" : match.opponent(of: uid)?.name ?? "Student")")
                        .ratioFont(.body)
                    Text(details(sparring: sparring))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                }
                Spacer()
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .ratioFont(.monoData)
                    .foregroundStyle(delta >= 0 ? Color.ratioVerdigris : Color.ratioInk2)
            }
            .padding(.vertical, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func details(sparring: Bool) -> String {
        let kind: String? = switch match.mode {
        case "lobby": "Friend lobby"
        case "challenge": "Challenge"
        case "ranked": "Ranked"
        default: nil
        }
        let parts: [String?] = sparring
            ? [match.createdAt?.formatted(.relative(presentation: .named)), DuelScope.title(of: match.moduleId), "Level \(match.partner?.level ?? 1)", "Practice · not on the boards"]
            : [match.createdAt?.formatted(.relative(presentation: .named)), DuelScope.title(of: match.moduleId), kind]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// screens/33-matchmaking.png — searches for a student within ±100 rating in this
/// module (or mixed) and time pool, widening evenly to ±500 at 60 s; from 60 s a
/// labelled sparring partner is offered too.
private struct MatchmakingView: View {
    let scope: DuelScope
    let seconds: Int
    let found: (String) -> Void
    let spar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @State private var started = Date.now
    @State private var window = 100
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button { cancel() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Cancel")
                Spacer()
                Text("Matching · \(scope.title) · Ranked").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            Text("\(Text("Fastest finger").italic().foregroundStyle(Color.ratioOxblood)) wins the point.").ratioFont(.display)
            HStack(spacing: 16) {
                ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 64)
                VStack(alignment: .leading) {
                    Text("You").ratioFont(.h2)
                    Text(student.profile.displayName ?? "").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Rating").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text(Int((student.ratings[scope]?.rating ?? 1200).rounded()).formatted()).ratioFont(.monoData)
                }
            }
            HStack {
                Rectangle().fill(Color.ratioRule).frame(height: 1)
                Text("v").ratioFont(.h2).italic().foregroundStyle(Color.ratioInk2)
                Rectangle().fill(Color.ratioRule).frame(height: 1)
            }
            TimelineView(.periodic(from: started, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(started))
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        ProgressView().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failed ? "Reconnecting…" : "Finding a fair match…").ratioFont(.h3)
                            Text("Searching within ±\(window) · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                        }
                    }
                    HStack(alignment: .top, spacing: 14) {
                        SparringMark(size: 36)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(elapsed < 60 ? "No one yet? After 60 s we'll offer a sparring partner, clearly labelled." : "No one's free right now. Spar with a labelled partner instead?")
                                .ratioFont(.body)
                            if elapsed >= 60 {
                                RatioButton("Spar instead →", style: .secondary) { cancel(then: spar) }
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            HStack(spacing: 0) {
                fact("Format", "First to 3")
                Divider()
                fact("Per question", "\(seconds) s")
                Divider()
                fact("Pool", seconds == DuelTime.standard ? "Standard" : "Extra time")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
            Spacer()
            RatioButton("Cancel", style: .tertiary) { cancel() }
        }
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .interactiveDismissDisabled()
        .task { await search() }
    }

    /// Polls the matchmaker every 3 seconds until paired or cancelled.
    private func search() async {
        while !Task.isCancelled {
            do {
                let result = try await DuelService.findMatch(scope: scope, seconds: seconds)
                failed = false
                if let matchId = result.matchId {
                    found(matchId)
                    return
                }
                window = result.window ?? window
            } catch {
                if PlanService.isFreeLimit(error) {
                    dismiss()
                    navigator.paywall = "That's today's three free duels. Ratio Plus makes them unlimited."
                    return
                }
                failed = true
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func cancel(then next: (() -> Void)? = nil) {
        Task { await DuelService.cancelMatchmaking() }
        dismiss()
        next?()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(value).ratioFont(.h3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Choose a sparring partner's level; the one nearest the student's rating is suggested.
private struct LevelPicker: View {
    let scope: DuelScope
    let rating: Double?
    let choose: (Int) -> Void

    private static let ratings = [1000.0, 1150, 1300, 1450, 1600]

    private var suggested: Int {
        let target = rating ?? 1150
        return (Self.ratings.enumerated().min { abs($0.element - target) < abs($1.element - target) }?.offset ?? 1) + 1
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(SparringLevel.all), id: \.self) { level in
                        Button { choose(level) } label: {
                            HStack(spacing: 14) {
                                Text("\(level)").ratioFont(.h2).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(SparringLevel.title(level)).ratioFont(.h3)
                                        if level == suggested { RatioTag("Suggested", style: .tint(.ratioVerdigris)) }
                                    }
                                    Text(SparringLevel.detail(level)).ratioFont(.small).foregroundStyle(Color.ratioInk2)
                                }
                                Spacer()
                                Text(Int(Self.ratings[level - 1]).formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundStyle(Color.ratioInk)
                    }
                } footer: {
                    Text("Sparring moves your \(scope.title) rating and your profile. Wins against a sparring partner never count on the boards.")
                        .ratioFont(.small)
                }
            }
            .navigationTitle("Sparring partner")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}

/// A row that slides left to reveal "Decline"; a long enough swipe declines outright.
private struct SwipeToDecline<Content: View>: View {
    let decline: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat = 0
    private let reveal: CGFloat = 96

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: decline) {
                Text("Decline").ratioFont(.h3).foregroundStyle(Color.ratioOnInk).frame(width: reveal).frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(Color.ratioOxblood)
            .opacity(offset < 0 ? 1 : 0)
            .accessibilityHidden(true)
            content
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, value.translation.width)
                        }
                        .onEnded { value in
                            withAnimation(.snappy) {
                                if value.translation.width < -reveal * 2 {
                                    offset = 0
                                    decline()
                                } else {
                                    offset = value.translation.width < -reveal / 2 ? -reveal : 0
                                }
                            }
                        }
                )
        }
    }
}
