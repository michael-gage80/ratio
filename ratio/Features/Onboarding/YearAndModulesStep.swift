import SwiftUI

/// screens/06-year-and-modules.png — year of study and the modules taken this year,
/// which set the order of the Pathway (PRD: "Year + modules").
struct YearAndModulesStep: View {
    let model: OnboardingModel

    @State private var year: Int?
    @State private var modules: Set<Module>

    init(model: OnboardingModel) {
        self.model = model
        _year = State(initialValue: model.profile.year)
        _modules = State(initialValue: Set(model.profile.modules ?? []))
    }

    var body: some View {
        OnboardingStepLayout(
            title: "Your year and modules",
            canContinue: year != nil && !modules.isEmpty && !model.isSaving,
            onContinue: {
                guard let year else { return }
                Task { await model.saveYearAndModules(year: year, modules: modules) }
            }
        ) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Year of study").ratioFont(.monoLabel)
                    RatioSegmentedControl(
                        options: [(Optional(1), "Year 1"), (Optional(2), "Year 2"), (Optional(3), "Year 3")],
                        selection: $year
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Modules this year").ratioFont(.monoLabel)
                        Spacer()
                        Text("\(modules.count) of \(Module.allCases.count) selected")
                            .ratioFont(.monoData)
                            .foregroundStyle(Color.ratioInk2)
                    }
                    moduleList
                    Text("These set the order of your Pathway. Change them any time in Settings.")
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
