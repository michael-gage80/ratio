import SwiftUI

/// Which IRAC scaffold a student sees (PRD: "Worked examples, then fading… IRAC builder
/// with 4 scaffold levels"). Chosen from the lower edge of the student's application
/// estimate for the topic, so support only fades once they're both strong and
/// consistently so: a new or uncertain student starts on the worked example.
enum IRACScaffold {
    static func level(for application: Estimate?) -> Int {
        guard let application else { return 1 }
        let lowerEdge = application.score - application.band
        switch lowerEdge {
        case ..<35: return 1
        case ..<50: return 2
        case ..<62: return 3
        default: return 4
        }
    }
}

/// Shows an IRAC item at the right scaffold level.
struct IRACInteraction: View {
    let itemId: String
    let facts: [String]
    let answer: Item.IRACAnswer
    let level: Int
    let decoyFacts: [String]
    let decoyRules: [String]
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    var body: some View {
        if level <= 1 {
            IRACWorkedExample(itemId: itemId, facts: facts, answer: answer, locked: locked, onLock: onLock)
        } else {
            IRACBuilder(itemId: itemId, facts: facts, answer: answer, level: min(level, 4),
                        decoyFacts: decoyFacts, decoyRules: decoyRules, locked: locked, onLock: onLock)
        }
    }
}

// MARK: - Level 1: worked example

private struct IRACWorkedExample: View {
    let itemId: String
    let facts: [String]
    let answer: Item.IRACAnswer
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Worked example · scaffold 1 of 4")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            IRACFactsList(facts: facts)
            IRACModelAnswer(answer: answer)
            if locked == nil {
                RatioButton("I've read the worked example", style: .secondary) {
                    onLock(ItemResponse(itemId: itemId, selfMarkedCorrect: true))
                }
            }
        }
    }
}

// MARK: - Levels 2–4: the builder

/// Board cell 05 ("IRAC builder · structuring an answer, with fading support"): slots for
/// Issue, Rule, Application and Conclusion; a tray of fact chips including decoys. Tap a
/// chip to place it and tap it again to take it back — the non-drag route that works
/// with VoiceOver (PRD: Accessibility). On iPad (screens/iPad/3-lesson/05) the material
/// sits on the left and the four slots on the right: draw a link from a card's dot to
/// the Application slot with Apple Pencil or a finger, or tap the card — the same thing.
private struct IRACBuilder: View {
    let itemId: String
    let facts: [String]
    let answer: Item.IRACAnswer
    let level: Int
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    /// Real facts first (0..<facts.count), then decoys.
    private let tray: [String]
    /// The right rule and up to two decoys, in a stable shuffled order.
    private let ruleOptions: [String]

    @State private var placed: [Int] = []
    @State private var chosenRule: Int?
    @State private var issue = ""
    @State private var rule = ""
    @State private var application = ""
    @State private var conclusion = ""
    @State private var isChecking = false
    @Environment(\.ratioWidth) private var width
    // iPad drawn links: where each card and the Application slot are, and a link being drawn.
    @State private var cardFrames: [Int: CGRect] = [:]
    @State private var slotFrame: CGRect = .zero
    @State private var drawing: (card: Int, point: CGPoint)?
    private static let space = "irac-links"

    init(itemId: String, facts: [String], answer: Item.IRACAnswer, level: Int, decoyFacts: [String], decoyRules: [String],
         locked: ItemResponse?, onLock: @escaping (ItemResponse) -> Void) {
        self.itemId = itemId
        self.facts = facts
        self.answer = answer
        self.level = level
        self.locked = locked
        self.onLock = onLock
        self.tray = facts + decoyFacts.prefix(2)
        var generator = SeededGenerator(seed: itemId)
        self.ruleOptions = ([answer.rule] + decoyRules.prefix(2)).shuffled(using: &generator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Scaffold \(level) of 4").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: .infinity, alignment: width.isCompact ? .leading : .trailing)

            Group {
            if level < 4 && !width.isCompact {
                // iPad: material on the left, the four slots on the right.
                ColumnsLayout(fraction: 0.45, spacing: RatioSpace.xl) {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) { linkCards }
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        slot("Issue") { Text(answer.issue).ratioFont(.small) }
                        if level == 2 {
                            slot("Rule") { Text(answer.rule).ratioFont(.small) }
                        } else {
                            ruleChoice
                        }
                        placedSlot
                            .overlay(alignment: .topLeading) { linkDot(filled: !placed.isEmpty).offset(x: -6, y: RatioSpace.m) }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slotFrame = $0 }
                        RatioTextField("Conclusion", placeholder: "What a court would likely decide…", text: $conclusion, axis: .vertical)
                    }
                }
                .coordinateSpace(name: Self.space)
                .overlay { links.allowsHitTesting(false) }
            } else if level == 4 {
                RatioTextField("Issue", placeholder: "The question the facts raise…", text: $issue, axis: .vertical)
                RatioTextField("Rule", placeholder: "The test that applies…", text: $rule, axis: .vertical)
                RatioTextField("Application", placeholder: "Apply the rule to these facts…", text: $application, axis: .vertical)
                RatioTextField("Conclusion", placeholder: "What a court would likely decide…", text: $conclusion, axis: .vertical)
            } else {
                slot("Issue") { Text(answer.issue).ratioFont(.small) }
                if level == 2 {
                    slot("Rule") { Text(answer.rule).ratioFont(.small) }
                } else {
                    ruleChoice
                }
                applicationSlot
                RatioTextField("Conclusion", placeholder: "What a court would likely decide…", text: $conclusion, axis: .vertical)
            }
            }
            // Inputs freeze once checking starts; the verdict buttons below stay live.
            .disabled(isChecking || locked != nil)

            if let locked {
                outcome(locked)
            } else if isChecking {
                FreeTextVerdictView(studentAnswer: writtenAnswer, modelAnswer: modelForWrittenPart) { lock(writtenPartCovered: $0) }
            } else {
                RatioButton("Check", isEnabled: canCheck) { isChecking = true }
                    .keyboardShortcut(.return, modifiers: .command)
                if KeyboardMonitor.shared.isConnected { KeyHint(keys: "⌘↩", label: "Check") }
            }
        }
    }

    // MARK: Parts

    private func slot(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text(title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            content()
        }
        .ratioPanel()
    }

    private var ruleChoice: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Rule · choose the test that applies").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(Array(ruleOptions.enumerated()), id: \.offset) { index, option in
                RatioOptionRow(text: option, state: ruleState(index), action: locked == nil && !isChecking ? { chosenRule = index } : nil)
            }
        }
    }

    private func ruleState(_ index: Int) -> RatioOptionState {
        let isRight = ruleOptions[index] == answer.rule
        guard locked != nil else { return index == chosenRule ? .selected : .default }
        if isRight { return .correct }
        return index == chosenRule ? .incorrect : .default
    }

    private var applicationSlot: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            placedSlot
            if locked == nil && !isChecking {
                VStack(alignment: .leading, spacing: RatioSpace.xs) { trayChips }
            }
        }
    }

    /// The Application slot, holding the placed facts.
    private var placedSlot: some View {
        slot("Application · the facts that decide it") {
            if placed.isEmpty {
                Text(width.isCompact ? "Drag or tap facts below to place them here." : "Tap or drag a card on the left to place it here.")
                    .ratioFont(.small).italic().foregroundStyle(Color.ratioInk2)
            }
            ForEach(placed, id: \.self) { index in
                chip(index, isPlaced: true)
            }
        }
        .dropDestination(for: String.self) { dropped, _ in place(dropped, in: true) }
    }

    /// The tray: the facts not yet placed, decoys among them.
    @ViewBuilder
    private var trayChips: some View {
        Text(width.isCompact ? "Tray · \(tray.count) chips, \(tray.count - facts.count) decoys" : "Material · \(tray.count) cards, \(tray.count - facts.count) decoys")
            .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
        if locked == nil && !isChecking {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                ForEach(trayOrder.filter { !placed.contains($0) }, id: \.self) { index in
                    chip(index, isPlaced: false)
                }
            }
            .dropDestination(for: String.self) { dropped, _ in place(dropped, in: false) }
        }
    }

    // MARK: iPad drawn links

    /// Every card stays on the left; linked ones show it, and a curve runs to the slot.
    @ViewBuilder
    private var linkCards: some View {
        Text("Material · \(tray.count) cards, \(tray.count - facts.count) decoys")
            .ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
        ForEach(trayOrder, id: \.self) { index in
            chip(index, isPlaced: placed.contains(index))
                .overlay(alignment: .trailing) { linkDot(filled: placed.contains(index)).offset(x: 6) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { cardFrames[index] = $0 }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.space))
                        .onChanged { value in
                            guard locked == nil, !isChecking else { return }
                            drawing = (index, value.location)
                        }
                        .onEnded { value in
                            defer { drawing = nil }
                            guard locked == nil, !isChecking, slotFrame.insetBy(dx: -RatioSpace.m, dy: -RatioSpace.m).contains(value.location),
                                  !placed.contains(index) else { return }
                            withAnimation(RatioMotion.tap) { placed.append(index) }
                        }
                )
        }
        Text("Draw from a card's dot to Application with Apple Pencil or a finger, or tap the card.")
            .ratioFont(.small).italic().foregroundStyle(Color.ratioInk2)
    }

    private func linkDot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.ratioInk : Color.ratioPaper)
            .overlay(Circle().strokeBorder(Color.ratioInk2, lineWidth: 1.5))
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    /// Ink curves from each linked card to the Application slot, and the one being drawn.
    private var links: some View {
        let target = CGPoint(x: slotFrame.minX, y: slotFrame.minY + RatioSpace.m + 6)
        return Canvas { context, _ in
            guard slotFrame != .zero else { return }
            for index in placed {
                guard let card = cardFrames[index] else { continue }
                context.stroke(curve(from: CGPoint(x: card.maxX + 6, y: card.midY), to: target), with: .color(.ratioInk), lineWidth: 1.5)
            }
            if let drawing, let card = cardFrames[drawing.card] {
                context.stroke(curve(from: CGPoint(x: card.maxX + 6, y: card.midY), to: drawing.point), with: .color(.ratioOxblood),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }

    private func curve(from start: CGPoint, to end: CGPoint) -> Path {
        Path { path in
            let bend = max(40, abs(end.x - start.x) / 2)
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y), control2: CGPoint(x: end.x - bend, y: end.y))
        }
    }

    /// A chip dragged into the application (or back to the tray).
    private func place(_ dropped: [String], in application: Bool) {
        guard locked == nil, !isChecking, let index = dropped.first.flatMap(Int.init), tray.indices.contains(index) else { return }
        if application, !placed.contains(index) { placed.append(index) }
        if !application { placed.removeAll { $0 == index } }
    }

    private func chip(_ index: Int, isPlaced: Bool) -> some View {
        let isDecoy = index >= facts.count
        let showsOutcome = locked != nil
        return Button {
            if isPlaced { placed.removeAll { $0 == index } } else { placed.append(index) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                if showsOutcome {
                    Image(systemName: isDecoy ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isDecoy ? Color.ratioOxblood : Color.ratioVerdigris)
                }
                Text(tray[index]).ratioFont(.small).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(RatioSpace.s)
            .frame(minHeight: 44)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).strokeBorder(Color.ratioRule) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked != nil || isChecking)
        .draggable(String(index)) { Text(tray[index]).ratioFont(.small).padding(RatioSpace.xs) }
        .accessibilityHint(isPlaced ? "Removes this fact from your application" : "Adds this fact to your application")
        .accessibilityValue(showsOutcome ? (isDecoy ? "Doesn't belong" : "Belongs") : "")
    }

    @ViewBuilder
    private func outcome(_ response: ItemResponse) -> some View {
        let missed = Set(facts.indices).subtracting(placed)
        if level < 4 && !missed.isEmpty {
            Label("Also relevant: " + missed.sorted().map { facts[$0] }.joined(separator: "; "), systemImage: "exclamationmark.circle.fill")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioOxblood)
        }
        IRACModelAnswer(answer: answer)
    }

    // MARK: Checking

    private var trayOrder: [Int] {
        var generator = SeededGenerator(seed: itemId + "tray")
        return Array(tray.indices).shuffled(using: &generator)
    }

    private var canCheck: Bool {
        if level == 4 {
            return [issue, rule, application, conclusion].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return !placed.isEmpty && !conclusion.trimmingCharacters(in: .whitespaces).isEmpty && (level == 2 || chosenRule != nil)
    }

    private var writtenAnswer: String {
        level == 4 ? "Issue: \(issue)\nRule: \(rule)\nApplication: \(application)\nConclusion: \(conclusion)" : conclusion
    }

    private var modelForWrittenPart: String {
        level == 4
            ? "Issue: \(answer.issue)\nRule: \(answer.rule)\nApplication: \(answer.application)\nConclusion: \(answer.conclusion)"
            : answer.conclusion
    }

    private func lock(writtenPartCovered: Bool) {
        isChecking = false
        var response = ItemResponse(itemId: itemId, selfMarkedCorrect: writtenPartCovered)
        if level < 4 {
            // Decoys go to the scorer as -1, so it can tell a wrong chip from a missing one.
            response.order = placed.map { $0 < facts.count ? $0 : -1 }
        }
        if level == 3 {
            response.choiceIndex = chosenRule.map { ruleOptions[$0] == answer.rule ? 0 : 1 }
        }
        onLock(response)
    }
}

// MARK: - Shared pieces

struct IRACFactsList: View {
    let facts: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Key facts").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(facts, id: \.self) { fact in
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                    Text("·").foregroundStyle(Color.ratioOxblood).accessibilityHidden(true)
                    Text(fact).ratioFont(.small)
                }
            }
        }
    }
}

struct IRACModelAnswer: View {
    let answer: Item.IRACAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            section("Issue", answer.issue)
            section("Rule", answer.rule)
            section("Application", answer.application)
            section("Conclusion", answer.conclusion)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            Text(title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(text).ratioFont(.body)
        }
        .ratioPanel()
    }
}

/// A small deterministic generator (SplitMix64), so shuffles are stable for an item
/// across view rebuilds rather than reshuffling under the student's finger.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = seed.unicodeScalars.reduce(1469598103934665603) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
