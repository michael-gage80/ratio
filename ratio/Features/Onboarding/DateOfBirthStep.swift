import SwiftUI

/// The 18+ age gate (PRD: "Date of birth is self-declared at sign-up; under-18s are
/// blocked"). Comes first, so nothing else is collected from someone under 18.
struct DateOfBirthStep: View {
    let model: OnboardingModel

    @Environment(SessionStore.self) private var session
    @State private var date = Calendar.current.date(byAdding: .year, value: -19, to: .now) ?? .now
    @State private var hasChosen = false

    private let range: ClosedRange<Date> = {
        let earliest = Calendar.current.date(from: DateComponents(year: 1920, month: 1, day: 1)) ?? .distantPast
        return earliest...Date.now
    }()

    var body: some View {
        OnboardingStepLayout(
            title: "When were you born?",
            subtitle: "Ratio is for students aged 18 and over. We keep only your birth year.",
            canContinue: hasChosen && !model.isSaving,
            onContinue: {
                Task {
                    if await model.saveDateOfBirth(date) == .underage {
                        await session.removeUnderageAccount(uid: model.uid)
                    }
                }
            }
        ) {
            DatePicker("Date of birth", selection: $date, in: range, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                // Continue stays off until the wheel has been moved, so nobody passes the
                // gate by accepting a default.
                .onChange(of: date) { hasChosen = true }
        }
    }
}
