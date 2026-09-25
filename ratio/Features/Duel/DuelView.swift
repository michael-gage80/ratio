import SwiftUI

/// screens/31-duel.png — the Duel tab: rating per module (or mixed), ranked play against
/// other students, friend lobbies, async challenges waiting for you, sparring, the
/// tutorial, and recent duels.
struct DuelView: View {
    @Environment(StudentStore.self) private var student
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width
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
        student.modules.filter { !content.lessons(in: $0).isEmpty }
    }

    /// Mixed first, then each module.
    private var scopes: [DuelScope] { modules.isEmpty ? [] : [.mixed] + modules.map { .module($0) } }
    private var scope: DuelScope? { scopes.contains(selected) ? selected : scopes.first }
    private var seconds: Int { DuelTime.seconds(extended: extendedSeconds) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                RatioPageHeader(eyebrow: "Human duels · Ranked", title: "Duel") {
                    // iPad: the free-duels line sits top right (screens/iPad/5-duel/01-duel.png).
                    if !width.isCompact && scope != nil && !student.isPlus { freeDuels(inline: true) }
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 56)
                        .accessibilityHidden(true)
                }
                if let scope {
                    if width.isCompact {
                        scopeChips(selected: scope)
                        ratingCard(scope)
                        waitingForYou
                        actionRows(scope)
                        recentDuels
                        if !student.isPlus { freeDuels(inline: false) }
                    } else {
                        // iPad: chips and rating on the left; challenges and ways to play on the right.
                        ColumnsLayout(fraction: 0.55, spacing: RatioSpace.m) {
                            VStack(alignment: .leading, spacing: RatioSpace.m) {
                                scopeChips(selected: scope)
                                ratingCard(scope)
                            }
                            VStack(alignment: .leading, spacing: RatioSpace.m) {
                                waitingForYou
                                actionRows(scope)
                            }
                        }
                        recentDuels
                    }
                } else {
                    RatioEmptyState(art: .scales, message: "Duels draw on your modules' lessons, which are still in preparation.")
                }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.bottom, RatioSpace.xl)
        }
        .ratioPage()
        .toolbar(.hidden, for: .navigationBar)
        // A sheet on iPhone; the whole screen on iPad (screens/iPad/5-duel/03-matchmaking.png).
        .sheet(isPresented: Binding(get: { showsMatchmaking && width.isCompact }, set: { showsMatchmaking = $0 })) { matchmaking }
        .fullScreenCover(isPresented: Binding(get: { showsMatchmaking && !width.isCompact }, set: { showsMatchmaking = $0 })) { matchmaking }
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

    @ViewBuilder
    private var matchmaking: some View {
        if let scope {
            MatchmakingView(scope: scope, seconds: seconds) { matchId in
                showsMatchmaking = false
                cover = .live(matchId)
            } spar: {
                choosingLevel = true
            }
            .ratioMeasuresWidth()
        }
    }

    private func actionRows(_ scope: DuelScope) -> some View {
        VStack(spacing: RatioSpace.s) {
            row(icon: "number", title: "Friend lobby", detail: "Play with a code") { lobbyEntry = LobbyEntry(code: nil) }
            row(mark: true, title: "Sparring partner", detail: "Practise against a labelled bot, 5 levels") { startSparring() }
            row(icon: "questionmark", title: "How duels work", detail: "Replay the tutorial") { play(scope, level: 1, tutorial: true) }
        }
    }

    /// "3 free duels left today · Go unlimited →" — under the page on iPhone, top right on iPad.
    private func freeDuels(inline: Bool) -> some View {
        let left = max(0, 3 - student.duelsToday)
        let layout = inline ? AnyLayout(HStackLayout(spacing: RatioSpace.xs)) : AnyLayout(VStackLayout(spacing: RatioSpace.xs))
        return layout {
            Text("\(left) free \(left == 1 ? "duel" : "duels") left today").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Button("Go unlimited →") { navigator.paywall = "Duels are unlimited with Ratio Plus." }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioOxblood)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: inline ? nil : .infinity)
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
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Waiting for you").ratioFont(.h2).accessibilityAddTraits(.isHeader)
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
                        .padding(.vertical, RatioSpace.xs)
                        .padding(.horizontal, RatioSpace.m)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous))
                .ratioCard(padding: 0)
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
        withAnimation(RatioMotion.tap) { declining = (id, task) }
        AccessibilityNotification.Announcement("Challenge declined. Undo available for 5 seconds.").post()
    }

    private func undoDecline() {
        declining?.task.cancel()
        withAnimation(RatioMotion.tap) { declining = nil }
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
        let status = declined ? "Declined" : myTurn
            ? (challenge.isFrom(student.uid) ? "Your challenge · play your half" : (challenge.done[opponent.uid] == true ? "Played their half" : "Challenged you"))
            : "Waiting for their half"
        // At accessibility sizes the Play button goes under the details.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RatioSpace.s))
            : AnyLayout(HStackLayout(spacing: RatioSpace.s))
        return layout {
            ProfilePhoto(uid: opponent.uid, initial: String(opponent.name.prefix(1)), version: nil, size: 48)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text(opponent.name).ratioFont(.h3)
                Text("\(DuelScope.title(of: challenge.moduleId)) · \(status)")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
                if !declined {
                    Text("\(hours)\u{00A0}h left").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
            }
            .layoutPriority(1)
            if !typeSize.isAccessibilitySize { Spacer(minLength: RatioSpace.xs) }
            if myTurn {
                // Ink with parchment text: flips correctly in dark mode.
                Button { cover = .challenge(challenge) } label: {
                    Text("Play").ratioFont(.h3).fixedSize().foregroundStyle(Color.ratioParchment).padding(.horizontal, RatioSpace.s).frame(minHeight: 44)
                        .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                }
                .buttonStyle(.ratioPress)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RatioSpace.s)
        .padding(.horizontal, RatioSpace.s)
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

    private func scopeChips(selected current: DuelScope) -> some View {
        // Chips wrap onto more lines, as in the mockup, rather than scrolling sideways.
        ChipFlow(spacing: RatioSpace.xs) {
            ForEach(scopes) { option in
                Button { withAnimation(RatioMotion.tap) { selected = option } } label: {
                    Text(option.title)
                        .ratioFont(.body)
                        .padding(.horizontal, RatioSpace.s)
                        .frame(minHeight: 44)
                        .foregroundStyle(option == current ? Color.ratioParchment : Color.ratioInk)
                        .background(option == current ? Color.ratioInk : Color.ratioPaper, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.ratioRule))
                }
                .buttonStyle(.ratioPress)
                .accessibilityAddTraits(option == current ? .isSelected : [])
            }
        }
    }

    private func ratingCard(_ scope: DuelScope) -> some View {
        let rating = student.ratings[scope]
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text(scope == .mixed ? "Ranked · Mixed · questions from your modules" : "Ranked · \(scope.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text("Your rating").ratioFont(.body)
                Text(Int((rating?.rating ?? 1200).rounded()).formatted())
                    .ratioFont(.figure)
                Text(rating.map { "\($0.isSettled ? "Settled" : "Provisional") · \($0.duels) \($0.duels == 1 ? "duel" : "duels")" } ?? "Provisional · no duels yet")
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
            }
            Divider().overlay(Color.ratioRule)
            Text("First to 3 · \(seconds)\u{00A0}s a question").ratioFont(.h3)
            HStack(spacing: RatioSpace.s) {
                RatioButton("Find an opponent →") {
                    if tutorialSeen { showsMatchmaking = true } else { play(scope, level: 1, tutorial: true) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                KeyHint(keys: "⌘↩", label: "Find")
            }
        }
        .ratioCard()
    }

    private func row(icon: String? = nil, mark: Bool = false, title: String, detail: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: RatioSpace.s) {
                Group {
                    if mark {
                        SparringMark(size: 40)
                    } else {
                        Image(systemName: icon ?? "circle")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
                    }
                }
                .frame(width: 48)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(title).ratioFont(.h3)
                    Text(detail).ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: RatioSpace.xs)
                Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            }
            .ratioCard(padding: RatioSpace.s)
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.ratioPress)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var recentDuels: some View {
        let finished = student.matches.filter { $0.status == "complete" && $0.result(for: student.uid) != nil }
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                Text("Recent duels").ratioFont(.h2).accessibilityAddTraits(.isHeader)
                if width.isCompact {
                    VStack(spacing: 0) {
                        ForEach(Array(finished.prefix(5).enumerated()), id: \.element.id) { index, match in
                            if index > 0 { Divider().overlay(Color.ratioRule) }
                            matchRow(match, inset: RatioSpace.m)
                        }
                    }
                    .ratioCard(padding: 0)
                } else {
                    // iPad: a row of cards, three across.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: RatioSpace.s, alignment: .top)], spacing: RatioSpace.s) {
                        ForEach(finished.prefix(6)) { match in
                            matchRow(match, inset: RatioSpace.s)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .ratioCard(padding: 0)
                        }
                    }
                }
            }
        }
    }

    private func matchRow(_ match: MatchSummary, inset: CGFloat) -> some View {
        MatchRow(match: match, uid: student.uid, inset: inset)
            .contextMenu {
                if match.isBot == false, let opponent = match.opponent(of: student.uid) {
                    Button("Challenge \(opponent.name) to a rematch", systemImage: "arrow.uturn.right") { challenge(match) }
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
    /// Horizontal inset, so the row can sit inside a card or on a page.
    var inset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let result = match.result(for: uid) {
            let won = result.winner == 0
            let delta = result.ratingAfter - result.ratingBefore
            let sparring = match.isBot != false
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RatioSpace.xs))
                : AnyLayout(HStackLayout(spacing: RatioSpace.s))
            layout {
                Image(systemName: won ? "checkmark" : result.winner == nil ? "equal" : "minus")
                    .font(.footnote)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(won ? Color.ratioVerdigris : Color.ratioInk2))
                    .foregroundStyle(won ? Color.ratioVerdigris : Color.ratioInk2)
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text("\(won ? "Won" : result.winner == nil ? "Drew" : "Lost") \(result.score[0])–\(result.score[1]) · v \(sparring ? "Sparring partner" : match.opponent(of: uid)?.name ?? "Student")")
                        .ratioFont(.body)
                    Text(details(sparring: sparring))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: RatioSpace.xs) }
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .ratioFont(.monoData)
                    .foregroundStyle(delta >= 0 ? Color.ratioVerdigris : Color.ratioInk2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, RatioSpace.s)
            .padding(.horizontal, inset)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RatioIconButton(systemImage: "xmark", label: "Cancel") { cancel() }
                Spacer()
                Text("Matching · \(scope.title) · Ranked").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            .padding(.horizontal, RatioSpace.s)
            .padding(.top, RatioSpace.xs)
            ScrollView {
                Group {
                    if width.isCompact { content } else { wideContent }
                }
                .padding(.horizontal, RatioSpace.m)
                .padding(.vertical, RatioSpace.s)
            }
            VStack(spacing: RatioSpace.xs) {
                RatioButton("Cancel", style: .tertiary) { cancel() }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: width.isCompact ? .infinity : 500)
                KeyHint(keys: "esc", label: "Cancel")
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.bottom, RatioSpace.s)
        }
        .ratioPage()
        .interactiveDismissDisabled()
        .task { await search() }
    }

    private var headline: some View {
        Text("\(Text("Fastest finger").italic().foregroundStyle(Color.ratioOxblood)) wins the point.").ratioFont(.display)
    }

    /// iPad: you, the "v" ring and the search side by side; the facts and the sparring
    /// offer beneath.
    private var wideContent: some View {
        VStack(spacing: RatioSpace.l) {
            headline.multilineTextAlignment(.center)
            HStack(alignment: .center, spacing: RatioSpace.m) {
                VStack(spacing: RatioSpace.xs) {
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 96)
                    Text("You").ratioFont(.h2)
                    Text(student.profile.displayName ?? "").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                    Text("Rating \(Int((student.ratings[scope]?.rating ?? 1200).rounded()).formatted())").ratioFont(.monoData)
                }
                .frame(maxWidth: .infinity)
                .ratioCard()
                .accessibilityElement(children: .combine)
                ZStack {
                    RatioRings(diameter: 120)
                    Text("v").ratioFont(.display).italic().foregroundStyle(Color.ratioInk2)
                }
                .accessibilityHidden(true)
                TimelineView(.periodic(from: started, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(started))
                    VStack(spacing: RatioSpace.xs) {
                        Image(systemName: "questionmark")
                            .font(.title)
                            .frame(width: 96, height: 96)
                            .overlay(Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            .foregroundStyle(Color.ratioInk2)
                        Text(failed ? "Reconnecting…" : "Finding a fair opponent…").ratioFont(.h3).multilineTextAlignment(.center)
                        Text("Searching within ±\(window) · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    .padding(RatioSpace.m)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous)
                            .strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            ColumnsLayout(fraction: 0.5, spacing: RatioSpace.m) {
                facts
                TimelineView(.periodic(from: started, by: 1)) { context in
                    sparringOffer(elapsed: Int(context.date.timeIntervalSince(started)))
                }
            }
        }
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact("Format", "First to 3")
            Divider()
            fact("Per question", "\(seconds)\u{00A0}s")
            Divider()
            fact("Pool", seconds == DuelTime.standard ? "Standard" : "Extra time")
        }
        .fixedSize(horizontal: false, vertical: true)
        .ratioCard(padding: 0)
    }

    private func sparringOffer(elapsed: Int) -> some View {
        HStack(alignment: .top, spacing: RatioSpace.s) {
            SparringMark(size: 36)
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                Text(elapsed < 60 ? "No one yet? After 60\u{00A0}s we'll offer a sparring partner, clearly labelled." : "No one's free right now. Spar with a labelled partner instead?")
                    .ratioFont(.body)
                if elapsed >= 60 {
                    RatioButton("Spar instead →", style: .secondary) { cancel(then: spar) }
                }
            }
        }
        .ratioPanel()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            headline
            HStack(spacing: RatioSpace.s) {
                ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 64)
                VStack(alignment: .leading) {
                    Text("You").ratioFont(.h2)
                    Text(student.profile.displayName ?? "").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: RatioSpace.xs)
                VStack(alignment: .trailing) {
                    Text("Rating").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text(Int((student.ratings[scope]?.rating ?? 1200).rounded()).formatted()).ratioFont(.monoData)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: RatioSpace.s) {
                Rectangle().fill(Color.ratioRule).frame(height: 1)
                Text("v").ratioFont(.h2).italic().foregroundStyle(Color.ratioInk2)
                Rectangle().fill(Color.ratioRule).frame(height: 1)
            }
            .accessibilityHidden(true)
            TimelineView(.periodic(from: started, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(started))
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    HStack(spacing: RatioSpace.s) {
                        ProgressView().frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                            Text(failed ? "Reconnecting…" : "Finding a fair opponent…").ratioFont(.h3)
                            Text("Searching within ±\(window) · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                        }
                    }
                    HStack(alignment: .top, spacing: RatioSpace.s) {
                        SparringMark(size: 36)
                        VStack(alignment: .leading, spacing: RatioSpace.s) {
                            Text(elapsed < 60 ? "No one yet? After 60\u{00A0}s we'll offer a sparring partner, clearly labelled." : "No one's free right now. Spar with a labelled partner instead?")
                                .ratioFont(.body)
                            if elapsed >= 60 {
                                RatioButton("Spar instead →", style: .secondary) { cancel(then: spar) }
                            }
                        }
                    }
                    .ratioPanel()
                }
            }
            // Three facts side by side; stacked at accessibility sizes.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                fact("Format", "First to 3")
                Divider()
                fact("Per question", "\(seconds)\u{00A0}s")
                Divider()
                fact("Pool", seconds == DuelTime.standard ? "Standard" : "Extra time")
            }
            .fixedSize(horizontal: false, vertical: true)
            .ratioCard(padding: 0)
        }
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
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(value).ratioFont(.h3)
        }
        .padding(RatioSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                            HStack(spacing: RatioSpace.s) {
                                Text("\(level)").ratioFont(.h2).frame(minWidth: 28)
                                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                                    HStack(spacing: RatioSpace.xs) {
                                        Text(SparringLevel.title(level)).ratioFont(.h3)
                                        if level == suggested { RatioTag("Suggested") }
                                    }
                                    Text(SparringLevel.detail(level)).ratioFont(.small).foregroundStyle(Color.ratioInk2)
                                }
                                Spacer(minLength: RatioSpace.xs)
                                Text(Int(Self.ratings[level - 1]).formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                            }
                            .padding(.vertical, RatioSpace.xxs)
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
            // The deep oxblood in both themes, so cream text stays readable.
            .background(Color.ratioCommitFill)
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
                            withAnimation(RatioMotion.tap) {
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

/// Lays chips out left to right, wrapping onto new lines as needed.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
