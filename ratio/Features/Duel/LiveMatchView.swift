import FirebaseFunctions
import SwiftUI

/// A live match against another student, full screen: versus and countdown, the
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
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
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
            waiting("Connecting to the match…")
        case .countdown:
            LiveVersus(model: model)
        case .round:
            VStack(spacing: 0) {
                HStack {
                    Button { confirmingLeave = true } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .foregroundStyle(Color.ratioInk2)
                    .accessibilityLabel("Leave the match")
                    Spacer()
                    Text("\(Module(rawValue: model.moduleId ?? "")?.title ?? "") · Live").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                .padding(.horizontal, 12)
                if let since = model.opponentGoneSince {
                    OpponentGoneBanner(name: model.opponent.name, since: since)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                DuelRoundView(model: model)
            }
            .confirmationDialog("Leave the match?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave — \(model.opponent.name) wins", role: .destructive) {
                    Task { await model.leave() }
                }
                Button("Keep playing", role: .cancel) {}
            } message: {
                Text("Leaving forfeits the match and counts as a loss.")
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
            VStack(spacing: 20) {
                Text("This match isn't available.").ratioFont(.h3)
                RatioButton("Close", style: .secondary) { dismiss() }
            }
            .padding(32)
        }
    }

    private func waiting(_ text: String) -> some View {
        VStack(spacing: 24) {
            RatioRings(diameter: 140)
            Text(text).ratioFont(.h3).italic()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }

    /// Rematch against a student is an async challenge: they get 24 hours to play.
    private func challenge(_ record: DuelRecord) {
        guard let opponent = record.opponent.uid, let module = Module(rawValue: record.moduleId) else { return }
        Task {
            do {
                try await DuelService.createChallenge(opponent: opponent, module: module, seconds: record.limitMs / 1000)
                challengeSent = "\(record.opponent.name) has 24 hours to play their half. You'll find it under Waiting for you."
            } catch {
                challengeSent = (error as NSError).localizedDescription
            }
        }
    }
}

/// Screen 34 for a live match: both players and a countdown to the first question.
private struct LiveVersus: View {
    let model: LiveMatchModel

    @Environment(StudentStore.self) private var student

    var body: some View {
        let opponent = model.opponent
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("\(Module(rawValue: model.moduleId ?? "")?.title ?? "") · First to 3").ratioFont(.monoLabel).opacity(0.7)
                OpponentMark(opponent: opponent, size: 96)
                Text(opponent.name).ratioFont(.h1)
                Text(opponent.detail).ratioFont(.monoData).opacity(0.7)
            }
            .foregroundStyle(Color.ratioParchment)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ratioInk)
            SwiftUI.TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let seconds = max(0, Int(((model.firstRoundAt ?? context.date).timeIntervalSince(context.date)).rounded(.up)))
                ZStack {
                    Circle().fill(Color.ratioPaper)
                    Circle().strokeBorder(Color.ratioInk, lineWidth: 1.5)
                    Text(seconds > 0 ? "\(seconds)" : "v").font(.custom("NewsreaderDisplay-Italic", size: 56, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ratioOxblood)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 120, height: 120)
                .padding(.vertical, -60)
                .zIndex(1)
                .accessibilityLabel(seconds > 0 ? "Starting in \(seconds)" : "Starting")
            }
            .frame(height: 0)
            VStack(spacing: 12) {
                ProfilePhoto(uid: student.uid, initial: student.profile.displayName ?? "?", version: student.profile.avatarVersion, size: 96)
                Text("You").ratioFont(.h1)
                Text("Rating \((model.view?.players[student.uid]?.rating ?? 1200).formatted())").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// "Zara's connection dropped · 0:12" — the match is claimed at 45 seconds.
private struct OpponentGoneBanner: View {
    let name: String
    let since: Date

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            let gone = Int(context.date.timeIntervalSince(since))
            Label("\(name)'s connection dropped · \(gone / 60):\(String(format: "%02d", gone % 60)). The match is yours at 0:45.",
                  systemImage: "wifi.slash")
                .ratioFont(.small)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
