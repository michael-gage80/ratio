import SwiftUI

/// The onboarding shell — back chevron, "02 / 06" counter and progress rule from
/// screens/03-name.png — around whichever step is current. On iPad, a "Getting set up"
/// panel lists the steps on the left and the step sits on the right
/// (screens/iPad/1-onboarding).
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingLayout(model: model)
            .ratioMeasuresWidth()
            .ratioPage()
            .disabled(model.isSaving)
            .alert(model.errorMessage ?? "", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
    }
}

private struct OnboardingLayout: View {
    let model: OnboardingModel

    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ratioWidth) private var width

    var body: some View {
        Group {
            if width.isCompact {
                VStack(spacing: 0) {
                    header
                    stepView
                }
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        stepList
                            .frame(width: proxy.size.width * 0.35)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(Color.ratioSunk.ignoresSafeArea())
                        VStack(alignment: .leading, spacing: 0) {
                            backRow
                            stepView
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .animation(RatioMotion.reveal, value: model.step)
    }

    private var stepView: some View {
        Group {
            switch model.step {
            case .dateOfBirth: DateOfBirthStep(model: model)
            case .name: NameStep(model: model, suggestedName: session.suggestedName)
            case .programme: ProgrammeStep(model: model)
            case .university: UniversityStep(model: model)
            case .modules: ModulesStep(model: model)
            case .diagnostic: DiagnosticStep(onboarding: model)
            case nil: EmptyView()
            }
        }
        .id(model.step)
        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
    }

    // MARK: iPad

    /// "Getting set up": each step, done, now or still to come, with the progress rule.
    private var stepList: some View {
        let current = model.step?.rawValue ?? OnboardingModel.totalSteps + 1
        let titles = ["Date of birth", "Name", "Programme", "University", "Modules", "Diagnostic"]
        return VStack(alignment: .leading, spacing: RatioSpace.l) {
            Text("Ratio\(Text(".").foregroundStyle(Color.ratioOxblood))").ratioFont(.h1).italic()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                HStack {
                    Text("Getting set up").ratioFont(.monoLabel)
                    Spacer()
                    Text(String(format: "%02d / %02d", min(current, OnboardingModel.totalSteps), OnboardingModel.totalSteps)).ratioFont(.monoData)
                }
                .foregroundStyle(Color.ratioInk2)
                progressRule(step: min(current, OnboardingModel.totalSteps))
            }
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    let number = index + 1
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                        Text(String(format: "%02d", number)).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                        Text(title)
                            .ratioFont(.h2)
                            .italic(number == current)
                            .foregroundStyle(number > current ? Color.ratioInk2 : Color.ratioInk)
                        Spacer(minLength: RatioSpace.xs)
                        Text(number < current ? "Done ✓" : number == current ? "Now" : "")
                            .ratioFont(.monoLabel)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    .padding(.vertical, RatioSpace.xs)
                    .padding(.leading, RatioSpace.s)
                    .overlay(alignment: .leading) {
                        if number == current { Rectangle().fill(Color.ratioOxblood).frame(width: 3) }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(number < current ? "Done" : number == current ? "Current step" : "")
                }
            }
            Spacer(minLength: RatioSpace.m)
            RatioSpotArt.quill.view
                .frame(width: 160)
                .foregroundStyle(Color.ratioInk)
                .accessibilityHidden(true)
            Text("Six short steps, then a brief written for you.").ratioFont(.h3).italic()
        }
        .padding(RatioSpace.xl)
    }

    @ViewBuilder
    private var backRow: some View {
        HStack {
            if model.canGoBack {
                Button { model.goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .ratioFont(.monoLabel)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, RatioSpace.m)
        .padding(.top, RatioSpace.s)
        .ratioReadableWidth(720)
    }

    private func progressRule(step number: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ratioRule)
                Capsule()
                    .fill(Color.ratioOxblood)
                    .frame(width: proxy.size.width * CGFloat(number) / CGFloat(OnboardingModel.totalSteps))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private var header: some View {
        let number = model.step?.rawValue ?? OnboardingModel.totalSteps
        return VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(spacing: RatioSpace.s) {
                if model.canGoBack {
                    Button {
                        model.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityLabel("Back")
                }
                Text(String(format: "%02d / %02d", number, OnboardingModel.totalSteps))
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
                    .accessibilityLabel("Step \(number) of \(OnboardingModel.totalSteps)")
                Spacer()
            }
            .frame(minHeight: 44)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ratioSunk)
                    Capsule()
                        .fill(Color.ratioOxblood)
                        .frame(width: proxy.size.width * CGFloat(number) / CGFloat(OnboardingModel.totalSteps))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, RatioSpace.m)
        .padding(.top, RatioSpace.xs)
    }
}

/// Title, optional subtitle, the step's controls, and a pinned Continue button.
struct OnboardingStepLayout<Content: View>: View {
    let title: String
    var subtitle: String?
    let canContinue: Bool
    let onContinue: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.l) {
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    Text(title).ratioFont(.h1).accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .ratioFont(.body)
                            .foregroundStyle(Color.ratioInk2)
                    }
                }
                content
            }
            .padding(RatioSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            // iPad: one readable column (no change on iPhone).
            .ratioReadableWidth(720)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: RatioSpace.s) {
                KeyHint(keys: "⌘↩", label: "Continue")
                RatioButton("Continue", style: .secondary, isEnabled: canContinue, action: onContinue)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(RatioSpace.m)
            .ratioReadableWidth(720)
            .background(Color.ratioParchment)
        }
    }
}
