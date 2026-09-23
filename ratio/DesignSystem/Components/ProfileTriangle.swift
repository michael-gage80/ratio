import SwiftUI

/// The three-axis profile — screens/00-design-system/02-components.png, cell 13, and
/// screens/09-first-profile.png. "Shaded outer shape is the upper edge of each band;
/// line is the estimate." Replaces the old five-axis radar (PRD: "Me tab").
struct ProfileTriangle: View {
    let headline: Headline
    /// Drawn in oxblood to point at the growth edge.
    var highlight: Skill?

    /// Knowledge at the top, understanding bottom-right, application bottom-left.
    private static let angles: [Skill: Double] = [.knowledge: -90, .understanding: 30, .application: 150]

    var body: some View {
        VStack(spacing: 8) {
            label(.knowledge)
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)
                let radius = size * 0.5
                ZStack {
                    triangle(center: center, radius: radius) { _ in 1 }
                        .stroke(Color.ratioRule, lineWidth: 1)
                    triangle(center: center, radius: radius) { _ in 0.5 }
                        .stroke(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    spokes(center: center, radius: radius)
                        .stroke(Color.ratioRule, lineWidth: 1)
                    triangle(center: center, radius: radius) { upper($0) }
                        .fill(Color.ratioOxblood.opacity(0.16))
                    triangle(center: center, radius: radius) { fraction($0) }
                        .stroke(Color.ratioOxblood, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                    ForEach(Skill.allCases) { skill in
                        Circle()
                            .fill(Color.ratioInk)
                            .frame(width: 9, height: 9)
                            .position(point(skill, center: center, radius: radius * fraction(skill)))
                    }
                }
            }
            .aspectRatio(1.15, contentMode: .fit)
            HStack(alignment: .top) {
                label(.application)
                Spacer()
                label(.understanding)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Skill.allCases.map { "\($0.title) \(headline[$0].displayScore), plus or minus \(headline[$0].band)" }.joined(separator: ". "))
    }

    private func label(_ skill: Skill) -> some View {
        VStack(spacing: 2) {
            Text(skill.title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("\(headline[skill].displayScore) ±\(headline[skill].band)")
                .ratioFont(.monoData)
                .foregroundStyle(skill == highlight ? Color.ratioOxblood : Color.ratioInk)
        }
    }

    private func fraction(_ skill: Skill) -> Double { Double(headline[skill].displayScore) / 100 }

    private func upper(_ skill: Skill) -> Double { min(1, Double(headline[skill].displayScore + headline[skill].band) / 100) }

    private func point(_ skill: Skill, center: CGPoint, radius: Double) -> CGPoint {
        let angle = (Self.angles[skill] ?? 0) * .pi / 180
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func triangle(center: CGPoint, radius: Double, scale: (Skill) -> Double) -> Path {
        Path { path in
            let points = Skill.allCases.map { point($0, center: center, radius: radius * scale($0)) }
            path.addLines(points)
            path.closeSubpath()
        }
    }

    private func spokes(center: CGPoint, radius: Double) -> Path {
        Path { path in
            for skill in Skill.allCases {
                path.move(to: center)
                path.addLine(to: point(skill, center: center, radius: radius))
            }
        }
    }
}
