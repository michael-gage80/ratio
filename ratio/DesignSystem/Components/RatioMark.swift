import SwiftUI
import UIKit

/// The "R." mark — screens/00-logo/01-family-and-construction.png. Newsreader Italic
/// at display optical size, plus a true circle whose diameter is 19.2% of the cap
/// height, sitting on the baseline with a gap of 0.36× the dot.
struct RatioMark: View {
    var size: CGFloat = 96
    /// Centres the letter itself (cap height) rather than its line box, which has room
    /// for ascenders and descenders — for the mark alone inside a ring.
    var opticallyCentred = false

    private static let fontName = "NewsreaderDisplay-Italic"

    var body: some View {
        let font = UIFont(name: Self.fontName, size: size)
        let capHeight = font?.capHeight ?? size * 0.66
        let dot = capHeight * 0.192
        // How far the cap's centre sits above the line box's centre.
        let lift = font.map { capHeight / 2 - ($0.ascender + $0.descender) / 2 } ?? 0
        HStack(alignment: .lastTextBaseline, spacing: dot * 0.36) {
            Text("R")
                .font(.custom(Self.fontName, fixedSize: size))
                .foregroundStyle(Color.ratioInk)
            Circle()
                .fill(Color.ratioOxblood)
                .frame(width: dot, height: dot)
        }
        .offset(y: opticallyCentred ? lift : 0)
        .accessibilityElement()
        .accessibilityLabel("Ratio")
    }
}

/// The ring animation used on splash, analysing and matchmaking (PRD: "Motion").
/// A slowly turning dashed oxblood ring inside a faint dotted one; static when
/// Reduce Motion is on.
struct RatioRings: View {
    var diameter: CGFloat = 170

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ratioRule, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 6]))
                .frame(width: diameter * 1.24, height: diameter * 1.24)
            Circle()
                .stroke(Color.ratioOxblood, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [10, 7]))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(isTurning ? 360 : 0))
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) {
                isTurning = true
            }
        }
    }
}
