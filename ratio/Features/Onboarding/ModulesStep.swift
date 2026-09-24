import SwiftUI

/// screens/06-year-and-modules.png, without the year: the modules taken this year, which
/// set the order of Lessons. Year of study is optional and added later on Me.
struct ModulesStep: View {
    let model: OnboardingModel

    @State private var modules: Set<Module>

    init(model: OnboardingModel) {
        self.model = model
        _modules = State(initialValue: Set(model.profile.modules ?? []))
    }

    var body: some View {
        OnboardingStepLayout(
            title: "Which modules are you taking?",
            subtitle: "They set the order of your lessons. You can change them any time in Settings.",
            canContinue: !modules.isEmpty && !model.isSaving,
            onContinue: {
                Task { await model.saveModules(modules) }
            }
        ) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("Modules this year").ratioFont(.monoLabel)
                        Spacer()
                        selectedCount
                    }
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text("Modules this year").ratioFont(.monoLabel)
                        selectedCount
                    }
                }
                moduleList
            }
        }
    }

    private var selectedCount: some View {
        Text("\(modules.count) of \(Module.allCases.count) selected")
            .ratioFont(.monoData)
            .foregroundStyle(Color.ratioInk2)
    }

    private var moduleList: some View {
        VStack(spacing: 0) {
            ForEach(Module.allCases) { module in
                let isSelected = modules.contains(module)
                Button {
                    if isSelected { modules.remove(module) } else { modules.insert(module) }
                } label: {
                    HStack(spacing: RatioSpace.s) {
                        Text(module.title).ratioFont(.h3).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        checkbox(isSelected)
                    }
                    .padding(RatioSpace.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                if module != Module.allCases.last {
                    Divider().overlay(Color.ratioRule)
                }
            }
        }
        .background(Color.ratioPaper)
        .clipShape(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
                .strokeBorder(Color.ratioRule, lineWidth: 1)
        }
    }

    private func checkbox(_ isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? Color.ratioInk : Color.clear)
            .strokeBorder(isOn ? Color.ratioInk : Color.ratioInputBorder, lineWidth: 1)
            .frame(width: 24, height: 24)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.footnote)
                        .foregroundStyle(Color.ratioParchment)
                }
            }
            .accessibilityHidden(true)
    }
}
