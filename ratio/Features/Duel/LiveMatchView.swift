import FirebaseFunctions
import SwiftUI

/// A live duel against another student, full screen: versus and countdown, the
/// rounds, then judgment and the debrief (screens 34–39 with a human opponent).
struct LiveMatchView: View {
    let matchId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @Environment(AppNavigator.self) private var navigator
    @State private var model: LiveMatchModel?
    @State private var showsDebrief = false
    @State private var confirmingLeave = false
    @State private var challengeSent: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                waiting("Connecting to the duel…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ratioPage()
        .ratioMeasuresWidth()
        .onAppear {
            guard model == nil else { return }
            let live = LiveMatchModel(matchId: matchId, uid: student.uid)
            live.start()
            model = live
        }
        .onDisappear { model?.stop() }
        .alert("Challenge sent", isPresented: Binding(get: { challengeSent != nil }, set: { if !$0 { challengeSent = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(challengeSent ?? "")
        }
    }

    @ViewBuilder
    private func content(_ model: LiveMatchModel) -> some View {
        switch model.phase {
        case .connecting:
            waiting("Connecting to the duel…")
        case .countdown:
            LiveVersus(model: model)
        case .round:
            VStack(spacing: 0) {
                HStack {
                    RatioIconButton(systemImage: "xmark", label: "Leave the duel") { confirmingLeave = true }
                        .foregroundStyle(Color.ratioInk2)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Text("\(DuelScope.title(of: model.moduleId ?? "")) · Live").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                .padding(.horizontal, RatioSpace.s)
                if let since = model.opponentGoneSince {
                    OpponentGoneBanner(name: model.opponent.name, since: since)
                        .padding(.horizontal, RatioSpace.m)
                        .padding(.bottom, RatioSpace.xs)
                }
                DuelRoundView(model: model)
            }
            .confirmationDialog("Leave the duel?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave — \(model.opponent.name) wins", role: .destructive) {
                    Task { await model.leave() }
                }
                Button("Keep playing", role: .cancel) {}
            } message: {
                Text("Leaving forfeits the duel and counts as a loss.")
            }
        case .settling:
            waiting("Entering judgment…")
        case .finished:
            if let record = model.record {
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
                    DuelResultView(record: record, rematch: { challenge(record) }, debrief: { showsDebrief = true }, close: { dismiss() })
                }
            }
        case .failed:
            VStack(spacing: RatioSpace.m) {
                Text("This duel isn't available any more.").ratioFont(.h3).multilineTextAlignment(.center)
                RatioButton("Close", style: .secondary) { dismiss() }
            }
            .padding(RatioSpace.l)
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: RatioSpace.m) {
            RatioRings(diameter: 140)
            Text(text).ratioFont(.h3).italic().multilineTextAlignment(.center)
        }
        .padding(RatioSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    /// Rematch against a student is an async challenge: they get 24 hours to play.
    private func challenge(_ record: DuelRecord) {
        guard let opponent = record.opponent.uid, let scope = DuelScope(id: record.moduleId) else { return }
        Task {
            do {
                try await DuelService.createChallenge(opponent: opponent, scope: scope, seconds: record.limitMs / 1000)
                challengeSent = "\(record.opponent.name) has 24 hours to play their half. You'll find it under Waiting for you."
            } catch {
                challengeSent = (error as NSError).localizedDescription
            }
        }
    }
}

/// Screen 34 for a live match: both players and a countdown to the first question. On
/// iPad the two halves sit side by side (screens/iPad/5-duel/04-versus.png).
private struct LiveVersus: View {
    let model: LiveMatchModel

    @Environment(StudentStore.self) private var student
    @Environment(\.ratioWidth) private var width

    var body: some View {
        if width.isCompact { stacked } else { sideBySide }
    }

    private var countdown: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let seconds = max(0, Int(((model.firstRoundAt ?? context.date).timeIntervalSince(context.date)).rounded(.up)))
            ZStack {
                Circle().fill(Color.ratioPaper)
                Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
                Text(seconds > 0 ? "\(seconds)" : "v").ratioFont(.displayAccent)
                    .foregroundStyle(Color.ratioOxblood)
                    .contentTransition(.numericText(countsDown: true))
            }
            .accessibilityLabel(seconds > 0 ? "Starting in \(seconds)" : "Starting")
        }
    }

    private var sideBySide: some View {
        let opponent = model.opponent
        return ZStack {
            HStack(spacing: 0) {
                VStack(spacing: RatioSpace.s) {
                    Text("You · \(DuelScope.title(of: model.moduleId ?? ""))").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 128)
                    Text("You").ratioFont(.display)
                    Text("Rating \((model.view?.players[student.uid]?.rating ?? 1200).formatted())").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                }
                .foregroundStyle(Color.ratioInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ratioParchment)
                Rectangle().fill(Color.ratioOxblood).frame(width: 1)
                VStack(spacing: RatioSpace.s) {
                    Text("Opponent · First to 3").ratioFont(.monoLabel).opacity(0.75)
                    OpponentMark(opponent: opponent, size: 128)
                    Text(opponent.name).ratioFont(.display)
                    Text(opponent.detail).ratioFont(.monoData).opacity(0.75)
                }
                .foregroundStyle(Color.ratioParchment)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.ratioInk)
            }
            .multilineTextAlignment(.center)
            .ignoresSafeArea()
            countdown.frame(width: 160, height: 160)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var stacked: some View {
        let opponent = model.opponent
        return VStack(spacing: 0) {
            VStack(spacing: RatioSpace.s) {
                Text("\(DuelScope.title(of: model.moduleId ?? "")) · First to 3").ratioFont(.monoLabel).opacity(0.7)
                OpponentMark(opponent: opponent, size: 96)
                Text(opponent.name).ratioFont(.h1)
                Text(opponent.detail).ratioFont(.monoData).opacity(0.7)
            }
            .foregroundStyle(Color.ratioParchment)
            .multilineTextAlignment(.center)
            .padding(.horizontal, RatioSpace.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ratioInk)
            SwiftUI.TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let seconds = max(0, Int(((model.firstRoundAt ?? context.date).timeIntervalSince(context.date)).rounded(.up)))
                ZStack {
                    Circle().fill(Color.ratioPaper)
                    Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
                    Text(seconds > 0 ? "\(seconds)" : "v").ratioFont(.displayAccent)
                        .foregroundStyle(Color.ratioOxblood)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 120, height: 120)
                .padding(.vertical, -60)
                .zIndex(1)
                .accessibilityLabel(seconds > 0 ? "Starting in \(seconds)" : "Starting")
            }
            .frame(height: 0)
            VStack(spacing: RatioSpace.s) {
                ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 96)
                Text("You").ratioFont(.h1)
                Text("Rating \((model.view?.players[student.uid]?.rating ?? 1200).formatted())").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        // Two fixed halves; beyond this size they'd overlap.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// "Zara's connection dropped · 0:12" — the duel is claimed at 45 seconds.
private struct OpponentGoneBanner: View {
    let name: String
    let since: Date

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let gone = Int(context.date.timeIntervalSince(since))
            Label("\(name)'s connection dropped · \(gone / 60):\(String(format: "%02d", gone % 60)). The duel is yours at 0:45.",
                  systemImage: "wifi.slash")
                .ratioFont(.small)
                .ratioPanel(padding: RatioSpace.s)
        }
    }
}
