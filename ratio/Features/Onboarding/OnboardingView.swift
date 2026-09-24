import SwiftUI

/// The onboarding shell — back chevron, "02 / 06" counter and progress rule from
/// screens/03-name.png — around whichever step is current.
struct OnboardingView: View {
    let model: OnboardingModel

    @Environment(SessionStore.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .animation(RatioMotion.reveal, value: model.step)
        .ratioPage()
        .disabled(model.isSaving)
        .alert(model.errorMessage ?? "", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
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
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            RatioButton("Continue", style: .secondary, isEnabled: canContinue, action: onContinue)
                .padding(RatioSpace.m)
                .background(Color.ratioParchment)
        }
    }
}
