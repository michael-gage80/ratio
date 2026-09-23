import SwiftUI

/// screens/31-duel.png — the Duel tab: rating per module, ranked play against other
/// students, friend lobbies, async challenges waiting for you, sparring, the tutorial,
/// and recent matches.
struct DuelView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @AppStorage("duel.tutorialSeen") private var tutorialSeen = false
    /// 0 for standard time, or 15 / 20 seconds (PRD: "Extended time").
    @AppStorage("duel.extendedSeconds") private var extendedSeconds = 0
    @State private var selected: Module?
    @State private var showsMatchmaking = false
    @State private var choosingLevel = false
    @State private var lobbyEntry: LobbyEntry?
    @State private var cover: Cover?
    @State private var notice: String?

    /// Everything that takes over the screen.
    private enum Cover: Identifiable {
        case sparring(Module, level: Int, tutorial: Bool)
        case live(String)
        case lobby(String)
        case challenge(ChallengeSummary)

        var id: String {
            switch self {
            case .sparring(let module, let level, let tutorial): "sparring-\(module.rawValue)-\(level)-\(tutorial)"
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

    private var module: Module? { selected.flatMap { modules.contains($0) ? $0 : nil } ?? modules.first }
    private var seconds: Int { extendedSeconds == 0 ? 10 : extendedSeconds }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let module {
                    moduleChips(selected: module)
                    ratingCard(module)
                    extendedTime
                    waitingForYou
                    VStack(spacing: 12) {
                        row(icon: "number", title: "Friend lobby", detail: "Play with a code") { lobbyEntry = LobbyEntry(code: nil) }
                        row(mark: true, title: "Sparring partner", detail: "Practise against a labelled bot, 5 levels") { startSparring() }
                        row(icon: "questionmark", title: "How duels work", detail: "Replay the tutorial") { play(module, level: 1, tutorial: true) }
                    }
                    recentMatches
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
            if let module {
                MatchmakingView(module: module, seconds: seconds) { matchId in
                    showsMatchmaking = false
                    cover = .live(matchId)
                } spar: {
                    choosingLevel = true
                }
            }
        }
        .sheet(isPresented: $choosingLevel) {
            if let module {
                LevelPicker(module: module, rating: student.ratings[module]?.rating) { level in
                    choosingLevel = false
                    play(module, level: level, tutorial: false)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(item: $lobbyEntry) { entry in
            LobbyEntryView(module: module ?? .crime, seconds: seconds, initialCode: entry.code) { code in
                lobbyEntry = nil
                cover = .lobby(code)
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $cover) { cover in
            switch cover {
            case .sparring(let module, let level, let tutorial):
                DuelMatchView(module: module, level: level, seconds: seconds, isTutorial: tutorial)
            case .live(let matchId):
                LiveMatchView(matchId: matchId)
            case .lobby(let code):
                LobbyView(code: code)
            case .challenge(let challenge):
                ChallengeView(challenge: challenge)
            }
        }
        .onChange(of: navigator.showsDuelTutorial, initial: true) { _, shows in
            guard shows, let module else { return }
            navigator.showsDuelTutorial = false
            play(module, level: 1, tutorial: true)
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

    @ViewBuilder
    private var waitingForYou: some View {
        if !student.challenges.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Waiting for you").ratioFont(.h2)
                    Spacer()
                    let toPlay = student.challenges.count { $0.done[student.uid] != true }
                    if toPlay > 0 {
                        Text("\(toPlay) \(toPlay == 1 ? "challenge" : "challenges")").ratioFont(.monoLabel).foregroundStyle(Color.ratioOxblood)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(student.challenges.enumerated()), id: \.element.id) { index, challenge in
                        if index > 0 { Divider().overlay(Color.ratioRule) }
                        challengeRow(challenge)
                    }
                }
                .padding(.horizontal, 18)
                .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
            }
        }
    }

    private func challengeRow(_ challenge: ChallengeSummary) -> some View {
        let opponent = challenge.opponent(of: student.uid)
        let myTurn = challenge.done[student.uid] != true
        let hours = max(1, Int(challenge.expiresAt.timeIntervalSinceNow / 3600))
        return HStack(spacing: 14) {
            ProfilePhoto(uid: opponent.uid, initial: String(opponent.name.prefix(1)), version: nil, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(opponent.name) · \(Module(rawValue: challenge.moduleId)?.title ?? "")").ratioFont(.h3)
                Text(myTurn
                     ? (challenge.isFrom(student.uid) ? "Your challenge · play your half" : (challenge.done[opponent.uid] == true ? "Played their half" : "Challenged you"))
                     : "Waiting for their half")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("\(hours) h left").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
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
    }

    private func challenge(_ match: MatchSummary) {
        guard let opponent = match.opponent(of: student.uid), let module = Module(rawValue: match.moduleId) else { return }
        Task {
            do {
                try await DuelService.createChallenge(opponent: opponent.uid, module: module, seconds: seconds)
                notice = "\(opponent.name) has 24 hours to play their half. It's under Waiting for you."
            } catch {
                notice = (error as NSError).localizedDescription
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Human duels · Ranked by module").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text("Duel\(Text(".").foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            }
            Spacer()
            ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 56)
        }
    }

    private func moduleChips(selected current: Module) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(modules) { module in
                    Button { selected = module } label: {
                        Text(module.title)
                            .ratioFont(.body)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .foregroundStyle(module == current ? Color.ratioOnInk : Color.ratioInk)
                            .background(module == current ? Color.ratioInk : Color.ratioPaper, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.ratioRule))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(module == current ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ratingCard(_ module: Module) -> some View {
        let rating = student.ratings[module]
        return VStack(alignment: .leading, spacing: 16) {
            Text("Ranked · \(module.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
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
                if tutorialSeen { showsMatchmaking = true } else { play(module, level: 1, tutorial: true) }
            }
        }
        .padding(22)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    private var extendedTime: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { extendedSeconds > 0 }, set: { extendedSeconds = $0 ? 15 : 0 })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extended time").ratioFont(.h3)
                    Text("15 s or 20 s a question. In ranked play you're matched with other extended-time players.")
                        .ratioFont(.small)
                        .foregroundStyle(Color.ratioInk2)
                }
            }
            .tint(Color.ratioVerdigris)
            if extendedSeconds > 0 {
                Picker("Time per question", selection: $extendedSeconds) {
                    Text("15 s").tag(15)
                    Text("20 s").tag(20)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(20)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
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
        if tutorialSeen { choosingLevel = true } else if let module { play(module, level: 1, tutorial: true) }
    }

    private func play(_ module: Module, level: Int, tutorial: Bool) {
        cover = .sparring(module, level: level, tutorial: tutorial)
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
            ? [match.createdAt?.formatted(.relative(presentation: .named)), Module(rawValue: match.moduleId)?.title, "Level \(match.partner?.level ?? 1)", "Practice · not on the boards"]
            : [match.createdAt?.formatted(.relative(presentation: .named)), Module(rawValue: match.moduleId)?.title, kind]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// screens/33-matchmaking.png — searches for a student within ±100 rating in this
/// module and time pool, widening every 10 s; after 60 s a labelled sparring partner is
/// offered instead (PRD: "Ranked (live)").
private struct MatchmakingView: View {
    let module: Module
    let seconds: Int
    let found: (String) -> Void
    let spar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @State private var started = Date.now
    @State private var window = 100
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button { cancel() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Cancel")
                Spacer()
                Text("Matching · \(module.title) · Ranked").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
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
                    Text(Int((student.ratings[module]?.rating ?? 1200).rounded()).formatted()).ratioFont(.monoData)
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
                fact("Pool", seconds == 10 ? "Standard" : "Extended")
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
                let result = try await DuelService.findMatch(module: module, seconds: seconds)
                failed = false
                if let matchId = result.matchId {
                    found(matchId)
                    return
                }
                window = result.window ?? window
            } catch {
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
    let module: Module
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
                    Text("Sparring moves your \(module.title) rating and your profile. Wins against a sparring partner never count on the boards.")
                        .ratioFont(.small)
                }
            }
            .navigationTitle("Sparring partner")
            .toolbarTitleDisplayMode(.inline)
        }
    }
}
