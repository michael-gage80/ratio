import SwiftUI

/// The blocks on Today after the brief, which always comes first. Their order and which
/// are hidden are kept in `settings.homeOrder` and `settings.homeHidden`.
enum HomeCard: String, CaseIterable, Identifiable {
    case continueLearning, duel, streak, boards, news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueLearning: "Continue learning"
        case .duel: "Duel"
        case .streak: "This week"
        case .boards: "Boards"
        case .news: "The week in law"
        }
    }

    /// The saved order (unknown IDs dropped), minus hidden cards. A card added since the
    /// order was saved goes in at its default place (after the one before it by default).
    static func arranged(order: [String]?, hidden: [String]?) -> [HomeCard] {
        var all = (order ?? []).compactMap(HomeCard.init(rawValue:))
        for (index, card) in allCases.enumerated() where !all.contains(card) {
            let before = allCases[..<index].last { all.contains($0) }
            all.insert(card, at: before.flatMap { all.firstIndex(of: $0).map { $0 + 1 } } ?? 0)
        }
        return all.filter { !(hidden ?? []).contains($0.rawValue) }
    }
}

/// Edit home: drag to reorder, tap the eye to hide or show.
struct EditHomeSheet: View {
    @State var order: [HomeCard]
    @State var hidden: Set<HomeCard>
    let save: ([HomeCard], Set<HomeCard>) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Today's brief", systemImage: "lock")
                        .foregroundStyle(Color.ratioInk2)
                        .moveDisabled(true)
                    .listRowBackground(Color.ratioPaper)
                    ForEach(order) { card in
                        HStack(spacing: RatioSpace.s) {
                            Text(card.title).foregroundStyle(hidden.contains(card) ? Color.ratioInk2 : Color.ratioInk)
                            Spacer(minLength: 0)
                            Button {
                                if hidden.contains(card) { hidden.remove(card) } else { hidden.insert(card) }
                            } label: {
                                Image(systemName: hidden.contains(card) ? "eye.slash" : "eye").frame(width: 44, height: 44)
                            }
                            .buttonStyle(.ratioPress)
                            .accessibilityLabel(hidden.contains(card) ? "Show \(card.title)" : "Hide \(card.title)")
                        }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                    .listRowBackground(Color.ratioPaper)
                } footer: {
                    Text("The brief stays at the top.").ratioFont(.small)
                }
            }
            .ratioFont(.body)
            .foregroundStyle(Color.ratioInk)
            .scrollContentBackground(.hidden)
            .background(Color.ratioParchment.ignoresSafeArea())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit home")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save(order, hidden)
                        dismiss()
                    }
                }
            }
        }
    }
}
