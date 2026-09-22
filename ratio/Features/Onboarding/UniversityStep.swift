import SwiftUI

/// screens/05-university.png — searchable list of law schools in England and Wales,
/// plus free text for anyone whose university isn't listed (PRD: "University").
struct UniversityStep: View {
    let model: OnboardingModel

    private enum Choice: Equatable {
        case listed(String)
        case other
    }

    @State private var query = ""
    @State private var choice: Choice?
    @State private var otherName: String
    @FocusState private var otherFieldFocused: Bool

    private let universities = UniversityDirectory.all
    private static let maxLength = 80

    init(model: OnboardingModel) {
        self.model = model
        _otherName = State(initialValue: model.profile.universityOther ?? "")
        if let id = model.profile.universityId {
            _choice = State(initialValue: .listed(id))
        } else if model.profile.universityOther != nil {
            _choice = State(initialValue: .other)
        }
    }

    var body: some View {
        OnboardingStepLayout(
            title: "Where do you study?",
            subtitle: "We use this for your university board. It's never shown with your surname.",
            canContinue: canContinue,
            onContinue: continueTapped
        ) {
            VStack(alignment: .leading, spacing: 16) {
                searchField
                list
                otherRow
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search universities").ratioFont(.monoLabel)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.ratioInk2)
                TextField("University or city", text: $query)
                    .ratioFont(.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.ratioInputBorder, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let matches = universities.filter { $0.matches(query) }
        if matches.isEmpty {
            Text("No matches. Choose “My university isn't listed” below.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(matches) { university in
                    universityRow(university)
                    if university.id != matches.last?.id {
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
    }

    private func universityRow(_ university: University) -> some View {
        let isSelected = choice == .listed(university.id)
        return Button {
            choice = .listed(university.id)
            otherFieldFocused = false
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(university.name).ratioFont(.body)
                    Text(university.city)
                        .ratioFont(.monoData)
                        .foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.ratioSunk : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var otherRow: some View {
        if choice == .other {
            RatioTextField("Your university", text: $otherName)
                .textContentType(.organizationName)
                .focused($otherFieldFocused)
                .onChange(of: otherName) { _, new in
                    if new.count > Self.maxLength { otherName = String(new.prefix(Self.maxLength)) }
                }
                .onAppear { otherFieldFocused = otherName.isEmpty }
        } else {
            Button {
                choice = .other
            } label: {
                Text("My university isn't listed")
                    .ratioFont(.body)
                    .italic()
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var trimmedOther: String {
        otherName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        guard !model.isSaving else { return false }
        switch choice {
        case .listed: return true
        case .other: return trimmedOther.count >= 2
        case nil: return false
        }
    }

    private func continueTapped() {
        Task {
            switch choice {
            case .listed(let id): await model.saveUniversity(id: id)
            case .other: await model.saveUniversity(other: trimmedOther)
            case nil: break
            }
        }
    }
}
