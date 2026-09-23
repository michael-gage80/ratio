import SwiftUI

/// A score on the 0–100 track with its uncertainty band shaded and the estimate as a
/// dot — screens/00-design-system/02-components.png, cell 12 ("scores with uncertainty").
struct SkillTrack: View {
    let estimate: Estimate
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (score: Int) in width * CGFloat(min(max(score, 0), 100)) / 100 }
            let low = estimate.displayScore - estimate.band
            let high = estimate.displayScore + estimate.band
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ratioRule).frame(height: 2)
                Capsule()
                    .fill(Color.ratioOxblood.opacity(0.22))
                    .frame(width: max(height, x(high) - x(low)), height: height * 0.7)
                    .offset(x: x(low))
                Circle()
                    .fill(Color.ratioInk)
                    .frame(width: height, height: height)
                    .offset(x: x(estimate.displayScore) - height / 2)
            }
            .frame(height: height)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// "Knowledge  67 ±8" over its track — the Me tab and the Pathway peek.
struct SkillRow: View {
    let title: String
    let estimate: Estimate?
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 12) {
                Text(title).ratioFont(.monoLabel).frame(width: 16, alignment: .leading)
                track
                Text(score).ratioFont(.monoData).frame(width: 56, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).ratioFont(.h3)
                    Spacer()
                    Text(score).ratioFont(.monoData)
                }
                track
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    @ViewBuilder
    private var track: some View {
        if let estimate {
            SkillTrack(estimate: estimate)
        } else {
            Capsule().fill(Color.ratioRule).frame(height: 2).frame(maxWidth: .infinity)
        }
    }

    private var score: String {
        estimate.map { "\($0.displayScore) ±\($0.band)" } ?? "—"
    }

    private var accessibilityText: String {
        estimate.map { "\(title): \($0.displayScore), plus or minus \($0.band)" } ?? "\(title): not assessed yet"
    }
}
