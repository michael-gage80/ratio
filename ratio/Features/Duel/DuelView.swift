import SwiftUI

/// screens/31-duel.png — the Duel tab: rating per module, ranked play, sparring, the
/// tutorial, and recent matches. Live opponents, friend lobbies and async challenges
/// arrive with the next phase; until then Find an opponent offers a sparring partner.
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
    @State private var playing: Match?

    private struct Match: Identifiable {
        let id = UUID()
        let module: Module
        let level: Int
        let isTutorial: Bool
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
                    VStack(spacing: 12) {
                        row(icon: "number", title: "Friend lobby", detail: "Play with a code · next build", enabled: false) {}
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
                MatchmakingView(module: module, seconds: seconds) {
                    showsMatchmaking = false
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
        .fullScreenCover(item: $playing) { match in
            DuelMatchView(module: match.module, level: match.level, seconds: seconds, isTutorial: match.isTutorial)
        }
        .onChange(of: navigator.showsDuelTutorial, initial: true) { _, shows in
            guard shows, let module else { return }
            navigator.showsDuelTutorial = false
            play(module, level: 1, tutorial: true)
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
        let finished = student.matches.filter { $0.status == "complete" && $0.result != nil }
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent matches").ratioFont(.h2)
                VStack(spacing: 0) {
                    ForEach(Array(finished.prefix(5).enumerated()), id: \.element.id) { index, match in
                        if index > 0 { Divider().overlay(Color.ratioRule) }
                        MatchRow(match: match)
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
        playing = Match(module: module, level: level, isTutorial: tutorial)
    }
}

/// "Won 3–1 · v Sparring partner, level 2 · Yesterday · Crime   +10"
struct MatchRow: View {
    let match: MatchSummary

    var body: some View {
        if let result = match.result {
            let won = result.winner == 0
            let delta = result.ratingAfter - result.ratingBefore
            HStack(spacing: 14) {
                Image(systemName: won ? "checkmark" : result.winner == nil ? "equal" : "minus")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(won ? Color.ratioVerdigris : Color.ratioInk2))
                    .foregroundStyle(won ? Color.ratioVerdigris : Color.ratioInk2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(won ? "Won" : result.winner == nil ? "Drew" : "Lost") \(result.score[0])–\(result.score[1]) · v Sparring partner")
                        .ratioFont(.body)
                    Text([match.createdAt?.formatted(.relative(presentation: .named)), Module(rawValue: match.moduleId)?.title, "Level \(match.partner?.level ?? 1)", "Practice · not on the boards"]
                        .compactMap { $0 }.joined(separator: " · "))
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
}

/// screens/33-matchmaking.png — until live matchmaking lands, this shows the format and
/// offers the labelled sparring partner straight away rather than making the student wait.
private struct MatchmakingView: View {
    let module: Module
    let seconds: Int
    let spar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @State private var started = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44) }
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
                HStack(spacing: 16) {
                    ProgressView().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Finding a fair match…").ratioFont(.h3)
                        Text("Searching within ±100 · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                SparringMark(size: 36)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live opponents arrive in the next build. Spar with a clearly labelled partner meanwhile.")
                        .ratioFont(.body)
                    RatioButton("Spar instead →", style: .secondary, action: spar)
                }
            }
            .padding(18)
            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(spacing: 0) {
                fact("Format", "First to 3")
                Divider()
                fact("Per question", "\(seconds) s")
                Divider()
                fact("Rating", "Glicko-2")
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
            Spacer()
            RatioButton("Cancel", style: .tertiary) { dismiss() }
        }
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
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
