import SwiftUI

/// Renders one item and collects the student's answer — screens/00-design-system/
/// 03-in-line-games.png. Shared by the diagnostic now and lessons later. Follows the
/// feedback grammar on that board: nothing is revealed until the student locks in, the
/// correct answer is always shown afterwards, and every result carries an icon and a
/// word, never colour alone.
struct ItemInteractionView: View {
    let item: Item
    /// Set once the student has locked in; the view then shows the outcome.
    let lockedResponse: ItemResponse?
    var context = InteractionContext()
    let onLock: (ItemResponse) -> Void

    /// Bumped by Reset to rebuild the interaction with fresh state.
    @State private var resetCount = 0
    @State private var reporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.m) {
            Text(item.prompt)
                .ratioFont(.h2)
                .fixedSize(horizontal: false, vertical: true)

            interaction
                .id(resetCount)

            if let lockedResponse {
                feedback(correct: item.isCorrect(lockedResponse))
            }

            footer
        }
        .sheet(isPresented: $reporting) {
            ReportErrorSheet(itemId: item.id, lessonId: context.lessonId)
        }
    }

    /// Board rules 4 and 6: "Reset is always one tap away" and "Every item carries
    /// 'Spotted an error? Report it'". Reset only before locking in — after that the
    /// answer has been shown.
    private var footer: some View {
        HStack {
            if lockedResponse == nil {
                Button("Reset") { resetCount += 1 }
                    .ratioFont(.monoLabel)
                    .underline()
            }
            Spacer()
            RatioReportErrorLink { reporting = true }
        }
        .foregroundStyle(Color.ratioInk2)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var interaction: some View {
            switch item.kind {
            case .choice(let options, let correctIndex):
                ChoiceInteraction(itemId: item.id, options: options, correctIndex: correctIndex, locked: lockedResponse, onLock: onLock)
            case .tapTheFact(let text, let spans, let correctSpan):
                TapTheFactInteraction(itemId: item.id, text: text, spans: spans, correctSpan: correctSpan, locked: lockedResponse, onLock: onLock)
            case .slider(let labels, let correctSide):
                SliderInteraction(itemId: item.id, labels: labels, correctSide: correctSide, locked: lockedResponse, onLock: onLock)
            case .sequence(let items, let correctOrder):
                SequenceInteraction(itemId: item.id, items: items, correctOrder: correctOrder, locked: lockedResponse, onLock: onLock)
            case .recall(let modelAnswer, let keyPoints):
                RecallInteraction(itemId: item.id, modelAnswer: modelAnswer, keyPoints: keyPoints, locked: lockedResponse, onLock: onLock)
            case .highlight(let sentences, let ratioSentence):
                HighlightInteraction(itemId: item.id, sentences: sentences, ratioSentence: ratioSentence, locked: lockedResponse, onLock: onLock)
            case .buckets(let buckets, let statements, let correct):
                SortInteraction(itemId: item.id, buckets: buckets, statements: statements, correct: correct, locked: lockedResponse, onLock: onLock)
            case .irac(let facts, let modelAnswer):
                IRACInteraction(itemId: item.id, facts: facts, answer: modelAnswer, level: context.iracLevel,
                                decoyFacts: context.decoyFacts, decoyRules: context.decoyRules,
                                locked: lockedResponse, onLock: onLock)
            }
    }

    @ViewBuilder
    private func feedback(correct: Bool) -> some View {
        if !correct, let trap = item.trapExplanation {
            RatioTrapCard(whyItsWrong: trap)
        } else if let text = item.feedback(correct: correct) {
            RatioWhyCard(text)
        }
    }
}

// MARK: - Choice (and distinguishing two scenarios)

private struct ChoiceInteraction: View {
    let itemId: String
    let options: [String]
    let correctIndex: Int
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var selection: Int?

    var body: some View {
        VStack(spacing: RatioSpace.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                RatioOptionRow(
                    letter: String(UnicodeScalar(UInt8(65 + index))),
                    text: option,
                    state: state(for: index),
                    action: locked == nil ? { selection = index } : nil
                )
            }
            if locked == nil {
                RatioButton("Lock it in", isEnabled: selection != nil) {
                    onLock(ItemResponse(itemId: itemId, choiceIndex: selection))
                }
                .padding(.top, RatioSpace.xs)
            }
        }
    }

    private func state(for index: Int) -> RatioOptionState {
        guard let locked else { return index == selection ? .selected : .default }
        if index == correctIndex { return .correct }
        return index == locked.choiceIndex ? .incorrect : .default
    }
}

// MARK: - Tap the fact

/// The scenario is split into lines at each tappable phrase, as on the design board,
/// so every phrase is a full-size, VoiceOver-reachable button.
private struct TapTheFactInteraction: View {
    let itemId: String
    let text: String
    let spans: [String]
    let correctSpan: String
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if let span = segment.span {
                        spanButton(span, shown: segment.text)
                    } else {
                        Text(segment.text).ratioFont(.body)
                    }
                }
            }
            .ratioPanel()

            if locked == nil {
                RatioButton("Lock it in", isEnabled: selection != nil) {
                    onLock(ItemResponse(itemId: itemId, span: selection))
                }
            }
        }
    }

    private func spanButton(_ span: String, shown: String) -> some View {
        let isCorrect = locked != nil && span == correctSpan
        let isWrongPick = locked != nil && span == locked?.span && span != correctSpan
        let isSelected = locked == nil && span == selection
        return Button {
            selection = span
        } label: {
            HStack(spacing: RatioSpace.xs) {
                if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ratioVerdigris) }
                if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ratioOxblood) }
                Text(shown).ratioFont(.body).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, RatioSpace.xs)
            .padding(.vertical, RatioSpace.xxs)
            .frame(minHeight: 44)
            .background(isCorrect ? Color.ratioVWash : isWrongPick ? Color.ratioOxWash : Color.ratioPaper,
                        in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous)
                    .strokeBorder(isSelected ? Color.ratioInk : Color.ratioRule, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(locked != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isCorrect ? "Correct" : isWrongPick ? "Not quite" : "")
    }

    /// The scenario cut into plain text and tappable phrases. `span` is the content's
    /// canonical phrase (what gets graded); `text` is how it reads in the scenario —
    /// matching ignores case, e.g. a phrase that starts a sentence.
    private var segments: [(text: String, span: String?)] {
        var result: [(String, String?)] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let next = spans
                .compactMap { span in rest.range(of: span, options: .caseInsensitive).map { (span, $0) } }
                .min { $0.1.lowerBound < $1.1.lowerBound }
            guard let (span, range) = next else {
                result.append((String(rest), nil))
                break
            }
            result.append((String(rest[..<range.lowerBound]), nil))
            result.append((String(rest[range]), span))
            rest = rest[range.upperBound...]
        }
        return result
            .map { ($0.0.trimmingCharacters(in: .whitespaces), $0.1) }
            .filter { !$0.0.isEmpty && !CharacterSet.punctuationCharacters.isSuperset(of: CharacterSet(charactersIn: $0.0)) }
    }
}

// MARK: - Threshold slider

private struct SliderInteraction: View {
    let itemId: String
    let labels: [String]
    let correctSide: Int
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var value = 0.5
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Slider(value: $value, in: 0...1, step: 0.25)
                .tint(Color.ratioInk)
                .disabled(locked != nil)
                .accessibilityValue(position)
            Group {
                if typeSize.isAccessibilitySize {
                    // Large text: the two ends, labelled, one under the other.
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text("Left: \(labels.first ?? "")")
                        Text("Right: \(labels.last ?? "")")
                    }
                } else {
                    HStack(alignment: .top, spacing: RatioSpace.s) {
                        Text(labels.first ?? "").frame(maxWidth: .infinity, alignment: .leading)
                        Text(labels.last ?? "").frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
                    }
                }
            }
            .ratioFont(.small)
            .foregroundStyle(Color.ratioInk2)

            if locked != nil {
                let answer = labels.indices.contains(correctSide) ? labels[correctSide] : ""
                Label("Closer to “\(answer)”", systemImage: "checkmark.circle.fill")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioVerdigris)
            } else {
                RatioButton("Lock it in", isEnabled: value != 0.5) {
                    onLock(ItemResponse(itemId: itemId, sliderValue: value))
                }
            }
        }
    }

    private var position: String {
        switch value {
        case ..<0.5: "Towards \(labels.first ?? "left")"
        case 0.5: "Undecided"
        default: "Towards \(labels.last ?? "right")"
        }
    }
}

// MARK: - Sequence

/// Drag rows into order: press and hold a row (or grab its handle) and the others make
/// way as it moves. Tapping a row and using Move up / Move down does the same without
/// dragging — the route the PRD requires, also offered to VoiceOver as each row's
/// move actions.
private struct SequenceInteraction: View {
    let itemId: String
    let items: [String]
    let correctOrder: [Int]
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var order: [Int]
    @State private var selected: Int?
    /// The row being dragged, how far the finger has moved, and how much of that the
    /// reordering has already absorbed (the rows it has passed).
    @State private var dragging: Int?
    @State private var translation: CGFloat = 0
    @State private var absorbed: CGFloat = 0
    @State private var frames: [Int: CGRect] = [:]

    private static let space = "sequence"

    init(itemId: String, items: [String], correctOrder: [Int], locked: ItemResponse?, onLock: @escaping (ItemResponse) -> Void) {
        self.itemId = itemId
        self.items = items
        self.correctOrder = correctOrder
        self.locked = locked
        self.onLock = onLock
        // Never start in the right order. Reversing is deterministic, which keeps the
        // starting position stable if the view is rebuilt.
        _order = State(initialValue: correctOrder.reversed())
    }

    var body: some View {
        VStack(spacing: RatioSpace.xs) {
            if locked == nil {
                Text("Hold and drag to reorder, or tap a row and move it.")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: RatioSpace.xs) {
                ForEach(Array(order.enumerated()), id: \.element) { position, index in
                    row(position: position, index: index)
                }
            }
            .coordinateSpace(name: Self.space)
            if locked == nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RatioSpace.xs) { moveButtons }
                    VStack(spacing: RatioSpace.xs) { moveButtons }
                }
                .padding(.top, RatioSpace.xs)
                RatioButton("Lock it in") {
                    onLock(ItemResponse(itemId: itemId, order: order))
                }
            } else if locked?.order != correctOrder {
                RatioWhyCard("The right order: " + correctOrder.enumerated().map { "\($0.offset + 1). \(items[$0.element])" }.joined(separator: "  "))
            }
        }
        // Lets the scroll view hold still while a row is being dragged.
        .preference(key: ReorderingKey.self, value: dragging != nil)
        .ratioFeedback(.selection, trigger: dragging) { old, new in old == nil && new != nil }
    }

    @ViewBuilder private var moveButtons: some View {
        RatioButton("Move up", style: .tertiary, isEnabled: canMove(by: -1)) { move(by: -1) }
        RatioButton("Move down", style: .tertiary, isEnabled: canMove(by: 1)) { move(by: 1) }
    }

    private func row(position: Int, index: Int) -> some View {
        let state: RatioOptionState = if let locked {
            locked.order?[position] == correctOrder[position] ? .correct : .incorrect
        } else {
            selected == index || dragging == index ? .selected : .default
        }
        let isDragged = dragging == index
        return HStack(spacing: RatioSpace.xxs) {
            RatioOptionRow(letter: "\(position + 1)", text: items[index], state: state,
                           action: locked == nil ? { selected = index } : nil)
            if locked == nil {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Color.ratioInk2)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
                    // The handle drags straight away; the rest of the row after a hold.
                    .highPriorityGesture(dragGesture(for: index, hold: 0))
                    .accessibilityHidden(true)
            }
        }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[index] = $0 }
            .offset(y: isDragged ? translation - absorbed : 0)
            .scaleEffect(isDragged ? 1.02 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.12 : 0), radius: 12, y: 6)
            .zIndex(isDragged ? 1 : 0)
            .highPriorityGesture(locked == nil ? dragGesture(for: index, hold: 0.25) : nil)
            .accessibilityAction(named: "Move up") { selected = index; move(by: -1) }
            .accessibilityAction(named: "Move down") { selected = index; move(by: 1) }
    }

    /// Lifts the row (after `hold` seconds), follows the finger, and moves it past each
    /// neighbour whose middle it crosses.
    private func dragGesture(for index: Int, hold: Double) -> some Gesture {
        LongPressGesture(minimumDuration: hold)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    dragging = index
                    selected = index
                    absorbed = 0
                }
                translation = drag?.translation.height ?? 0
                reorder(index)
            }
            .onEnded { _ in
                withAnimation(RatioMotion.tap) {
                    dragging = nil
                    translation = 0
                    absorbed = 0
                }
            }
    }

    private func reorder(_ index: Int) {
        guard let frame = frames[index] else { return }
        let middle = frame.midY + translation - absorbed
        while let position = order.firstIndex(of: index) {
            if position + 1 < order.count, let below = frames[order[position + 1]], middle > below.midY {
                withAnimation(RatioMotion.tap) { order.swapAt(position, position + 1) }
                absorbed += below.height + RatioSpace.xs
            } else if position > 0, let above = frames[order[position - 1]], middle < above.midY {
                withAnimation(RatioMotion.tap) { order.swapAt(position, position - 1) }
                absorbed -= above.height + RatioSpace.xs
            } else {
                break
            }
        }
    }

    private func canMove(by offset: Int) -> Bool {
        guard let selected, let position = order.firstIndex(of: selected) else { return false }
        return order.indices.contains(position + offset)
    }

    private func move(by offset: Int) {
        guard let selected, let position = order.firstIndex(of: selected), order.indices.contains(position + offset) else { return }
        withAnimation(RatioMotion.tap) { order.swapAt(position, position + offset) }
    }
}

/// Whether a row is being dragged into order somewhere inside a scroll view.
struct ReorderingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// Holds a scroll view still while a sequence row inside it is being dragged.
    func holdsStillWhileReordering() -> some View {
        modifier(ReorderScrollLock())
    }
}

private struct ReorderScrollLock: ViewModifier {
    @State private var reordering = false

    func body(content: Content) -> some View {
        content
            .scrollDisabled(reordering)
            .onPreferenceChange(ReorderingKey.self) { reordering = $0 }
    }
}

// MARK: - Sort into buckets

/// Each statement gets a bucket by tapping one of the bucket buttons under it — no
/// dragging, so it works the same with VoiceOver.
private struct SortInteraction: View {
    let itemId: String
    let buckets: [String]
    let statements: [String]
    let correct: [Int]
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var chosen: [Int?]

    init(itemId: String, buckets: [String], statements: [String], correct: [Int], locked: ItemResponse?, onLock: @escaping (ItemResponse) -> Void) {
        self.itemId = itemId
        self.buckets = buckets
        self.statements = statements
        self.correct = correct
        self.locked = locked
        self.onLock = onLock
        _chosen = State(initialValue: Array(repeating: nil, count: statements.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            ForEach(statements.indices, id: \.self) { index in
                row(index)
            }
            if locked == nil {
                RatioButton("Lock it in", isEnabled: chosen.allSatisfy { $0 != nil }) {
                    onLock(ItemResponse(itemId: itemId, order: chosen.map { $0 ?? -1 }))
                }
                .padding(.top, RatioSpace.xs)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let answer = locked?.order?[safe: index] ?? chosen[index]
        let isRight = answer == correct[index]
        return VStack(alignment: .leading, spacing: RatioSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                Text(statements[index]).ratioFont(.body)
                Spacer(minLength: 0)
                if locked != nil {
                    Image(systemName: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isRight ? Color.ratioVerdigris : Color.ratioOxblood)
                        .accessibilityLabel(isRight ? "Right" : "Wrong")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.xs) { bucketButtons(index, answer: answer) }
                VStack(alignment: .leading, spacing: RatioSpace.xs) { bucketButtons(index, answer: answer) }
            }
            if locked != nil, !isRight, let right = buckets[safe: correct[index]] {
                Text("Belongs in: \(right)").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(RatioSpace.s)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    @ViewBuilder
    private func bucketButtons(_ index: Int, answer: Int?) -> some View {
        ForEach(buckets.indices, id: \.self) { bucket in
            let selected = answer == bucket
            Button { chosen[index] = bucket } label: {
                Text(buckets[bucket])
                    .ratioFont(.small)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, RatioSpace.s)
                    .padding(.vertical, RatioSpace.xs)
                    .frame(minHeight: 44)
                    .foregroundStyle(selected ? Color.ratioParchment : Color.ratioInk)
                    .background(selected ? Color.ratioInk : Color.ratioSunk, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(locked != nil)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

// MARK: - Recall first

/// Retrieval before reveal: the student writes what they remember first, then it's
/// marked against the model answer — on-device where possible, otherwise by the student.
private struct RecallInteraction: View {
    let itemId: String
    let modelAnswer: String
    let keyPoints: [String]
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var answer = ""
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            RatioTextField("Your answer", placeholder: "Type what you remember…", text: $answer, axis: .vertical)
                .disabled(submitted || locked != nil)

            if let locked {
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Model answer").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text(modelAnswer).ratioFont(.body)
                    Label(locked.selfMarkedCorrect == true ? "Recalled" : "One to revisit",
                          systemImage: locked.selfMarkedCorrect == true ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .ratioFont(.small)
                        .foregroundStyle(locked.selfMarkedCorrect == true ? Color.ratioVerdigris : Color.ratioOxblood)
                }
                .ratioPanel()
            } else if submitted {
                FreeTextVerdictView(studentAnswer: answer, modelAnswer: modelAnswer, keyPoints: keyPoints) { covered in
                    onLock(ItemResponse(itemId: itemId, selfMarkedCorrect: covered))
                }
            } else {
                RatioButton(AnswerMarker.isAvailable ? "Check" : "Reveal",
                            isEnabled: !answer.trimmingCharacters(in: .whitespaces).isEmpty) {
                    withAnimation(RatioMotion.reveal) { submitted = true }
                }
                Button("I can't recall — show me") {
                    onLock(ItemResponse(itemId: itemId, selfMarkedCorrect: false))
                }
                .ratioFont(.small)
                .italic()
                .underline()
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

// MARK: - Highlight the ratio

/// Tap the sentence that states the ratio (board cell 08). Each sentence is a button,
/// so the passage stays readable and every choice is reachable with VoiceOver.
private struct HighlightInteraction: View {
    let itemId: String
    let sentences: [String]
    let ratioSentence: String
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text("Paraphrased · not the judgment text")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .padding(.bottom, RatioSpace.xxs)
                ForEach(sentences, id: \.self) { sentence in
                    sentenceButton(sentence)
                }
            }
            .ratioPanel()

            if locked == nil {
                RatioButton("Lock it in", isEnabled: selection != nil) {
                    onLock(ItemResponse(itemId: itemId, span: selection))
                }
            }
        }
    }

    private func sentenceButton(_ sentence: String) -> some View {
        let isRatio = Item.sentence(sentence, states: ratioSentence)
        let isCorrect = locked != nil && isRatio
        let isWrongPick = locked != nil && sentence == locked?.span && !isRatio
        let isSelected = locked == nil && sentence == selection
        return Button {
            selection = sentence
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ratioVerdigris) }
                if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ratioOxblood) }
                Text(sentence).ratioFont(.body).multilineTextAlignment(.leading)
            }
            .padding(RatioSpace.xs)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isCorrect ? Color.ratioVWash : isWrongPick ? Color.ratioOxWash : isSelected ? Color.ratioPaper : .clear,
                        in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous).strokeBorder(Color.ratioInk, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked != nil)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isCorrect ? "The ratio" : isWrongPick ? "Not quite" : "")
    }
}

/// What an item needs to know about where it's shown: the IRAC scaffold level and
/// decoys (lessons only), and the lesson for error reports.
struct InteractionContext {
    var iracLevel = 1
    var decoyFacts: [String] = []
    var decoyRules: [String] = []
    var lessonId: String?
}
