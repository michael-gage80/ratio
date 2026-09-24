import SwiftUI

/// Analysing (screens/08-analysing.png) then the first profile (09). The steps on
/// Analysing tick as the real work finishes — the Function re-grading and scoring the
/// answers — not on a timer (PRD: "not a fake delay").
struct DiagnosticResultsFlow: View {
    let finish: DiagnosticStep.Finish
    let onDone: (Headline) -> Void

    @State private var headline: Headline?
    @State private var completedSteps = 0
    @State private var failed = false
    @State private var showsProfile = false

    private var steps: [String] {
        if case .skipped = finish {
            ["Setting up your profile", "Drafting your first bands"]
        } else {
            ["Checking your answers", "Scoring recall, understanding and application", "Drafting your first profile"]
        }
    }

    var body: some View {
        if showsProfile, let headline {
            FirstProfileView(headline: headline) { onDone(headline) }
        } else {
            analysing
        }
    }

    private var analysing: some View {
        VStack(spacing: 40) {
            Spacer()
            ZStack {
                RatioRings(diameter: 170)
                RatioMark(size: 64, opticallyCentred: true)
            }
            Text("Reading your answers.")
                .ratioFont(.h2)
                .italic()
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 14) {
                        Group {
                            if index < completedSteps {
                                Image(systemName: "checkmark").foregroundStyle(Color.ratioVerdigris)
                            } else if index == completedSteps && !failed {
                                ProgressView().controlSize(.small)
                            } else {
                                Circle().fill(Color.ratioRule).frame(width: 8, height: 8)
                            }
                        }
                        .frame(width: 20)
                        Text(step).ratioFont(.monoData)
                    }
                }
            }
            Spacer()
            VStack(spacing: 12) {
                if failed {
                    Text("We couldn't reach the server. Your answers are safe on this phone.")
                        .ratioFont(.small)
                        .multilineTextAlignment(.center)
                    RatioButton("Try again", style: .secondary) { Task { await submit() } }
                } else {
                    RatioButton("See your profile →", style: .secondary, isEnabled: headline != nil && completedSteps == steps.count) {
                        withAnimation { showsProfile = true }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .environment(\.colorScheme, .dark)
        .task { await submit() }
    }

    private func submit() async {
        failed = false
        completedSteps = 0
        do {
            let result: Headline
            switch finish {
            case .answered(let responses): result = try await DiagnosticService.submit(responses)
            case .skipped: result = try await DiagnosticService.skip()
            }
            headline = result
            // Everything is done at this point; tick the remaining steps in turn so each
            // one can be read.
            for step in 1...steps.count {
                withAnimation { completedSteps = step }
                if step < steps.count { try? await Task.sleep(for: .milliseconds(350)) }
            }
        } catch {
            failed = true
        }
    }
}

/// screens/09-first-profile.png — the archetype and three scores with bands, framed as
/// a hypothesis (PRD: "First profile").
struct FirstProfileView: View {
    let headline: Headline
    let onContinue: () -> Void

    var body: some View {
        let archetype = Archetype(headline)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    RatioTag("Hypothesis · First profile", style: .tint(.ratioOxblood))
                    Spacer()
                    RatioSpotArt.openBook.view
                        .foregroundStyle(Color.ratioInk)
                        .frame(width: 88)
                }
                Text("The \(Text(archetype.name + ".").italic().foregroundStyle(Color.ratioOxblood))")
                    .ratioFont(.display)
                Text(archetype.summary)
                    .ratioFont(.h3)

                ProfileTriangle(headline: headline, highlight: Archetype.growthEdge(headline))
                    .padding(.horizontal, 12)

                VStack(spacing: 10) {
                    HStack(spacing: 20) {
                        Label { Text("Likely range") } icon: {
                            RoundedRectangle(cornerRadius: 2).fill(Color.ratioOxblood.opacity(0.16)).frame(width: 22, height: 12)
                        }
                        Label { Text("Best estimate") } icon: {
                            Rectangle().fill(Color.ratioOxblood).frame(width: 22, height: 1.5)
                        }
                    }
                    .ratioFont(.monoData)
                    Text("The shaded area shows how sure we are. It narrows as you answer more.")
                        .ratioFont(.small)
                        .foregroundStyle(Color.ratioInk2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                RatioButton("Enter chambers", action: onContinue)
            }
            .padding(24)
            .background(Color.ratioParchment)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }
}
