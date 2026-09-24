import SwiftUI

/// Engraving spot art — screens/00-design-system/01-foundations.png, "Engraving spot
/// art" section: "placeholder line-work in the house style. Final art needs an
/// illustrator." Drawn as SwiftUI `Shape`s (1pt stroke, no fill, generic objects, never
/// people) rather than bundled SVGs, so they scale losslessly, recolour with the
/// design tokens, and are trivial to delete once real illustrations arrive — swap the
/// `case` in `RatioSpotArt.view(for:)` for an `Image`.
public enum RatioSpotArt: CaseIterable {
    case scales      // Crime — scales of justice
    case pediment    // Public law — courthouse pediment and columns
    case quill       // Contract — quill and inkwell
    case bottle      // Tort — a spilled bottle (harm/damage)
    case openBook    // Land law — an open book (title, registration)
    case seal        // Equity & Trusts — a wax seal (a trust instrument)

    /// The 1pt-stroke line drawing, in a 100×100 coordinate space. Wrap in
    /// `.aspectRatio(1, contentMode: .fit)` at the call site to size it.
    @ViewBuilder
    public var view: some View {
        switch self {
        case .scales: ScalesShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        case .pediment: PedimentShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        case .quill: QuillShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        case .bottle: BottleShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        case .openBook: OpenBookShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        case .seal: SealShape().stroke(style: RatioSpotArt.strokeStyle).aspectRatio(1, contentMode: .fit)
        }
    }

    static let strokeStyle = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)

    /// The icon for a module on the Pathway module rail.
    static func `for`(_ module: Module) -> RatioSpotArt {
        switch module {
        case .crime: .scales
        case .publicLaw: .pediment
        case .contract: .quill
        case .tort: .bottle
        case .landLaw: .openBook
        case .equityTrusts: .seal
        // Placeholders until the illustrator draws their own.
        case .companyLaw: .quill
        case .euLaw: .pediment
        case .humanRights: .scales
        case .jurisprudence: .openBook
        }
    }
}

// MARK: - Shapes

private struct ScalesShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        // Post
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.78))
        // Base
        p.move(to: CGPoint(x: w * 0.32, y: h * 0.9))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.9))
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.78))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.9))
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.78))
        p.addLine(to: CGPoint(x: w * 0.68, y: h * 0.9))
        // Beam
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.82, y: h * 0.28))
        // Pans (simple arcs hung from beam)
        for cx in [w * 0.18, w * 0.82] {
            p.move(to: CGPoint(x: cx - w * 0.13, y: h * 0.28))
            p.addLine(to: CGPoint(x: cx, y: h * 0.44))
            p.addLine(to: CGPoint(x: cx + w * 0.13, y: h * 0.28))
            p.addArc(center: CGPoint(x: cx, y: h * 0.42), radius: w * 0.13, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        }
        // Pivot
        p.addEllipse(in: CGRect(x: w * 0.46, y: h * 0.1, width: w * 0.08, height: w * 0.08))
        return p
    }
}

private struct PedimentShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        // Triangular pediment
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.3))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.3))
        p.closeSubpath()
        // Entablature
        p.move(to: CGPoint(x: w * 0.1, y: h * 0.32))
        p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.32))
        // Columns
        for i in 0..<4 {
            let x = w * (0.2 + CGFloat(i) * 0.2)
            p.move(to: CGPoint(x: x, y: h * 0.34))
            p.addLine(to: CGPoint(x: x, y: h * 0.82))
        }
        // Steps
        p.move(to: CGPoint(x: w * 0.06, y: h * 0.84))
        p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.84))
        p.move(to: CGPoint(x: w * 0.0, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 1.0, y: h * 0.92))
        return p
    }
}

private struct QuillShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        // Feather spine, curved from tip to nib
        p.move(to: CGPoint(x: w * 0.82, y: h * 0.1))
        p.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.88),
                    control1: CGPoint(x: w * 0.5, y: h * 0.2),
                    control2: CGPoint(x: w * 0.35, y: h * 0.6))
        // Barbs, alternating either side of the spine
        let steps = 6
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps + 1)
            let x = w * (0.82 - 0.5 * t)
            let y = h * (0.1 + 0.62 * t)
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + w * 0.14, y: y - h * 0.03))
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x - w * 0.1, y: y + h * 0.05))
        }
        // Inkwell
        p.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.86, width: w * 0.26, height: h * 0.08))
        p.move(to: CGPoint(x: w * 0.1, y: h * 0.88))
        p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.98))
        p.addLine(to: CGPoint(x: w * 0.3, y: h * 0.98))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.88))
        return p
    }
}

private struct BottleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        // Neck
        p.move(to: CGPoint(x: w * 0.42, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.28, y: h * 0.78))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.9),
                    control1: CGPoint(x: w * 0.28, y: h * 0.86),
                    control2: CGPoint(x: w * 0.38, y: h * 0.9))
        p.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.78),
                    control1: CGPoint(x: w * 0.62, y: h * 0.9),
                    control2: CGPoint(x: w * 0.72, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.62))
        p.move(to: CGPoint(x: w * 0.58, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.08))
        // Cork
        p.move(to: CGPoint(x: w * 0.4, y: h * 0.06))
        p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.06))
        // Spill puddle + drips
        p.addEllipse(in: CGRect(x: w * 0.66, y: h * 0.86, width: w * 0.28, height: h * 0.06))
        p.move(to: CGPoint(x: w * 0.72, y: h * 0.6))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.84))
        return p
    }
}

private struct OpenBookShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        let spineX = w * 0.5
        let topY = h * 0.22
        let bottomY = h * 0.82
        // Left leaf
        p.move(to: CGPoint(x: spineX, y: topY))
        p.addCurve(to: CGPoint(x: w * 0.08, y: topY + h * 0.06),
                    control1: CGPoint(x: w * 0.3, y: topY - h * 0.04),
                    control2: CGPoint(x: w * 0.16, y: topY - h * 0.02))
        p.addLine(to: CGPoint(x: w * 0.08, y: bottomY))
        p.addCurve(to: CGPoint(x: spineX, y: bottomY - h * 0.06),
                    control1: CGPoint(x: w * 0.16, y: bottomY + h * 0.02),
                    control2: CGPoint(x: w * 0.3, y: bottomY + h * 0.04))
        p.closeSubpath()
        // Right leaf (mirror)
        p.move(to: CGPoint(x: spineX, y: topY))
        p.addCurve(to: CGPoint(x: w * 0.92, y: topY + h * 0.06),
                    control1: CGPoint(x: w * 0.7, y: topY - h * 0.04),
                    control2: CGPoint(x: w * 0.84, y: topY - h * 0.02))
        p.addLine(to: CGPoint(x: w * 0.92, y: bottomY))
        p.addCurve(to: CGPoint(x: spineX, y: bottomY - h * 0.06),
                    control1: CGPoint(x: w * 0.84, y: bottomY + h * 0.02),
                    control2: CGPoint(x: w * 0.7, y: bottomY + h * 0.04))
        p.closeSubpath()
        // Text lines on each leaf
        for i in 0..<3 {
            let y = topY + h * (0.18 + CGFloat(i) * 0.14)
            p.move(to: CGPoint(x: w * 0.16, y: y))
            p.addLine(to: CGPoint(x: w * 0.4, y: y))
            p.move(to: CGPoint(x: w * 0.6, y: y))
            p.addLine(to: CGPoint(x: w * 0.84, y: y))
        }
        return p
    }
}

private struct SealShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (w, h) = (r.width, r.height)
        let center = CGPoint(x: w * 0.5, y: h * 0.42)
        let radius = w * 0.3
        // Ribbon tails
        p.move(to: CGPoint(x: w * 0.38, y: h * 0.66))
        p.addLine(to: CGPoint(x: w * 0.3, y: h * 0.94))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.98))
        p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.86))
        p.addLine(to: CGPoint(x: w * 0.7, y: h * 0.94))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.66))
        // Outer seal edge (scalloped-ish via two circles)
        p.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        p.addEllipse(in: CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.62, width: radius * 1.24, height: radius * 1.24))
        // A simple mark at the centre (an "E" cipher stand-in — an equal-armed cross)
        p.move(to: CGPoint(x: center.x - radius * 0.28, y: center.y))
        p.addLine(to: CGPoint(x: center.x + radius * 0.28, y: center.y))
        p.move(to: CGPoint(x: center.x, y: center.y - radius * 0.28))
        p.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.28))
        return p
    }
}
