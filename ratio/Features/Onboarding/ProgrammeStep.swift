import SwiftUI

/// screens/04-programme.png — LLB and SQE1 are selectable; GDL and BPTC are "Soon", and
/// tapping one opts in to an email when it launches (PRD: "Programme").
struct ProgrammeStep: View {
    let model: OnboardingModel

    @State private var programme: Programme
    @State private var waitlist: Set<String>

    private let upcoming: [(id: String, name: String, detail: String)] = [
        ("gdl", "GDL", "Graduate Diploma in Law · conversion"),
        ("bptc", "BPTC", "Bar training course"),
    ]

    init(model: OnboardingModel) {
        self.model = model
        _programme = State(initialValue: model.programme)
        _waitlist = State(initialValue: Set(model.profile.waitlist ?? []).subtracting(["sqe"]))
    }

    var body: some View {
        OnboardingStepLayout(
            title: "Which programme are you on?",
            subtitle: "It sets which modules you see. You can switch in Settings. Other routes are on the way — tap one to hear when it launches.",
            canContinue: !model.isSaving,
            onContinue: { Task { await model.saveProgramme(programme, waitlist: waitlist) } }
        ) {
            VStack(spacing: RatioSpace.s) {
                ForEach(Programme.allCases) { option in
                    let isSelected = option == programme
                    Button { programme = option } label: {
                        row(name: option.title, detail: option.detail, isSelected: isSelected) {
                            Image(systemName: isSelected ? "record.circle" : "circle")
                                .font(.title2)
                                .foregroundStyle(isSelected ? Color.ratioInk : Color.ratioInk2)
                        }
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                ForEach(upcoming, id: \.id) { programme in
                    let isOnList = waitlist.contains(programme.id)
                    Button {
                        if isOnList { waitlist.remove(programme.id) } else { waitlist.insert(programme.id) }
                    } label: {
                        row(name: programme.name, detail: isOnList ? "We'll email you when it launches" : programme.detail, isSelected: false) {
                            if isOnList {
                                RatioTag("Notify me", icon: "checkmark", style: .filledDark)
                            } else {
                                RatioTag("Soon")
                            }
                        }
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityHint(isOnList ? "Stops the launch email" : "Emails you when it launches")
                }
            }
        }
    }

    private func row(name: String, detail: String, isSelected: Bool, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text(name)
                    .ratioFont(.h3)
                    .foregroundStyle(isSelected ? Color.ratioInk : Color.ratioInk2)
                Text(detail)
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            Spacer(minLength: RatioSpace.xs)
            accessory()
        }
        .padding(RatioSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
                .strokeBorder(isSelected ? Color.ratioInk : Color.ratioRule, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(Rectangle())
    }
}
