import SwiftUI

/// A full-screen sparring match or tutorial: versus → rounds → judgment → debrief.
struct DuelMatchView: View {
    let module: Module
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

    init(module: Module, level: Int, seconds: Int, isTutorial: Bool = false) {
        self.module = module
        self.level = level
        self.seconds = seconds
        self.isTutorial = isTutorial
        _model = State(initialValue: DuelMatchModel(module: module, level: level, seconds: seconds, isTutorial: isTutorial))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                status("Finding your sparring partner…", dark: true)
            case .failed:
                if model.hitFreeLimit {
                    VStack(spacing: 20) {
                        Text("That's today's three free duels.").ratioFont(.h2)
                        Text("They reset at midnight. Ratio Plus makes duels unlimited.").ratioFont(.body).multilineTextAlignment(.center)
                        RatioButton("See Ratio Plus") {
                            dismiss()
                            navigator.paywall = "Duels are unlimited with Ratio Plus."
                        }
                        Button("Close") { dismiss() }.ratioFont(.monoLabel)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    failure("We couldn't start the match. Check your connection and try again.") { Task { await model.load() } }
                }
            case .versus:
                VersusView(model: model) { model.begin() }
            case .coaching, .playing, .revealing:
                VStack(spacing: 0) {
                    HStack { closeButton; Spacer() }.padding(.horizontal, 12)
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
                    let record = DuelRecord(match: match, result: result, module: module)
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
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .task { await model.load() }
        .onDisappear { model.stop() }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(isTutorial ? "Leave the tutorial" : "Leave the match")
        .foregroundStyle(Color.ratioInk2)
    }

    private func rematch() {
        showsDebrief = false
        model.stop()
        model = DuelMatchModel(module: module, level: level, seconds: seconds, isTutorial: false)
        Task { await model.load() }
    }

    private func status(_ text: String, dark: Bool) -> some View {
        VStack(spacing: 24) {
            ZStack {
                RatioRings(diameter: 140)
                SparringMark(size: 56)
            }
            Text(text).ratioFont(.h3).italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func failure(_ text: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Text(text).ratioFont(.body).multilineTextAlignment(.center)
            RatioButton("Try again", style: .secondary, action: retry)
            Button("Close") { dismiss() }.ratioFont(.monoLabel)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tutorial

    private static let coachMarks: [(label: String, title: String, detail: String)] = [
        ("The clock", "Ten seconds a question. The ring turns red in the last three.",
         "You'll feel a light pulse too. Extended time (15 s or 20 s) is in Duel settings."),
        ("Scoring", "The first right answer takes the point.",
         "First to three wins. At 2–2 a final round, of any type, decides it."),
        ("The penalty", "A wrong answer gives the point away.",
         "So don't guess blind: if you're first and wrong, your opponent scores."),
    ]

    private var coachMarks: some View {
        let mark = Self.coachMarks[coachStep]
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(coachStep + 1) / \(Self.coachMarks.count)")
                    Spacer()
                    Text(mark.label)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                Text(mark.title).ratioFont(.h2)
                Text(mark.detail).ratioFont(.body).foregroundStyle(Color.ratioInk2)
                HStack {
                    Button("Skip") { finishTutorial() }
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    Spacer()
                    Button {
                        if coachStep + 1 < Self.coachMarks.count { coachStep += 1 } else { model.begin() }
                    } label: {
                        Text(coachStep + 1 < Self.coachMarks.count ? "Next" : "Play")
                            .ratioFont(.h3)
                            .foregroundStyle(Color.ratioOnInk)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 50)
                            .background(Color.ratioInk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.ratioRule) }
            .padding(24)
            .accessibilityAddTraits(.isModal)
        }
        .foregroundStyle(Color.ratioInk)
    }

    private var tutorialDone: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Practice · Done").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("That's a \(Text("duel.").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
            Text("You took \(model.score[0]) of \(model.played.count) points. Real matches are first to three, and move your rating and your profile.")
                .ratioFont(.h3)
            Spacer()
            RatioButton("Done", style: .secondary) { finishTutorial() }
        }
        .padding(24)
    }

    private func finishTutorial() {
        tutorialSeen = true
        dismiss()
    }
}

/// screens/34-versus.png — the partner on the dark half, the student on the light half.
private struct VersusView: View {
    let model: DuelMatchModel
    let begin: () -> Void

    @Environment(StudentStore.self) private var student

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Color.ratioInk.frame(height: proxy.size.height * 0.47)
                    Rectangle().fill(Color.ratioOxblood).frame(height: 1)
                    Color.ratioParchment
                }
                .ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("\(model.module.title) · First to 3 · Sparring").ratioFont(.monoLabel).foregroundStyle(Color.ratioParchment.opacity(0.7))
                    SparringMark(size: 96).colorInvert()
                    Text("Sparring partner").ratioFont(.h1).foregroundStyle(Color.ratioParchment)
                    Text("Level \(model.level) · \(SparringLevel.title(model.level))").ratioFont(.body).foregroundStyle(Color.ratioParchment.opacity(0.7))
                    rating(model.match?.partner.rating ?? 0).foregroundStyle(Color.ratioParchment)
                    Spacer()
                }
                .padding(.top, 24)
                .frame(height: proxy.size.height * 0.47)
                .frame(maxHeight: .infinity, alignment: .top)

                ZStack {
                    Circle().fill(Color.ratioPaper)
                    Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
                    Circle().strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [2, 3])).padding(8)
                    VStack(spacing: 2) {
                        RatioSpotArt.scales.view.frame(width: 70).foregroundStyle(Color.ratioInk)
                        Text("v").ratioFont(.h2).italic().foregroundStyle(Color.ratioOxblood)
                    }
                }
                .frame(width: 130, height: 130)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.47)

                VStack(spacing: 12) {
                    Spacer()
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 96)
                    Text(name).ratioFont(.h1)
                    rating(model.match?.rating.rating ?? 1200)
                    RatioButton("Begin →", action: begin).padding(.top, 12)
                }
                .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var name: String {
        [student.profile.displayName, student.profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    private func rating(_ value: Double) -> some View {
        HStack(spacing: 8) {
            Text("Rating").ratioFont(.monoLabel).opacity(0.7)
            Text(Int(value.rounded()).formatted()).ratioFont(.monoData)
        }
    }
}
