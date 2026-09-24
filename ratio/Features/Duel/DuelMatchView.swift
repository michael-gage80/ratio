import SwiftUI

/// A full-screen sparring match or tutorial: versus → rounds → judgment → debrief.
struct DuelMatchView: View {
    let scope: DuelScope
    let level: Int
    let seconds: Int
    let isTutorial: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @AppStorage("duel.tutorialSeen") private var tutorialSeen = false
    @State private var model: DuelMatchModel
    @State private var showsDebrief = false
    @State private var coachStep = 0

    init(scope: DuelScope, level: Int, seconds: Int, isTutorial: Bool = false) {
        self.scope = scope
        self.level = level
        self.seconds = seconds
        self.isTutorial = isTutorial
        _model = State(initialValue: DuelMatchModel(scope: scope, level: level, seconds: seconds, isTutorial: isTutorial))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                status("Finding your sparring partner…", dark: true)
            case .failed:
                if model.hitFreeLimit {
                    VStack(spacing: RatioSpace.m) {
                        Text("That's today's three free duels.").ratioFont(.h2).multilineTextAlignment(.center)
                        Text("They reset at midnight. Ratio Plus makes duels unlimited.").ratioFont(.body).multilineTextAlignment(.center)
                        RatioButton("See Ratio Plus") {
                            dismiss()
                            navigator.paywall = "Duels are unlimited with Ratio Plus."
                        }
                        closeLink
                    }
                    .padding(RatioSpace.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    failure("We couldn't start the duel. Check your connection and try again.") { Task { await model.load() } }
                }
            case .versus:
                VersusView(model: model) { model.begin() }
            case .coaching, .playing, .revealing:
                VStack(spacing: 0) {
                    HStack { closeButton; Spacer() }.padding(.horizontal, RatioSpace.s)
                    DuelRoundView(model: model)
                }
                .overlay {
                    if model.phase == .coaching { coachMarks }
                }
            case .submitting:
                status("Entering judgment…", dark: true)
            case .submitFailed:
                failure("We couldn't reach the referee. Your answers are still here.") { Task { await model.submit() } }
            case .finished:
                if isTutorial {
                    tutorialDone
                } else if let result = model.result, let match = model.match {
                    let record = DuelRecord(match: match, result: result, scope: scope)
                    if showsDebrief {
                        DuelDebriefView(record: record) {
                            dismiss()
                            navigator.backToToday()
                        } revisit: { lessonId in
                            dismiss()
                            navigator.pathwayPath = [.overview(lessonId)]
                            navigator.tab = .pathway
                        }
                    } else {
                        DuelResultView(record: record, rematch: rematch, debrief: { showsDebrief = true }, close: { dismiss() })
                    }
                }
            }
        }
        .ratioPage()
        .ratioMeasuresWidth()
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var closeButton: some View {
        RatioIconButton(systemImage: "xmark", label: isTutorial ? "Leave the tutorial" : "Leave the duel") { dismiss() }
            .foregroundStyle(Color.ratioInk2)
            .keyboardShortcut(.cancelAction)
    }

    private var closeLink: some View {
        Button("Close") { dismiss() }
            .ratioFont(.monoLabel)
            .foregroundStyle(Color.ratioInk2)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func rematch() {
        showsDebrief = false
        model.stop()
        model = DuelMatchModel(scope: scope, level: level, seconds: seconds, isTutorial: false)
        Task { await model.load() }
    }

    private func status(_ text: String, dark: Bool) -> some View {
        VStack(spacing: RatioSpace.m) {
            ZStack {
                RatioRings(diameter: 140)
                SparringMark(size: 56)
            }
            Text(text).ratioFont(.h3).italic().multilineTextAlignment(.center)
        }
        .padding(RatioSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func failure(_ text: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: RatioSpace.xs) {
            RatioErrorState(message: text, retry: retry)
            closeLink
        }
        .padding(RatioSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tutorial

    private static let coachMarks: [(label: String, title: String, detail: String)] = [
        ("The clock", "Fifteen seconds a question. The ring turns red in the last three.",
         "You'll feel a light pulse too. Extra time (30\u{00A0}s) is in Settings → Accessibility."),
        ("Scoring", "The first right answer takes the point.",
         "First to three wins. At 2–2 a final round, of any type, decides it."),
        ("The penalty", "A wrong answer gives the point away.",
         "So don't guess blind: if you're first and wrong, your opponent scores."),
    ]

    private var coachMarks: some View {
        CoachMarks(marks: Self.coachMarks, step: $coachStep, skip: finishTutorial) { model.begin() }
    }

    fileprivate static func compactCoachMark(_ marks: [(label: String, title: String, detail: String)], step: Binding<Int>, skip: @escaping () -> Void, play: @escaping () -> Void) -> some View {
        let coachStep = step.wrappedValue
        let mark = marks[coachStep]
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                HStack {
                    Text("\(coachStep + 1) / \(marks.count)")
                    Spacer()
                    Text(mark.label)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                Text(mark.title).ratioFont(.h2)
                Text(mark.detail).ratioFont(.body).foregroundStyle(Color.ratioInk2)
                HStack {
                    Button("Skip") { skip() }
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                    Button {
                        if coachStep + 1 < marks.count { step.wrappedValue += 1 } else { play() }
                    } label: {
                        // Parchment on ink, which flips correctly in dark mode.
                        Text(coachStep + 1 < marks.count ? "Next" : "Play")
                            .ratioFont(.h3)
                            .foregroundStyle(Color.ratioParchment)
                            .padding(.horizontal, RatioSpace.l)
                            .frame(minHeight: 56)
                            .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                    }
                    .buttonStyle(.ratioPress)
                }
            }
            .ratioCard()
            .padding(RatioSpace.m)
            .accessibilityAddTraits(.isModal)
        }
        .foregroundStyle(Color.ratioInk)
    }

    private var tutorialDone: some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            Spacer()
            Text("Practice · Done").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("That's a \(Text("duel.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("You took \(model.score[0]) of \(model.played.count) points. Real duels are first to three, and move your rating and your profile.")
                .ratioFont(.h3)
            Spacer()
            RatioButton("Done", style: .secondary) { finishTutorial() }
        }
        .padding(RatioSpace.m)
    }

    private func finishTutorial() {
        tutorialSeen = true
        dismiss()
    }
}

/// The tutorial's three rules: one card at a time on iPhone; on iPad all three side by
/// side, the current one outlined (screens/iPad/5-duel/02-duel-tutorial.png).
private struct CoachMarks: View {
    let marks: [(label: String, title: String, detail: String)]
    @Binding var step: Int
    let skip: () -> Void
    let play: () -> Void

    @Environment(\.ratioWidth) private var width

    var body: some View {
        if width.isCompact {
            DuelMatchView.compactCoachMark(marks, step: $step, skip: skip, play: play)
        } else {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    HStack {
                        Text("How duels work · \(step + 1) / \(marks.count)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Spacer()
                        Button("Skip", action: skip)
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    HStack(alignment: .top, spacing: RatioSpace.s) {
                        ForEach(marks.indices, id: \.self) { index in
                            let mark = marks[index]
                            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                                HStack {
                                    Text("\(DuelRoundView.numerals[index]) · \(mark.label)")
                                    Spacer()
                                    Text(index == step ? "Now" : index < step ? "Done" : "Next")
                                        .foregroundStyle(index == step ? Color.ratioOxblood : Color.ratioInk2)
                                }
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                                Text(mark.title).ratioFont(.h3)
                                Text(mark.detail).ratioFont(.small).foregroundStyle(Color.ratioInk2)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .ratioPanel(Color.ratioPaper)
                            .overlay {
                                RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
                                    .strokeBorder(index == step ? Color.ratioInk : Color.ratioRule, lineWidth: index == step ? 2 : 1)
                            }
                            .opacity(index == step ? 1 : 0.6)
                        }
                    }
                    HStack(spacing: RatioSpace.s) {
                        Spacer()
                        KeyHint(keys: "→", label: "Next")
                        Button {
                            if step + 1 < marks.count { step += 1 } else { play() }
                        } label: {
                            // Parchment on ink, which flips correctly in dark mode.
                            Text(step + 1 < marks.count ? "Next →" : "Play →")
                                .ratioFont(.h3)
                                .foregroundStyle(Color.ratioParchment)
                                .padding(.horizontal, RatioSpace.l)
                                .frame(minHeight: 56)
                                .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                        }
                        .buttonStyle(.ratioPress)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                }
                .ratioCard()
                .frame(maxWidth: 960)
                .padding(RatioSpace.l)
                .accessibilityAddTraits(.isModal)
            }
            .foregroundStyle(Color.ratioInk)
        }
    }
}

/// screens/34-versus.png — the partner on the dark half, the student on the light half.
/// On iPad the halves sit side by side (screens/iPad/5-duel/04-versus.png).
private struct VersusView: View {
    let model: DuelMatchModel
    let begin: () -> Void

    @Environment(StudentStore.self) private var student
    @Environment(\.ratioWidth) private var width

    var body: some View {
        if width.isCompact { stacked } else { sideBySide }
    }

    private var sideBySide: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.ratioParchment
                Rectangle().fill(Color.ratioOxblood).frame(width: 1)
                Color.ratioInk
            }
            .ignoresSafeArea()
            HStack(spacing: 0) {
                VStack(spacing: RatioSpace.s) {
                    Text("You · \(model.scope.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 128)
                    Text(name).ratioFont(.display).foregroundStyle(Color.ratioInk)
                    rating(model.match?.rating.rating ?? 1200).foregroundStyle(Color.ratioInk)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: RatioSpace.s) {
                    Text("Opponent · \(model.scope.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioParchment.opacity(0.75))
                    SparringMark(size: 128).colorInvert()
                    Text("Sparring partner").ratioFont(.display).foregroundStyle(Color.ratioParchment)
                    Text("Level \(model.level) · \(SparringLevel.title(model.level))").ratioFont(.body).foregroundStyle(Color.ratioParchment.opacity(0.75))
                    rating(model.match?.partner.rating ?? 0).foregroundStyle(Color.ratioParchment)
                }
                .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 200)
            seal.frame(width: 200, height: 200).padding(.bottom, 200)
            VStack(spacing: RatioSpace.s) {
                Text("Round I · First to 3 · \(model.limitMs / 1000)\u{00A0}s").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                RatioButton("Round I →", action: begin)
                    .keyboardShortcut(.return, modifiers: .command)
                KeyHint(keys: "⌘↩", label: "Begin")
            }
            .ratioCard()
            .frame(maxWidth: 560)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(RatioSpace.l)
        }
        .accessibilityElement(children: .contain)
    }

    private var seal: some View {
        ZStack {
            Circle().fill(Color.ratioPaper)
            Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
            Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(RatioSpace.xs)
            VStack(spacing: 2) {
                RatioSpotArt.scales.view.frame(width: 100).foregroundStyle(Color.ratioInk)
                Text("v").ratioFont(.h2).italic().foregroundStyle(Color.ratioOxblood)
            }
        }
        .accessibilityHidden(true)
    }

    private var stacked: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Color.ratioInk.frame(height: proxy.size.height * 0.47)
                    Rectangle().fill(Color.ratioOxblood).frame(height: 1)
                    Color.ratioParchment
                }
                .ignoresSafeArea()
                VStack(spacing: RatioSpace.s) {
                    Text("\(model.scope.title) · First to 3 · Sparring").ratioFont(.monoLabel).foregroundStyle(Color.ratioParchment.opacity(0.7))
                    SparringMark(size: 96).colorInvert()
                    Text("Sparring partner").ratioFont(.h1).foregroundStyle(Color.ratioParchment)
                    Text("Level \(model.level) · \(SparringLevel.title(model.level))").ratioFont(.body).foregroundStyle(Color.ratioParchment.opacity(0.7))
                    rating(model.match?.partner.rating ?? 0).foregroundStyle(Color.ratioParchment)
                    Spacer()
                }
                .padding(.top, RatioSpace.m)
                .padding(.horizontal, RatioSpace.m)
                .multilineTextAlignment(.center)
                .frame(height: proxy.size.height * 0.47)
                .frame(maxHeight: .infinity, alignment: .top)

                ZStack {
                    Circle().fill(Color.ratioPaper)
                    Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
                    Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(RatioSpace.xs)
                    VStack(spacing: 2) {
                        RatioSpotArt.scales.view.frame(width: 70).foregroundStyle(Color.ratioInk)
                        Text("v").ratioFont(.h2).italic().foregroundStyle(Color.ratioOxblood)
                    }
                }
                .frame(width: 130, height: 130)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.47)
                .accessibilityHidden(true)

                VStack(spacing: RatioSpace.s) {
                    Spacer()
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 96)
                    Text(name).ratioFont(.h1)
                    rating(model.match?.rating.rating ?? 1200)
                    RatioButton("Begin →", action: begin).padding(.top, RatioSpace.xs)
                }
                .padding(RatioSpace.m)
            }
        }
        // The two halves are fixed shares of the screen; beyond this size they'd overlap.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
    }

    private var name: String {
        [student.profile.displayName, student.profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    private func rating(_ value: Double) -> some View {
        HStack(spacing: RatioSpace.xs) {
            Text("Rating").ratioFont(.monoLabel).opacity(0.7)
            Text(Int(value.rounded()).formatted()).ratioFont(.monoData)
        }
    }
}
