import SwiftUI

/// screens/03-name.png — first name plus an optional surname initial; other players
/// see e.g. "Zara K." (PRD: "Name").
struct NameStep: View {
    let model: OnboardingModel

    @State private var firstName: String
    @State private var initial: String

    private static let maxLength = 40

    init(model: OnboardingModel, suggestedName: String?) {
        self.model = model
        // Prefer what they've already saved; otherwise what Apple or Google gave us.
        let parts = (suggestedName ?? "").split(separator: " ")
        _firstName = State(initialValue: model.profile.displayName ?? parts.first.map(String.init) ?? "")
        _initial = State(initialValue: model.profile.initial ?? parts.dropFirst().last?.prefix(1).uppercased() ?? "")
    }

    var body: some View {
        OnboardingStepLayout(
            title: "What should we call you?",
            subtitle: "We'll use your first name in your briefs. Other players only see your first name and an initial.",
            canContinue: !trimmedName.isEmpty && !model.isSaving,
            onContinue: {
                Task { await model.saveName(firstName: trimmedName, initial: initial.isEmpty ? nil : initial) }
            }
        ) {
            VStack(alignment: .leading, spacing: 24) {
                RatioTextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .onChange(of: firstName) { _, new in
                        if new.count > Self.maxLength { firstName = String(new.prefix(Self.maxLength)) }
                    }

                RatioTextField("Surname initial (optional)", text: $initial)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 180)
                    .onChange(of: initial) { _, new in
                        // Keep one letter, even if autofill supplies a whole surname.
                        let letter = new.first(where: \.isLetter).map { String($0).uppercased() } ?? ""
                        if letter != new { initial = letter }
                    }

                preview
            }
        }
    }

    private var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var publicName: String {
        [trimmedName, initial.isEmpty ? nil : "\(initial)."].compactMap { $0 }.joined(separator: " ")
    }

    private var preview: some View {
        HStack(spacing: 14) {
            RatioAvatar(initial: trimmedName.isEmpty ? "?" : trimmedName, seed: model.uid, size: 40)
            Text("Other players see: \(Text(publicName.isEmpty ? "—" : publicName).foregroundStyle(Color.ratioInk))")
                .ratioFont(.monoData)
                .textCase(.uppercase)
                .foregroundStyle(Color.ratioInk2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
