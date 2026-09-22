import SwiftUI

/// Option rows and feedback — screens/00-design-system/02-components.png, cell 04, and
/// the shared feedback grammar in cell "KEY · FEEDBACK GRAMMAR" on
/// screens/00-design-system/03-in-line-games.png. Used across every one of the 11
/// in-line interaction types (Phase 7) and the exam-room tests (Phase 8).
///
/// Rules this bakes in, straight from the design board:
/// - Recall before reveal: nothing is shown until the student locks in.
/// - Colour is never the only signal — every result carries an icon *and* a word
///   ("CORRECT" / "NOT QUITE"), never colour alone.
/// - The correct answer is always revealed, even on a wrong answer.
public enum RatioOptionState {
    case `default`
    case selected
    case correct
    case incorrect
}

public struct RatioOptionRow: View {
    private let letter: String?
    private let text: String
    private let state: RatioOptionState
    private let action: (() -> Void)?

    public init(letter: String? = nil, text: String, state: RatioOptionState = .default, action: (() -> Void)? = nil) {
        self.letter = letter
        self.text = text
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                marker
                Text(text)
                    .ratioFont(.body)
                    .fontWeight(state == .selected ? .semibold : .regular)
                    .foregroundStyle(Color.ratioInk)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let resultLabel {
                    Text(resultLabel)
                        .ratioFont(.monoLabel)
                        .foregroundStyle(resultColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: state == .selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var marker: some View {
        switch state {
        case .default, .selected:
            if let letter {
                Text(letter)
                    .ratioFont(.h3)
                    .foregroundStyle(Color.ratioInk)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(Color.ratioRule, lineWidth: state == .selected ? 2 : 1))
            }
        case .correct:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.ratioVerdigris)
                .imageScale(.large)
        case .incorrect:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.ratioOxblood)
                .imageScale(.large)
        }
    }

    private var resultLabel: String? {
        switch state {
        case .correct: return "Correct"
        case .incorrect: return "Not quite"
        default: return nil
        }
    }

    private var resultColor: Color {
        switch state {
        case .correct: return .ratioVerdigris
        case .incorrect: return .ratioOxblood
        default: return .ratioInk
        }
    }

    private var background: Color {
        switch state {
        case .correct: return .ratioVWash
        case .incorrect: return .ratioOxWash
        default: return Color.ratioPaper
        }
    }

    private var borderColor: Color {
        switch state {
        case .selected: return .ratioInk
        case .correct: return .ratioVerdigris.opacity(0.4)
        case .incorrect: return .ratioOxblood.opacity(0.4)
        default: return .ratioRule
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .correct: return "\(text), correct"
        case .incorrect: return "\(text), not quite"
        case .selected: return "\(text), selected"
        case .default: return text
        }
    }
}
