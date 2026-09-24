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
        VStack(spacing: RatioSpace.l) {
            Spacer()
            ZStack {
                RatioRings(diameter: 170)
                RatioMark(size: 64, opticallyCentred: true)
            }
            Text("Reading your answers.")
                .ratioFont(.h2)
                .italic()
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                        Group {
                            if index < completedSteps {
                                Image(systemName: "checkmark").foregroundStyle(Color.ratioVerdigris)
                            } else if index == completedSteps && !failed {
                                ProgressView().controlSize(.small)
                            } else {
                                Circle().fill(Color.ratioRule).frame(width: 8, height: 8)
                            }
                        }
                        .frame(width: 24)
                        Text(step).ratioFont(.monoData)
                    }
                }
            }
            Spacer()
            VStack(spacing: RatioSpace.s) {
                if failed {
                    Text("We couldn't reach the server. Your answers are safe on this phone.")
                        .ratioFont(.small)
                        .multilineTextAlignment(.center)
                    RatioButton("Try again", style: .secondary) { Task { await submit() } }
                } else {
                    RatioButton("See your profile →", style: .secondary, isEnabled: headline != nil && completedSteps == steps.count) {
                        withAnimation(RatioMotion.reveal) { showsProfile = true }
                    }
                }
            }
        }
        .padding(RatioSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ratioPage()
        // A dark full-screen moment whatever the phone's appearance.
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
                withAnimation(RatioMotion.tap) { completedSteps = step }
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
            VStack(alignment: .leading, spacing: RatioSpace.m) {
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
                    .padding(.horizontal, RatioSpace.s)

                VStack(spacing: RatioSpace.xs) {
                    let range = Label { Text("Likely range") } icon: {
                        RoundedRectangle(cornerRadius: 2).fill(Color.ratioOxblood.opacity(0.16)).frame(width: 24, height: 12)
                    }
                    let estimate = Label { Text("Best estimate") } icon: {
                        Rectangle().fill(Color.ratioOxblood).frame(width: 24, height: 1.5)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: RatioSpace.m) { range; estimate }
                        VStack(alignment: .leading, spacing: RatioSpace.xs) { range; estimate }
                    }
                    .ratioFont(.monoData)
                    Text("The shaded area shows how sure we are. It narrows as you answer more.")
                        .ratioFont(.small)
                        .foregroundStyle(Color.ratioInk2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(RatioSpace.m)
        }
        .safeAreaInset(edge: .bottom) {
            RatioButton("Enter chambers", action: onContinue)
                .padding(RatioSpace.m)
                .background(Color.ratioParchment)
        }
        .ratioPage()
    }
}
