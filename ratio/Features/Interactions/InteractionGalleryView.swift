import SwiftUI

#if DEBUG
/// Phase 7 verification screen: one real item of every type from the lessons, to try
/// each one right and wrong, with every IRAC scaffold level. Debug builds only.
struct InteractionGalleryView: View {
    @Environment(ContentStore.self) private var content
    @State private var index = 0
    @State private var iracLevel = 1
    @State private var locked: ItemResponse?

    /// The first item of each type found across the lessons, in the board's order.
    private var items: [(item: Item, lessonId: String, module: Module)] {
        let order = ["recallFirst", "quickCheck", "thresholdSlider", "tapTheFact", "irac", "sequence",
                     "mcqWithTrap", "highlightTheRatio", "distinguishTheCase", "statuteParser", "applyTheRule"]
        let all = Module.allCases.flatMap { module in
            content.lessons(in: module).flatMap { lesson in
                (lesson.parts.map(\.interaction) + lesson.testPool).map { ($0, lesson.id, module) }
            }
        }
        return order.compactMap { type in all.first { $0.0.type == type } }
    }

    var body: some View {
        let entries = items
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("\(index + 1) of \(entries.count) · \(entries[safe: index]?.item.typeTitle ?? "")")
                        .ratioFont(.monoLabel)
                    Spacer()
                    Button("Previous") { move(-1, count: entries.count) }.disabled(index == 0)
                    Button("Next") { move(1, count: entries.count) }.disabled(index >= entries.count - 1)
                }
                if let entry = entries[safe: index] {
                    if entry.item.type == "irac" {
                        RatioSegmentedControl(options: (1...4).map { ($0, "Level \($0)") }, selection: $iracLevel)
                            .onChange(of: iracLevel) { locked = nil }
                    }
                    let decoys = content.iracDecoys(for: entry.item.id, in: entry.module)
                    ItemInteractionView(
                        item: entry.item,
                        lockedResponse: locked,
                        context: InteractionContext(iracLevel: iracLevel, decoyFacts: decoys.facts, decoyRules: decoys.rules, lessonId: entry.lessonId)
                    ) { locked = $0 }
                    .id("\(entry.item.id)-\(iracLevel)")
                    if let locked {
                        Label(entry.item.isCorrect(locked) ? "Graded correct" : "Graded not quite", systemImage: "info.circle")
                            .ratioFont(.monoLabel)
                        RatioButton("Try again", style: .tertiary) { self.locked = nil }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .navigationTitle("Interaction gallery")
        .toolbarTitleDisplayMode(.inline)
    }

    private func move(_ step: Int, count: Int) {
        index = max(0, min(count - 1, index + step))
        locked = nil
    }
}
#endif
