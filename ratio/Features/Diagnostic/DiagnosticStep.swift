import SwiftUI

/// Onboarding step 6 — screens/07-diagnostic.png. Six adaptive questions (fewer if
/// the chosen modules hold fewer), each with feedback, then Analysing and the first
/// profile. Can be skipped for a default profile with wide bands.
struct DiagnosticStep: View {
    let onboarding: OnboardingModel

    @State private var diagnostic: DiagnosticModel?
    @State private var loadFailed = false
    @State private var confirmingSkip = false
    @State private var finish: Finish?

    /// How the diagnostic ended, which decides what Analysing submits.
    enum Finish: Identifiable {
        case answered([ItemResponse]), skipped
        var id: String { if case .skipped = self { "skipped" } else { "answered" } }
    }

    var body: some View {
        Group {
            if let diagnostic {
                questions(diagnostic)
            } else if loadFailed {
                RatioErrorState(message: "The diagnostic didn't load.") { load() }
                    .padding(RatioSpace.m)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard diagnostic == nil else { return }
            load()
        }
        .confirmationDialog("Skip the diagnostic?", isPresented: $confirmingSkip, titleVisibility: .visible) {
            Button("Skip — start with wide bands") { finish = .skipped }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("You'll start with a default profile. It sharpens as you play.")
        }
        .fullScreenCover(item: $finish) { finish in
            DiagnosticResultsFlow(finish: finish) { headline in
                onboarding.finishDiagnostic(headline: headline)
            }
        }
    }

    private func load() {
        loadFailed = false
        do {
            let model = DiagnosticModel(modules: onboarding.profile.modules ?? [], seed: onboarding.uid, bank: try DiagnosticBank.load())
            diagnostic = model
            // Modules added after the diagnostic bank have no questions yet: start
            // those students on the default profile, as if they'd skipped.
            if model.total == 0 { finish = .skipped }
        } catch {
            loadFailed = true
        }
    }

    private func questions(_ diagnostic: DiagnosticModel) -> some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    let about = Text("\(diagnostic.total) questions · about 2 minutes · no penalties")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    let count = Text("Q \(diagnostic.number) of \(diagnostic.total)")
                        .ratioFont(.monoData)
                    ViewThatFits(in: .horizontal) {
                        HStack { about; Spacer(minLength: RatioSpace.xs); count }
                        VStack(alignment: .leading, spacing: RatioSpace.xxs) { count; about }
                    }
                    .id("top")

                    if let item = diagnostic.current {
                        RatioTag(item.skill.title, style: .outline)
                        ItemInteractionView(
                            item: item,
                            lockedResponse: diagnostic.lastAnswerCorrect == nil ? nil : diagnostic.responses.last,
                            onLock: { diagnostic.lock($0) }
                        )
                        .id(item.id)

                        if diagnostic.lastAnswerCorrect != nil {
                            RatioButton(diagnostic.isFinished ? "See your profile →" : "Next →", style: .secondary) {
                                if diagnostic.isFinished {
                                    finish = .answered(diagnostic.responses)
                                } else {
                                    diagnostic.advance()
                                    scroll.scrollTo("top", anchor: .top)
                                }
                            }
                        }
                    }

                    if diagnostic.lastAnswerCorrect == nil {
                        VStack(spacing: RatioSpace.xxs) {
                            Button("Skip the diagnostic") { confirmingSkip = true }
                                .ratioFont(.monoLabel)
                                .underline()
                                .frame(minHeight: 44)
                            Text("You'll start with a default profile and wide bands.")
                                .ratioFont(.small)
                                .italic()
                                .foregroundStyle(Color.ratioInk2)
                        }
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, RatioSpace.xs)
                    }
                }
                .padding(RatioSpace.m)
            }
            .holdsStillWhileReordering()
            .scrollDismissesKeyboard(.interactively)
        }
        .ratioFeedback(trigger: diagnostic.lastAnswerCorrect) { _, correct in
            switch correct {
            case true: .success
            case false: .error
            default: nil
            }
        }
    }
}
