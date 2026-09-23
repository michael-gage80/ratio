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
    let onLock: (ItemResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(item.prompt)
                .ratioFont(.h2)
                .fixedSize(horizontal: false, vertical: true)

            switch item.kind {
            case .choice(let options, let correctIndex):
                ChoiceInteraction(itemId: item.id, options: options, correctIndex: correctIndex, locked: lockedResponse, onLock: onLock)
            case .tapTheFact(let text, let spans, let correctSpan):
                TapTheFactInteraction(itemId: item.id, text: text, spans: spans, correctSpan: correctSpan, locked: lockedResponse, onLock: onLock)
            case .slider(let labels, let correctSide):
                SliderInteraction(itemId: item.id, labels: labels, correctSide: correctSide, locked: lockedResponse, onLock: onLock)
            case .sequence(let items, let correctOrder):
                SequenceInteraction(itemId: item.id, items: items, correctOrder: correctOrder, locked: lockedResponse, onLock: onLock)
            case .recall(let modelAnswer):
                RecallInteraction(itemId: item.id, modelAnswer: modelAnswer, locked: lockedResponse, onLock: onLock)
            case .highlight(let sentences, let ratioSentence):
                HighlightInteraction(itemId: item.id, sentences: sentences, ratioSentence: ratioSentence, locked: lockedResponse, onLock: onLock)
            case .irac(let facts, let modelAnswer):
                IRACWorkedExample(itemId: item.id, facts: facts, answer: modelAnswer, locked: lockedResponse, onLock: onLock)
            }

            if let lockedResponse {
                feedback(correct: item.isCorrect(lockedResponse))
            }
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
        VStack(spacing: 10) {
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
                .padding(.top, 8)
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if let span = segment.span {
                        spanButton(span, shown: segment.text)
                    } else {
                        Text(segment.text).ratioFont(.body)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
            HStack(spacing: 8) {
                if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ratioVerdigris) }
                if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ratioOxblood) }
                Text(shown).ratioFont(.body).multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isCorrect ? Color.ratioVWash : isWrongPick ? Color.ratioOxWash : Color.ratioPaper,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Slider(value: $value, in: 0...1, step: 0.25)
                .tint(Color.ratioInk)
                .disabled(locked != nil)
                .accessibilityValue(position)
            HStack(alignment: .top) {
                Text(labels.first ?? "").frame(maxWidth: .infinity, alignment: .leading)
                Text(labels.last ?? "").frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
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

/// Tap a row, then move it — the non-drag route the PRD requires for VoiceOver.
private struct SequenceInteraction: View {
    let itemId: String
    let items: [String]
    let correctOrder: [Int]
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var order: [Int]
    @State private var selected: Int?

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
        VStack(spacing: 10) {
            ForEach(Array(order.enumerated()), id: \.element) { position, index in
                row(position: position, index: index)
            }
            if locked == nil {
                HStack(spacing: 10) {
                    RatioButton("Move up", style: .tertiary, isEnabled: canMove(by: -1)) { move(by: -1) }
                    RatioButton("Move down", style: .tertiary, isEnabled: canMove(by: 1)) { move(by: 1) }
                }
                RatioButton("Lock it in") {
                    onLock(ItemResponse(itemId: itemId, order: order))
                }
            } else if locked?.order != correctOrder {
                RatioWhyCard("The right order: " + correctOrder.enumerated().map { "\($0.offset + 1). \(items[$0.element])" }.joined(separator: "  "))
            }
        }
    }

    private func row(position: Int, index: Int) -> some View {
        let state: RatioOptionState = if let locked {
            locked.order?[position] == correctOrder[position] ? .correct : .incorrect
        } else {
            selected == index ? .selected : .default
        }
        return RatioOptionRow(letter: "\(position + 1)", text: items[index], state: state,
                              action: locked == nil ? { selected = index } : nil)
    }

    private func canMove(by offset: Int) -> Bool {
        guard let selected, let position = order.firstIndex(of: selected) else { return false }
        return order.indices.contains(position + offset)
    }

    private func move(by offset: Int) {
        guard let selected, let position = order.firstIndex(of: selected), order.indices.contains(position + offset) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { order.swapAt(position, position + offset) }
    }
}

// MARK: - Recall first

/// Retrieval before reveal: the student writes what they remember, sees the model
/// answer, then marks themselves against it.
private struct RecallInteraction: View {
    let itemId: String
    let modelAnswer: String
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    @State private var answer = ""
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RatioTextField("Your answer", placeholder: "Type what you remember…", text: $answer, axis: .vertical)
                .disabled(revealed)

            if revealed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model answer").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text(modelAnswer).ratioFont(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let locked {
                    Label(locked.selfMarkedCorrect == true ? "You marked this as recalled" : "Marked as one to revisit",
                          systemImage: locked.selfMarkedCorrect == true ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .ratioFont(.small)
                        .foregroundStyle(locked.selfMarkedCorrect == true ? Color.ratioVerdigris : Color.ratioOxblood)
                } else {
                    Text("Did your answer cover the key point?").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                    HStack(spacing: 10) {
                        RatioButton("I missed it", style: .tertiary) { lock(correct: false) }
                        RatioButton("I got it", style: .secondary) { lock(correct: true) }
                    }
                }
            } else {
                RatioButton("Reveal", isEnabled: !answer.trimmingCharacters(in: .whitespaces).isEmpty) {
                    withAnimation { revealed = true }
                }
                Button("I can't recall — show me") {
                    withAnimation { revealed = true }
                    lock(correct: false)
                }
                .ratioFont(.small)
                .italic()
                .underline()
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func lock(correct: Bool) {
        onLock(ItemResponse(itemId: itemId, selfMarkedCorrect: correct))
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Paraphrased · not the judgment text")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                ForEach(sentences, id: \.self) { sentence in
                    sentenceButton(sentence)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isCorrect { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.ratioVerdigris) }
                if isWrongPick { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ratioOxblood) }
                Text(sentence).ratioFont(.body).multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCorrect ? Color.ratioVWash : isWrongPick ? Color.ratioOxWash : isSelected ? Color.ratioPaper : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.ratioInk, lineWidth: 2)
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

// MARK: - IRAC (worked example)

/// Scaffold level 1 of the IRAC builder (PRD: "worked examples, then fading"): the
/// full model answer with the key facts, before any support is taken away.
private struct IRACWorkedExample: View {
    let itemId: String
    let facts: [String]
    let answer: Item.IRACAnswer
    let locked: ItemResponse?
    let onLock: (ItemResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Worked example · scaffold 1 of 4")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Key facts").ratioFont(.monoLabel)
                ForEach(facts, id: \.self) { fact in
                    Label(fact, systemImage: "circle.fill")
                        .labelStyle(BulletLabelStyle())
                        .ratioFont(.small)
                }
            }
            section("Issue", answer.issue)
            section("Rule", answer.rule)
            section("Application", answer.application)
            section("Conclusion", answer.conclusion)
            if locked == nil {
                RatioButton("I've read the worked example", style: .secondary) {
                    onLock(ItemResponse(itemId: itemId, selfMarkedCorrect: true))
                }
            }
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(text).ratioFont(.body)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("·").foregroundStyle(Color.ratioOxblood)
            configuration.title
        }
    }
}
