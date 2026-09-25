import SwiftUI

/// screens/20-law-report-sheet.png — the full case, typeset like a law report. Opened
/// from "Read the full report" on an expanded case card. Paraphrased, never the
/// judgment or an ICLR headnote (PRD: "Accuracy rules").
struct LawReportSheet: View {
    let card: LessonComponent.CaseCard
    let moduleTitle: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ratioDyslexiaFriendly) private var dyslexiaFriendly
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: RatioSpace.xs) {
                        Rectangle().fill(Color.ratioRule).frame(height: 1)
                        Text("Law reports · \(moduleTitle)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).fixedSize()
                        Rectangle().fill(Color.ratioRule).frame(height: 1)
                    }
                    Text("Law reports · \(moduleTitle)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        .frame(maxWidth: .infinity)
                }
                VStack(spacing: RatioSpace.xs) {
                    CaseName.text(reportTitle)
                        .ratioFont(.displayAccent)
                        .multilineTextAlignment(.center)
                    Text("\(card.citation) · \(card.court)").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Rectangle().fill(Color.ratioInk).frame(height: 1)

                if let expanded = card.expanded {
                    // The oxblood initial stands in for a drop cap.
                    Text("\(Text(String(expanded.facts.prefix(1))).font(RatioTypography.font(for: .display, dyslexiaFriendly: dyslexiaFriendly)).foregroundStyle(Color.ratioOxblood))\(Text(String(expanded.facts.dropFirst())))")
                        .ratioFont(.body)
                    Text(expanded.judgmentExtract).ratioFont(.body)
                } else {
                    Text(card.factsShort).ratioFont(.body)
                }

                Group {
                    if typeSize.isAccessibilitySize {
                        // Large text: the sideways label wouldn't fit beside the ratio.
                        VStack(alignment: .leading, spacing: RatioSpace.xs) {
                            Text("Ratio decidendi").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Text(card.ratioShort).ratioFont(.body)
                        }
                    } else {
                        HStack(alignment: .top, spacing: RatioSpace.s) {
                            Text("Ratio decidendi")
                                .ratioFont(.monoLabel)
                                .foregroundStyle(Color.ratioInk2)
                                .fixedSize()
                                .rotationEffect(.degrees(-90))
                                .frame(width: 16, height: 128)
                            Rectangle().fill(Color.ratioRule).frame(width: 1)
                            Text(card.ratioShort).ratioFont(.body)
                        }
                    }
                }
                .ratioPanel(padding: RatioSpace.m)

                if let significance = card.expanded?.significance {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Text("Significance").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Text(significance).ratioFont(.body)
                    }
                }

                Rectangle().fill(Color.ratioRule).frame(height: 1)
                Text("Paraphrased for study. Not a reproduction of the judgment or headnote.")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                HStack(spacing: RatioSpace.s) {
                    RatioButton("Close", style: .tertiary) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if KeyboardMonitor.shared.isConnected { KeyHint(keys: "esc", label: "Close") }
                }
            }
            .padding(width.isCompact ? RatioSpace.m : RatioSpace.xl)
            .ratioReadableWidth(760)
        }
        .background(Color.ratioPaper.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .presentationDragIndicator(.visible)
    }

    /// Law reports style the Crown in full: "R v Woollin" → "Regina v Woollin".
    private var reportTitle: String {
        card.caseName.hasPrefix("R v ") ? "Regina v " + card.caseName.dropFirst(4) : card.caseName
    }
}
