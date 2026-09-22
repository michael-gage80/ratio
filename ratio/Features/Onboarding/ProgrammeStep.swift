import SwiftUI

/// screens/04-programme.png — LLB is selectable; GDL, SQE and BPTC are "Soon", and
/// tapping one opts in to an email when it launches (PRD: "Programme").
struct ProgrammeStep: View {
    let model: OnboardingModel

    @State private var waitlist: Set<String>

    private let upcoming: [(id: String, name: String, detail: String)] = [
        ("gdl", "GDL", "Graduate Diploma in Law · conversion"),
        ("sqe", "SQE", "Solicitors Qualifying Examination"),
        ("bptc", "BPTC", "Bar training course"),
    ]

    init(model: OnboardingModel) {
        self.model = model
        _waitlist = State(initialValue: Set(model.profile.waitlist ?? []))
    }

    var body: some View {
        OnboardingStepLayout(
            title: "Which programme are you on?",
            subtitle: "Ratio starts with the LLB. Other routes are on the way — tap one to hear when it launches.",
            canContinue: !model.isSaving,
            onContinue: { Task { await model.saveProgramme(waitlist: waitlist) } }
        ) {
            VStack(spacing: 12) {
                row(name: "LLB", detail: "Bachelor of Laws · undergraduate", isSelected: true) {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .foregroundStyle(Color.ratioInk)
                }
                .accessibilityAddTraits(.isSelected)

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
                    .buttonStyle(.plain)
                    .accessibilityHint(isOnList ? "Stops the launch email" : "Emails you when it launches")
                }
            }
        }
    }

    private func row(name: String, detail: String, isSelected: Bool, @ViewBuilder accessory: () -> some View) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .ratioFont(.h3)
                    .foregroundStyle(isSelected ? Color.ratioInk : Color.ratioInk2)
                Text(detail)
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.ratioInk : Color.ratioRule, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(Rectangle())
    }
}
