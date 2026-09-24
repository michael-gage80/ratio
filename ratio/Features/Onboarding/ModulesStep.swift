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
            title: "Your modules",
            canContinue: !modules.isEmpty && !model.isSaving,
            onContinue: {
                Task { await model.saveModules(modules) }
            }
        ) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Modules this year").ratioFont(.monoLabel)
                        Spacer()
                        Text("\(modules.count) of \(Module.allCases.count) selected")
                            .ratioFont(.monoData)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    moduleList
                    Text("These set the order of your lessons. Change them any time in Settings.")
                        .ratioFont(.monoData)
                        .foregroundStyle(Color.ratioInk2)
                }
            }
        }
    }

    private var moduleList: some View {
        VStack(spacing: 0) {
            ForEach(Module.allCases) { module in
                let isSelected = modules.contains(module)
                Button {
                    if isSelected { modules.remove(module) } else { modules.insert(module) }
                } label: {
                    HStack {
                        Text(module.title).ratioFont(.h3)
                        Spacer()
                        checkbox(isSelected)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                if module != Module.allCases.last {
                    Divider().overlay(Color.ratioRule)
                }
            }
        }
        .background(Color.ratioPaper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.ratioRule, lineWidth: 1)
        }
    }

    private func checkbox(_ isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isOn ? Color.ratioInk : Color.clear)
            .strokeBorder(isOn ? Color.ratioInk : Color.ratioInputBorder, lineWidth: 1)
            .frame(width: 26, height: 26)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.ratioParchment)
                }
            }
            .accessibilityHidden(true)
    }
}
