import SwiftUI

/// Engraved line illustration for a module (Lessons tab cards, lesson overview).
/// Same house style as `RatioSpotArt` — stroked SwiftUI `Shape`s, no fills, generic
/// objects, never people — with a little more engraving character: parallel hatching
/// for shade on one side of an object and double outlines where they help. Each shape
/// is drawn in a unit (0…1) square and scaled to its rect; colour comes from the
/// foreground style.
struct ModuleIllustration: View {
    let module: Module

    var body: some View {
        shape
            .stroke(style: Self.strokeStyle)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    private static let strokeStyle = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)

    private var shape: AnyShape {
        switch module {
        case .crime: AnyShape(HandcuffsGavelShape())
        case .contract: AnyShape(SealedDeedShape())
        case .tort: AnyShape(SnailBottleShape())
        case .publicLaw: AnyShape(PortcullisShape())
        case .landLaw: AnyShape(BoundaryMapKeyShape())
        case .equityTrusts: AnyShape(ScalesDeedShape())
        case .companyLaw: AnyShape(ShareCertificateShape())
        case .euLaw: AnyShape(StarRingShape())
        case .humanRights: AnyShape(HandLaurelShape())
        case .jurisprudence: AnyShape(ColumnScrollShape())
        case .employmentLaw: AnyShape(BriefcaseClockShape())
        case .familyLaw: AnyShape(LinkedRingsShape())
        case .sqeDisputeResolution: AnyShape(BundleGavelShape())
        case .sqeLegalSystem: AnyShape(CourtsArchShape())
        case .sqeBusinessLaw: AnyShape(LedgerHandshakeShape())
        case .sqePropertyPractice: AnyShape(TerraceDeedsShape())
        case .sqeWills: AnyShape(WillQuillShape())
        case .sqeAccounts: AnyShape(AccountBookShape())
        case .sqeCriminalPractice: AnyShape(BlueLampClipboardShape())
        }
    }
}

// MARK: - Shapes

/// Crime — a gavel over a pair of handcuffs.
private struct HandcuffsGavelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Gavel, drawn level about the head's centre, then tilted
        var g = Path()
        // Head: a cylinder, near end face as a full ellipse, far end as a half
        g.polyline([pt(-0.2, -0.075), pt(0.2, -0.075)])
        g.polyline([pt(-0.2, 0.075), pt(0.2, 0.075)])
        g.ellipse(pt(-0.2, 0), 0.03, 0.075)
        g.arc(pt(0.2, 0), 0.03, 0.075, from: -90, to: 90)
        // Turned bands near each end
        for x in [-0.13, 0.11] as [CGFloat] {
            g.arc(pt(x, 0), 0.02, 0.075, from: -90, to: 90)
        }
        // Shade along the underside of the head
        g.hatch([pt(-0.17, 0.025), pt(0.2, 0.025), pt(0.2, 0.075), pt(-0.17, 0.075)], spacing: 0.022, inset: 0.012)
        // Handle, with a shade line and a rounded end
        g.polyline([pt(-0.022, 0.075), pt(-0.022, 0.44)])
        g.polyline([pt(0.022, 0.075), pt(0.022, 0.44)])
        g.polyline([pt(0.008, 0.11), pt(0.008, 0.42)])
        g.arc(pt(0, 0.44), 0.022, 0.02, from: 0, to: 180)
        p.addPath(g, transform: CGAffineTransform(translationX: 0.38, y: 0.26).rotated(by: -.pi / 4))
        // Handcuffs: two cuffs, each a band with radial shade on its lower right
        for c in [pt(0.24, 0.74), pt(0.72, 0.74)] {
            p.circle(c, 0.13)
            p.circle(c, 0.09)
            p.radialHatch(c, from: 0.097, to: 0.123, angles: stride(from: 5.0, through: 105.0, by: 12.5))
        }
        // Chain between the cuffs: flat, edge-on, flat links
        p.ellipse(pt(0.41, 0.74), 0.045, 0.022)
        p.ellipse(pt(0.48, 0.74), 0.014, 0.03)
        p.ellipse(pt(0.55, 0.74), 0.045, 0.022)
        return p.scaled(to: r)
    }
}

/// Contract — a signed deed with a wax seal and ribbon.
private struct SealedDeedShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Sheet with a turned-down corner
        p.polyline([pt(0.7, 0.08), pt(0.12, 0.08), pt(0.12, 0.84), pt(0.84, 0.84), pt(0.84, 0.22), pt(0.7, 0.08)])
        p.polyline([pt(0.7, 0.08), pt(0.7, 0.22), pt(0.84, 0.22)])
        p.hatch([pt(0.7, 0.08), pt(0.7, 0.22), pt(0.84, 0.22)], spacing: 0.03, angle: .degrees(90), inset: 0.012)
        // Second sheet beneath (double outline on the shaded side)
        p.polyline([pt(0.15, 0.84), pt(0.15, 0.87), pt(0.87, 0.87), pt(0.87, 0.25), pt(0.84, 0.25)])
        // Heading and body text
        p.polyline([pt(0.28, 0.17), pt(0.56, 0.17)])
        for (i, end) in ([0.76, 0.76, 0.76, 0.52] as [CGFloat]).enumerated() {
            let y = 0.28 + CGFloat(i) * 0.08
            p.polyline([pt(0.2, y), pt(end, y)])
        }
        // Signature flourish over its line
        p.move(to: pt(0.2, 0.68))
        p.addCurve(to: pt(0.3, 0.62), control1: pt(0.22, 0.6), control2: pt(0.27, 0.58))
        p.addCurve(to: pt(0.38, 0.66), control1: pt(0.32, 0.7), control2: pt(0.35, 0.7))
        p.addCurve(to: pt(0.46, 0.63), control1: pt(0.41, 0.6), control2: pt(0.43, 0.6))
        p.polyline([pt(0.18, 0.74), pt(0.48, 0.74)])
        // Ribbon tails under the seal
        p.polyline([pt(0.6, 0.78), pt(0.55, 0.94), pt(0.6, 0.91), pt(0.63, 0.95), pt(0.66, 0.8)])
        p.polyline([pt(0.7, 0.8), pt(0.74, 0.94), pt(0.77, 0.9), pt(0.81, 0.93), pt(0.76, 0.78)])
        // Wax seal: scalloped rim, inner die, die shaded solid
        let c = pt(0.67, 0.68)
        p.closedPolygon((0..<120).map { i -> CGPoint in
            let t = CGFloat(i) / 120 * 2 * .pi
            let rad = 0.12 + 0.008 * cos(16 * t)
            return CGPoint(x: c.x + rad * cos(t), y: c.y + rad * sin(t))
        })
        p.circle(c, 0.075)
        p.hatch(arcPoints(c, 0.075, 0.075, from: 0, to: 360), spacing: 0.028, angle: .degrees(-45), inset: 0.01)
        return p.scaled(to: r)
    }
}

/// Tort — the snail in the ginger-beer bottle (Donoghue v Stevenson).
private struct SnailBottleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Bottle outline: lip, neck, shoulders, body, rounded foot
        p.move(to: pt(0.44, 0.13))
        p.addLine(to: pt(0.44, 0.24))
        p.addCurve(to: pt(0.27, 0.42), control1: pt(0.44, 0.32), control2: pt(0.27, 0.32))
        p.addLine(to: pt(0.27, 0.86))
        p.addQuadCurve(to: pt(0.32, 0.91), control: pt(0.27, 0.91))
        p.addLine(to: pt(0.68, 0.91))
        p.addQuadCurve(to: pt(0.73, 0.86), control: pt(0.73, 0.91))
        p.addLine(to: pt(0.73, 0.42))
        p.addCurve(to: pt(0.56, 0.24), control1: pt(0.73, 0.32), control2: pt(0.56, 0.32))
        p.addLine(to: pt(0.56, 0.13))
        // Lip ring and stopper
        p.rect(0.425, 0.1, 0.15, 0.035)
        p.polyline([pt(0.46, 0.1), pt(0.46, 0.07), pt(0.54, 0.07), pt(0.54, 0.1)])
        // Liquid level
        p.polyline([pt(0.27, 0.5), pt(0.73, 0.5)])
        // Shade down the left of the body
        p.hatch([pt(0.27, 0.4), pt(0.33, 0.35), pt(0.33, 0.87), pt(0.27, 0.87)], spacing: 0.022, angle: .degrees(90), inset: 0.02)
        // Snail: spiral shell over a foot, head and eye stalks to the left
        let shell = pt(0.57, 0.73)
        p.polyline((0...90).map { i -> CGPoint in
            let f = CGFloat(i) / 90
            let t = f * 2.4 * 2 * .pi
            let rad = 0.11 * (1 - f * 0.92)
            return CGPoint(x: shell.x + rad * cos(t + .pi / 2), y: shell.y + rad * sin(t + .pi / 2))
        })
        p.move(to: pt(0.69, 0.86))
        p.addQuadCurve(to: pt(0.42, 0.86), control: pt(0.55, 0.88))
        p.addQuadCurve(to: pt(0.37, 0.79), control: pt(0.35, 0.85))
        p.addQuadCurve(to: pt(0.47, 0.8), control: pt(0.42, 0.76))
        p.polyline([pt(0.38, 0.79), pt(0.34, 0.69)])
        p.polyline([pt(0.41, 0.78), pt(0.41, 0.68)])
        p.circle(pt(0.34, 0.68), 0.012)
        p.circle(pt(0.41, 0.67), 0.012)
        return p.scaled(to: r)
    }
}

/// Public law — the Parliament portcullis, crowned, with its chains.
private struct PortcullisShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let bars: [CGFloat] = [0.32, 0.41, 0.5, 0.59, 0.68]
        let rails: [CGFloat] = [0.38, 0.5, 0.62]
        let bw: CGFloat = 0.013   // half-width of a bar
        // Crown: band, three points, orbs
        p.rect(0.37, 0.19, 0.26, 0.04)
        p.polyline([pt(0.37, 0.19), pt(0.36, 0.11), pt(0.43, 0.16), pt(0.5, 0.08), pt(0.57, 0.16), pt(0.64, 0.11), pt(0.63, 0.19)])
        for x in [0.36, 0.5, 0.64] as [CGFloat] { p.circle(pt(x, x == 0.5 ? 0.065 : 0.095), 0.013) }
        // Top beam
        p.rect(0.27, 0.25, 0.46, 0.04)
        // Upright bars: double lines ending in spikes
        for x in bars {
            p.polyline([pt(x - bw, 0.29), pt(x - bw, 0.74), pt(x, 0.8), pt(x + bw, 0.74), pt(x + bw, 0.29)])
        }
        // Cross rails: double lines, broken where the bars pass in front
        for y in rails {
            for (a, b) in zip([0.27] + bars.map { $0 + bw }, bars.map { $0 - bw } + [0.73]) {
                p.polyline([pt(a, y - 0.012), pt(b, y - 0.012)])
                p.polyline([pt(a, y + 0.012), pt(b, y + 0.012)])
            }
            // Rail ends
            p.polyline([pt(0.27, y - 0.012), pt(0.27, y + 0.012)])
            p.polyline([pt(0.73, y - 0.012), pt(0.73, y + 0.012)])
        }
        // Chains: rings at the beam ends, then links swagging down each side
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = { (u: CGFloat) in 0.5 + side * (u - 0.5) }
            p.circle(pt(x(0.25), 0.27), 0.02)
            let start = pt(x(0.235), 0.29), c1 = pt(x(0.12), 0.34), c2 = pt(x(0.1), 0.62), end = pt(x(0.22), 0.86)
            let n = 14
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                let (q, tangent) = cubic(start, c1, c2, end, t)
                let link = i.isMultiple(of: 2) ? Path(ellipseIn: CGRect(x: -0.02, y: -0.012, width: 0.04, height: 0.024))
                                                : Path(ellipseIn: CGRect(x: -0.02, y: -0.005, width: 0.04, height: 0.01))
                p.addPath(link, transform: CGAffineTransform(translationX: q.x, y: q.y).rotated(by: atan2(tangent.y, tangent.x)))
            }
        }
        return p.scaled(to: r)
    }
}

/// Land law — a plan of a plot (dashed dividing boundary, compass) and a key.
private struct BoundaryMapKeyShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Map sheet, with a second edge on the shaded side
        p.rect(0.08, 0.08, 0.62, 0.56)
        p.polyline([pt(0.11, 0.64), pt(0.11, 0.67), pt(0.73, 0.67), pt(0.73, 0.11), pt(0.7, 0.11)])
        // Plot outline
        let plot = [pt(0.15, 0.22), pt(0.36, 0.15), pt(0.53, 0.26), pt(0.5, 0.55), pt(0.2, 0.57), pt(0.13, 0.4)]
        p.closedPolygon(plot)
        // Dashed boundary dividing the plot; the left parcel hatched
        p.dashes(from: pt(0.36, 0.15), to: pt(0.34, 0.56), dash: 0.035, gap: 0.025)
        p.hatch([pt(0.15, 0.22), pt(0.36, 0.15), pt(0.34, 0.56), pt(0.2, 0.57), pt(0.13, 0.4)], spacing: 0.036, angle: .degrees(-45), inset: 0.015)
        // Compass: ring and a north needle, one half shaded
        let c = pt(0.61, 0.2)
        p.circle(c, 0.045)
        p.closedPolygon([pt(0.61, 0.13), pt(0.625, 0.2), pt(0.61, 0.27), pt(0.595, 0.2)])
        p.polyline([pt(0.61, 0.145), pt(0.61, 0.2)])
        p.polyline([pt(0.598, 0.115), pt(0.598, 0.085), pt(0.622, 0.115), pt(0.622, 0.085)])
        // Key, drawn level from its bow leftwards, then tilted
        var k = Path()
        k.circle(.zero, 0.1)
        k.circle(.zero, 0.055)
        k.radialHatch(.zero, from: 0.062, to: 0.093, angles: stride(from: 10.0, through: 120.0, by: 14.0))
        // Shank with collar rings
        k.polyline([pt(-0.1, -0.016), pt(-0.46, -0.016)])
        k.polyline([pt(-0.1, 0.016), pt(-0.46, 0.016)])
        k.polyline([pt(-0.13, -0.026), pt(-0.13, 0.026)])
        k.polyline([pt(-0.155, -0.026), pt(-0.155, 0.026)])
        k.polyline([pt(-0.46, -0.016), pt(-0.46, 0.016)])
        // Bit, with wards cut
        k.polyline([pt(-0.45, 0.016), pt(-0.45, 0.1), pt(-0.41, 0.1), pt(-0.41, 0.07), pt(-0.38, 0.07), pt(-0.38, 0.1), pt(-0.35, 0.1), pt(-0.35, 0.016)])
        p.addPath(k, transform: CGAffineTransform(translationX: 0.8, y: 0.72).rotated(by: -.pi / 9))
        return p.scaled(to: r)
    }
}

/// Equity & Trusts — scales, with a rolled trust deed tied in ribbon.
private struct ScalesDeedShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let postX: CGFloat = 0.38
        // Finial and post (double line, shaded)
        p.circle(pt(postX, 0.1), 0.025)
        p.polyline([pt(postX - 0.014, 0.125), pt(postX - 0.014, 0.8)])
        p.polyline([pt(postX + 0.014, 0.125), pt(postX + 0.014, 0.8)])
        // Beam
        p.rect(0.12, 0.2, 0.52, 0.025)
        // Pans on their cords, shaded beneath
        for cx in [0.14, 0.62] as [CGFloat] {
            p.polyline([pt(cx - 0.1, 0.46), pt(cx, 0.225), pt(cx + 0.1, 0.46)])
            p.move(to: pt(cx - 0.11, 0.46))
            p.addLine(to: pt(cx + 0.11, 0.46))
            p.addQuadCurve(to: pt(cx - 0.11, 0.46), control: pt(cx, 0.6))
            p.hatch([pt(cx - 0.06, 0.48), pt(cx + 0.09, 0.48), pt(cx + 0.03, 0.52)], spacing: 0.02, angle: .degrees(90))
        }
        // Stepped base
        p.rect(0.28, 0.8, 0.2, 0.04)
        p.rect(0.24, 0.84, 0.28, 0.05)
        p.hatch([pt(0.24, 0.84), pt(0.52, 0.84), pt(0.52, 0.89), pt(0.24, 0.89)], spacing: 0.034, angle: .degrees(90), inset: 0.012)
        // Rolled deed: cylinder with a curled end, shaded along its underside
        p.polyline([pt(0.58, 0.73), pt(0.9, 0.73)])
        p.polyline([pt(0.58, 0.83), pt(0.9, 0.83)])
        p.ellipse(pt(0.58, 0.78), 0.022, 0.05)
        p.arc(pt(0.9, 0.78), 0.022, 0.05, from: -90, to: 90)
        p.ellipse(pt(0.582, 0.785), 0.01, 0.025)
        p.hatch([pt(0.6, 0.8), pt(0.9, 0.8), pt(0.9, 0.83), pt(0.6, 0.83)], spacing: 0.015, inset: 0.0)
        // Ribbon band and bow tails
        for x in [0.71, 0.74] as [CGFloat] { p.arc(pt(x, 0.78), 0.012, 0.05, from: -90, to: 90) }
        p.polyline([pt(0.72, 0.83), pt(0.68, 0.93), pt(0.71, 0.91), pt(0.72, 0.94)])
        p.polyline([pt(0.745, 0.83), pt(0.79, 0.92), pt(0.76, 0.91)])
        return p.scaled(to: r)
    }
}

/// Company law — a share certificate: ornate border, heading banner, seal, signature.
private struct ShareCertificateShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Double border with rosettes at the corners
        p.rect(0.06, 0.18, 0.88, 0.64)
        p.rect(0.11, 0.23, 0.78, 0.54)
        for (x, y) in [(0.085, 0.205), (0.915, 0.205), (0.085, 0.795), (0.915, 0.795)] as [(CGFloat, CGFloat)] {
            p.circle(pt(x, y), 0.016)
        }
        // Beading in the border band
        for i in 0..<9 {
            let x = 0.2 + CGFloat(i) * 0.075
            p.circle(pt(x, 0.205), 0.006)
            p.circle(pt(x, 0.795), 0.006)
        }
        for i in 0..<5 {
            let y = 0.3 + CGFloat(i) * 0.1
            p.circle(pt(0.085, y), 0.006)
            p.circle(pt(0.915, y), 0.006)
        }
        // Heading banner (arched ribbon with folded ends)
        p.move(to: pt(0.3, 0.36))
        p.addQuadCurve(to: pt(0.7, 0.36), control: pt(0.5, 0.26))
        p.move(to: pt(0.3, 0.42))
        p.addQuadCurve(to: pt(0.7, 0.42), control: pt(0.5, 0.32))
        p.polyline([pt(0.3, 0.36), pt(0.3, 0.42)])
        p.polyline([pt(0.7, 0.36), pt(0.7, 0.42)])
        p.polyline([pt(0.3, 0.37), pt(0.22, 0.37), pt(0.25, 0.4), pt(0.22, 0.43), pt(0.3, 0.43)])
        p.polyline([pt(0.7, 0.37), pt(0.78, 0.37), pt(0.75, 0.4), pt(0.78, 0.43), pt(0.7, 0.43)])
        // Body text
        p.polyline([pt(0.24, 0.5), pt(0.76, 0.5)])
        p.polyline([pt(0.3, 0.57), pt(0.7, 0.57)])
        // Company seal, lower left, shaded
        let c = pt(0.24, 0.66)
        p.closedPolygon((0..<24).map { i -> CGPoint in
            let t = CGFloat(i) / 24 * 2 * .pi
            let rad: CGFloat = i.isMultiple(of: 2) ? 0.07 : 0.055
            return CGPoint(x: c.x + rad * cos(t), y: c.y + rad * sin(t))
        })
        p.circle(c, 0.035)
        p.hatch(arcPoints(c, 0.035, 0.035, from: -45, to: 135), spacing: 0.02, angle: .degrees(-45), inset: 0.006)
        // Signature over its line, lower right
        p.move(to: pt(0.56, 0.69))
        p.addCurve(to: pt(0.66, 0.66), control1: pt(0.58, 0.62), control2: pt(0.63, 0.62))
        p.addCurve(to: pt(0.76, 0.66), control1: pt(0.69, 0.71), control2: pt(0.72, 0.62))
        p.polyline([pt(0.54, 0.715), pt(0.8, 0.715)])
        return p.scaled(to: r)
    }
}

/// EU law — the ring of twelve five-pointed stars.
private struct StarRingShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let centre = pt(0.5, 0.5)
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let c = CGPoint(x: centre.x + 0.36 * cos(a), y: centre.y + 0.36 * sin(a))
            // Each star upright, as on the flag
            p.closedPolygon((0..<10).map { k -> CGPoint in
                let t = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let rad: CGFloat = k.isMultiple(of: 2) ? 0.068 : 0.027
                return CGPoint(x: c.x + rad * cos(t), y: c.y + rad * sin(t))
            })
        }
        return p.scaled(to: r)
    }
}

/// Human rights — a raised open hand within a laurel wreath.
private struct HandLaurelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Hand: wrist, thumb, four fingers, palm edge
        var h = Path()
        h.move(to: pt(0.42, 0.88))
        h.addLine(to: pt(0.42, 0.78))
        h.addCurve(to: pt(0.28, 0.55), control1: pt(0.37, 0.73), control2: pt(0.3, 0.63))
        h.addQuadCurve(to: pt(0.33, 0.49), control: pt(0.25, 0.47))
        h.addCurve(to: pt(0.4, 0.58), control1: pt(0.36, 0.51), control2: pt(0.38, 0.56))
        let fingers: [(x: CGFloat, top: CGFloat, base: CGFloat)] = [(0.4, 0.22, 0.49), (0.47, 0.17, 0.46), (0.54, 0.2, 0.47), (0.61, 0.29, 0.5)]
        let fw: CGFloat = 0.066
        for f in fingers {
            h.addLine(to: pt(f.x, f.top + fw / 2))
            h.addArc(center: pt(f.x + fw / 2, f.top + fw / 2), radius: fw / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            h.addLine(to: pt(f.x + fw, f.base))
        }
        h.addLine(to: pt(0.676, 0.64))
        h.addCurve(to: pt(0.62, 0.78), control1: pt(0.676, 0.7), control2: pt(0.64, 0.74))
        h.addLine(to: pt(0.62, 0.88))
        // Palm creases
        h.move(to: pt(0.43, 0.61))
        h.addQuadCurve(to: pt(0.49, 0.76), control: pt(0.42, 0.7))
        h.move(to: pt(0.5, 0.57))
        h.addQuadCurve(to: pt(0.64, 0.56), control: pt(0.57, 0.6))
        // Shade down the heel of the palm
        h.hatch([pt(0.6, 0.62), pt(0.67, 0.62), pt(0.66, 0.71), pt(0.62, 0.77), pt(0.6, 0.77)], spacing: 0.032, inset: 0.012)
        p.addPath(h, transform: CGAffineTransform(translationX: 0.03, y: 0))
        // Laurel: two branches curving up from a tie at the foot, leaves along each
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = { (u: CGFloat) in 0.5 + side * (u - 0.5) }
            let start = pt(x(0.46), 0.92), c1 = pt(x(0.2), 0.9), c2 = pt(x(0.1), 0.62), end = pt(x(0.2), 0.3)
            p.move(to: start)
            p.addCurve(to: end, control1: c1, control2: c2)
            for i in 1...7 {
                let t = CGFloat(i) / 7.6
                let (q, tangent) = cubic(start, c1, c2, end, t)
                let a = atan2(tangent.y, tangent.x)
                for turn in [side * 0.75, -side * 0.75] where i.isMultiple(of: 2) || turn == side * 0.75 {
                    p.leaf(at: q, angle: a - turn, length: 0.085, width: 0.03)
                }
            }
            p.leaf(at: end, angle: -.pi / 2 + side * 0.25, length: 0.08, width: 0.03)
        }
        return p.scaled(to: r)
    }
}

/// Jurisprudence — an Ionic column beside an open scroll.
private struct ColumnScrollShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Capital: abacus, echinus, spiral volutes
        p.rect(0.12, 0.12, 0.36, 0.035)
        p.polyline([pt(0.16, 0.155), pt(0.44, 0.155)])
        p.polyline([pt(0.16, 0.2), pt(0.44, 0.2)])
        for (cx, dir) in [(0.17, -1.0), (0.43, 1.0)] as [(CGFloat, CGFloat)] {
            p.polyline((0...40).map { i -> CGPoint in
                let f = CGFloat(i) / 40
                let t = f * 2.2 * .pi
                let rad = 0.045 * (1 - f * 0.8)
                return CGPoint(x: cx + dir * rad * sin(t), y: 0.2 - rad * cos(t))
            })
        }
        // Shaft: slight taper, fluting, heavier shade on the right
        p.polyline([pt(0.2, 0.24), pt(0.21, 0.78)])
        p.polyline([pt(0.4, 0.24), pt(0.39, 0.78)])
        for x in [0.25, 0.29, 0.33, 0.355, 0.375] as [CGFloat] { p.polyline([pt(x, 0.26), pt(x, 0.76)]) }
        // Base: torus and plinth
        p.rect(0.18, 0.78, 0.24, 0.04)
        p.rect(0.13, 0.82, 0.34, 0.06)
        p.hatch([pt(0.13, 0.82), pt(0.47, 0.82), pt(0.47, 0.88), pt(0.13, 0.88)], spacing: 0.034, angle: .degrees(90), inset: 0.012)
        // Scroll: sheet between two rolls, lines of text
        p.polyline([pt(0.59, 0.26), pt(0.59, 0.76)])
        p.polyline([pt(0.85, 0.26), pt(0.85, 0.76)])
        for y in [0.21, 0.81] as [CGFloat] {
            p.polyline([pt(0.56, y - 0.05), pt(0.88, y - 0.05)])
            p.polyline([pt(0.56, y + 0.05), pt(0.88, y + 0.05)])
            p.ellipse(pt(0.56, y), 0.022, 0.05)
            p.ellipse(pt(0.56, y), 0.009, 0.022)
            p.arc(pt(0.88, y), 0.022, 0.05, from: -90, to: 90)
            p.hatch([pt(0.58, y + 0.02), pt(0.88, y + 0.02), pt(0.88, y + 0.05), pt(0.58, y + 0.05)], spacing: 0.015)
        }
        for (i, end) in ([0.8, 0.8, 0.8, 0.8, 0.72] as [CGFloat]).enumerated() {
            let y = 0.35 + CGFloat(i) * 0.075
            p.polyline([pt(0.64, y), pt(end, y)])
        }
        return p.scaled(to: r)
    }
}

/// Employment law — a briefcase under a clock.
private struct BriefcaseClockShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Clock: double rim with radial shade, hour ticks, hands at ten past ten
        let c = pt(0.66, 0.27)
        p.circle(c, 0.19)
        p.circle(c, 0.15)
        p.radialHatch(c, from: 0.157, to: 0.183, angles: stride(from: 0.0, through: 110.0, by: 10.0))
        for i in 0..<12 {
            let a = CGFloat(i) / 12 * 2 * .pi
            let inner: CGFloat = i.isMultiple(of: 3) ? 0.105 : 0.125
            p.polyline([CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a)),
                        CGPoint(x: c.x + 0.14 * cos(a), y: c.y + 0.14 * sin(a))])
        }
        let hour = CGFloat.pi * (-90 + 10 * 30 + 5) / 180, minute = CGFloat.pi * (-90 + 60) / 180
        p.polyline([c, CGPoint(x: c.x + 0.065 * cos(hour), y: c.y + 0.065 * sin(hour))])
        p.polyline([c, CGPoint(x: c.x + 0.1 * cos(minute), y: c.y + 0.1 * sin(minute))])
        p.circle(c, 0.01)
        // Briefcase: body, gusset in perspective (shaded), flap, clasps, handle
        p.rect(0.08, 0.54, 0.6, 0.36)
        p.polyline([pt(0.68, 0.54), pt(0.75, 0.5), pt(0.75, 0.85), pt(0.68, 0.9)])
        p.polyline([pt(0.08, 0.54), pt(0.15, 0.5), pt(0.75, 0.5)])
        p.hatch([pt(0.68, 0.54), pt(0.75, 0.5), pt(0.75, 0.85), pt(0.68, 0.9)], spacing: 0.03, angle: .degrees(90), inset: 0.012)
        p.polyline([pt(0.08, 0.65), pt(0.68, 0.65)])
        p.rect(0.19, 0.62, 0.05, 0.06)
        p.rect(0.52, 0.62, 0.05, 0.06)
        p.move(to: pt(0.3, 0.52))
        p.addLine(to: pt(0.3, 0.44))
        p.addQuadCurve(to: pt(0.34, 0.4), control: pt(0.3, 0.4))
        p.addLine(to: pt(0.44, 0.4))
        p.addQuadCurve(to: pt(0.48, 0.44), control: pt(0.48, 0.4))
        p.addLine(to: pt(0.48, 0.52))
        p.polyline([pt(0.33, 0.52), pt(0.33, 0.445), pt(0.45, 0.445), pt(0.45, 0.52)])
        return p.scaled(to: r)
    }
}

/// Family law — two interlinked rings.
private struct LinkedRingsShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let a = pt(0.37, 0.5), b = pt(0.63, 0.5)
        let (outer, inner, gap): (CGFloat, CGFloat, CGFloat) = (0.25, 0.195, 0.022)
        // Whether a point on one ring is hidden where it passes under the other band
        func under(_ q: CGPoint, _ other: CGPoint) -> Bool {
            let d = hypot(q.x - other.x, q.y - other.y)
            return d > inner - gap && d < outer + gap
        }
        // Left ring dips under the right at the bottom crossing; the right under the left at the top
        let rings: [(CGPoint, CGPoint, (CGPoint) -> Bool)] = [
            (a, b, { $0.y > 0.5 }),
            (b, a, { $0.y < 0.5 }),
        ]
        for (c, other, side) in rings {
            let hidden = { (q: CGPoint) in side(q) && under(q, other) }
            for rad in [outer, inner] {
                p.brokenPolyline(arcPoints(c, rad, rad, from: 0, to: 360, count: 180), hidden: hidden)
            }
            // Radial shade across the lower right of the band
            for deg in stride(from: 0.0, through: 110.0, by: 9.0) {
                let t = CGFloat(deg) * .pi / 180
                let q0 = CGPoint(x: c.x + (inner + 0.009) * cos(t), y: c.y + (inner + 0.009) * sin(t))
                let q1 = CGPoint(x: c.x + (outer - 0.009) * cos(t), y: c.y + (outer - 0.009) * sin(t))
                if !hidden(q0) && !hidden(q1) && !under(q0, other) { p.polyline([q0, q1]) }
            }
        }
        return p.scaled(to: r)
    }
}

/// SQE Dispute resolution — a court bundle tied in tape, tabbed dividers, and a gavel.
private struct BundleGavelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Bundle cover, with the sheets beneath showing along the shaded edges
        p.rect(0.08, 0.32, 0.5, 0.54)
        p.polyline([pt(0.1, 0.86), pt(0.1, 0.88), pt(0.6, 0.88), pt(0.6, 0.34), pt(0.58, 0.34)])
        p.polyline([pt(0.12, 0.88), pt(0.12, 0.9), pt(0.62, 0.9), pt(0.62, 0.36), pt(0.6, 0.36)])
        // Tabbed dividers standing proud of the right edge, alternate tabs shaded
        for (i, y) in ([0.42, 0.53, 0.64, 0.75] as [CGFloat]).enumerated() {
            let tab = [pt(0.62, y), pt(0.68, y + 0.01), pt(0.68, y + 0.05), pt(0.62, y + 0.06)]
            p.polyline(tab)
            if i.isMultiple(of: 2) { p.hatch(tab, spacing: 0.018, inset: 0.008) }
        }
        // Backsheet label, top left
        p.rect(0.13, 0.37, 0.2, 0.13)
        p.polyline([pt(0.16, 0.415), pt(0.3, 0.415)])
        p.polyline([pt(0.16, 0.455), pt(0.26, 0.455)])
        // Tape: one band down, one across, broken at the knot
        let knot = CGRect(x: 0.395, y: 0.615, width: 0.04, height: 0.04)
        for x in [0.4, 0.43] as [CGFloat] {
            p.polyline([pt(x, 0.32), pt(x, knot.minY)])
            p.polyline([pt(x, knot.maxY), pt(x, 0.86)])
        }
        for y in [0.62, 0.65] as [CGFloat] {
            p.polyline([pt(0.08, y), pt(knot.minX, y)])
            p.polyline([pt(knot.maxX, y), pt(0.58, y)])
        }
        // Shade down the right of the cover, either side of the tape
        for (top, bottom) in [(0.32, 0.62), (0.65, 0.86)] as [(CGFloat, CGFloat)] {
            p.hatch([pt(0.48, top), pt(0.58, top), pt(0.58, bottom), pt(0.48, bottom)], spacing: 0.03, angle: .degrees(90), inset: 0.012)
        }
        // Bow: knot, two loops, two tails
        p.addRect(knot)
        p.leaf(at: pt(knot.minX, knot.minY + 0.01), angle: -.pi * 0.8, length: 0.12, width: 0.05)
        p.leaf(at: pt(knot.maxX, knot.minY + 0.01), angle: -.pi * 0.2, length: 0.12, width: 0.05)
        p.polyline([pt(0.4, knot.maxY), pt(0.33, 0.76), pt(0.36, 0.75), pt(0.35, 0.79)])
        p.polyline([pt(0.43, knot.maxY), pt(0.5, 0.75), pt(0.47, 0.745), pt(0.49, 0.78)])
        // Gavel, drawn level about the head's centre, then scaled and tilted
        var g = Path()
        g.polyline([pt(-0.2, -0.075), pt(0.2, -0.075)])
        g.polyline([pt(-0.2, 0.075), pt(0.2, 0.075)])
        g.ellipse(pt(-0.2, 0), 0.03, 0.075)
        g.arc(pt(0.2, 0), 0.03, 0.075, from: -90, to: 90)
        for x in [-0.13, 0.11] as [CGFloat] {
            g.arc(pt(x, 0), 0.02, 0.075, from: -90, to: 90)
        }
        g.hatch([pt(-0.17, 0.025), pt(0.2, 0.025), pt(0.2, 0.075), pt(-0.17, 0.075)], spacing: 0.024, inset: 0.012)
        g.polyline([pt(-0.022, 0.075), pt(-0.022, 0.44)])
        g.polyline([pt(0.022, 0.075), pt(0.022, 0.44)])
        g.polyline([pt(0.008, 0.11), pt(0.008, 0.42)])
        g.arc(pt(0, 0.44), 0.022, 0.02, from: 0, to: 180)
        p.addPath(g, transform: CGAffineTransform(translationX: 0.68, y: 0.17).rotated(by: -.pi / 4).scaledBy(x: 0.78, y: 0.78))
        return p.scaled(to: r)
    }
}

/// SQE Legal system — the Royal Courts of Justice entrance: a Gothic arch with tracery
/// under a gable, between two spired turrets.
private struct CourtsArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Ground line and step
        p.polyline([pt(0.06, 0.9), pt(0.94, 0.9)])
        p.polyline([pt(0.3, 0.9), pt(0.3, 0.875), pt(0.7, 0.875), pt(0.7, 0.9)])
        // Turrets: shaft, corbel band, spire, a lancet or two, shade on the right face
        for x in [0.1, 0.78] as [CGFloat] {
            p.polyline([pt(x, 0.9), pt(x, 0.3)])
            p.polyline([pt(x + 0.12, 0.9), pt(x + 0.12, 0.3)])
            p.rect(x - 0.015, 0.27, 0.15, 0.03)
            p.polyline([pt(x, 0.27), pt(x + 0.06, 0.08), pt(x + 0.12, 0.27)])
            p.polyline([pt(x + 0.06, 0.08), pt(x + 0.075, 0.27)])
            p.circle(pt(x + 0.06, 0.065), 0.013)
            for (spring, sill) in [(0.4, 0.46), (0.6, 0.7)] as [(CGFloat, CGFloat)] {
                p.closedPolygon([pt(x + 0.035, sill)] + pointedArch(x + 0.035, x + 0.07, spring: spring) + [pt(x + 0.07, sill)])
            }
            p.polyline([pt(x + 0.1, 0.32), pt(x + 0.1, 0.88)])
            p.hatch([pt(x + 0.075, 0.27), pt(x + 0.06, 0.08), pt(x + 0.12, 0.27)], spacing: 0.024, angle: .degrees(90), inset: 0.012)
        }
        // Wall between the turrets, and a small lancet either side of the arch
        p.polyline([pt(0.22, 0.4), pt(0.3, 0.4)])
        p.polyline([pt(0.7, 0.4), pt(0.78, 0.4)])
        for a in [0.245, 0.705] as [CGFloat] {
            p.closedPolygon([pt(a, 0.66)] + pointedArch(a, a + 0.05, spring: 0.54) + [pt(a + 0.05, 0.66)])
        }
        // Gable over the arch, doubled, with a finial
        p.polyline([pt(0.26, 0.4), pt(0.5, 0.14), pt(0.74, 0.4)])
        p.polyline([pt(0.3, 0.4), pt(0.5, 0.185), pt(0.7, 0.4)])
        p.circle(pt(0.5, 0.12), 0.014)
        // Arch: three receding orders down to the ground
        for (a, b) in [(0.32, 0.68), (0.345, 0.655), (0.37, 0.63)] as [(CGFloat, CGFloat)] {
            p.polyline([pt(a, 0.875)] + pointedArch(a, b, spring: 0.6) + [pt(b, 0.875)])
        }
        // Shade in the right-hand reveal
        p.hatch([pt(0.63, 0.6), pt(0.68, 0.6), pt(0.68, 0.875), pt(0.63, 0.875)], spacing: 0.03, inset: 0.008)
        // Tracery in the arch head: transom, two sub-arches, a quatrefoil in a roundel
        p.polyline([pt(0.37, 0.6), pt(0.63, 0.6)])
        p.polyline(pointedArch(0.37, 0.5, spring: 0.6))
        p.polyline(pointedArch(0.5, 0.63, spring: 0.6))
        p.circle(pt(0.5, 0.45), 0.042)
        for (dx, dy) in [(0.0, -0.018), (0.018, 0.0), (0.0, 0.018), (-0.018, 0.0)] as [(CGFloat, CGFloat)] {
            p.circle(pt(0.5 + dx, 0.45 + dy), 0.016)
        }
        // Double doors with panels
        p.polyline([pt(0.5, 0.6), pt(0.5, 0.875)])
        for x in [0.395, 0.525] as [CGFloat] {
            p.rect(x, 0.64, 0.08, 0.08)
            p.rect(x, 0.76, 0.08, 0.08)
        }
        return p.scaled(to: r)
    }
}

/// SQE Business law — a handshake over an open ledger.
private struct LedgerHandshakeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Sleeves and cuffs, one from each side
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = { (u: CGFloat) in 0.5 + side * (u - 0.5) }
            p.polyline([pt(x(0.04), 0.2), pt(x(0.2), 0.19)])
            p.polyline([pt(x(0.04), 0.42), pt(x(0.2), 0.41)])
            p.closedPolygon([pt(x(0.2), 0.17), pt(x(0.25), 0.17), pt(x(0.25), 0.43), pt(x(0.2), 0.43)])
            p.polyline([pt(x(0.06), 0.37), pt(x(0.2), 0.365)])
            p.polyline([pt(x(0.04), 0.2), pt(x(0.04), 0.42)])
        }
        // Left hand: back of the hand running in under the other's fingers, and its thumb
        // laid over the other hand's back
        p.move(to: pt(0.25, 0.21))
        p.addQuadCurve(to: pt(0.38, 0.22), control: pt(0.32, 0.2))
        p.move(to: pt(0.25, 0.4))
        p.addQuadCurve(to: pt(0.4, 0.41), control: pt(0.33, 0.43))
        p.move(to: pt(0.37, 0.22))
        p.addQuadCurve(to: pt(0.5, 0.17), control: pt(0.43, 0.15))
        p.addQuadCurve(to: pt(0.51, 0.215), control: pt(0.54, 0.19))
        p.addQuadCurve(to: pt(0.44, 0.235), control: pt(0.47, 0.22))
        // Right hand: back of the hand and palm edge from the cuff, fingers wrapped round
        p.move(to: pt(0.75, 0.21))
        p.addQuadCurve(to: pt(0.6, 0.2), control: pt(0.67, 0.19))
        p.move(to: pt(0.75, 0.4))
        p.addQuadCurve(to: pt(0.52, 0.41), control: pt(0.64, 0.43))
        let fingers: [(y: CGFloat, tip: CGFloat)] = [(0.235, 0.4), (0.28, 0.37), (0.325, 0.37), (0.37, 0.39)]
        let fh: CGFloat = 0.045
        for f in fingers {
            p.move(to: pt(0.53, f.y))
            p.addLine(to: pt(f.tip + fh / 2, f.y))
            p.addArc(center: pt(f.tip + fh / 2, f.y + fh / 2), radius: fh / 2, startAngle: .degrees(270), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: pt(0.53, f.y + fh))
        }
        // Knuckle line where the fingers turn
        p.move(to: pt(0.53, 0.235))
        p.addQuadCurve(to: pt(0.53, 0.415), control: pt(0.57, 0.325))
        // Open ledger: two pages curving to the gutter, the page block beneath
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = { (u: CGFloat) in 0.5 + side * (u - 0.5) }
            p.move(to: pt(x(0.1), 0.52))
            p.addQuadCurve(to: pt(0.5, 0.58), control: pt(x(0.3), 0.49))
            p.move(to: pt(x(0.1), 0.86))
            p.addQuadCurve(to: pt(0.5, 0.9), control: pt(x(0.3), 0.83))
            p.polyline([pt(x(0.1), 0.52), pt(x(0.1), 0.86)])
            p.move(to: pt(x(0.1), 0.86))
            p.polyline([pt(x(0.1), 0.86), pt(x(0.08), 0.88)])
            p.move(to: pt(x(0.08), 0.88))
            p.addQuadCurve(to: pt(0.5, 0.925), control: pt(x(0.3), 0.855))
            // Ruled lines following the page's curve, and two money columns
            let top = { (u: CGFloat) -> CGFloat in
                let t = (u - 0.1) / 0.4
                return (1 - t) * (1 - t) * 0.52 + 2 * t * (1 - t) * 0.49 + t * t * 0.58
            }
            for d in [0.07, 0.13, 0.19, 0.25] as [CGFloat] {
                p.polyline(stride(from: 0.14, through: 0.46, by: 0.02).map { pt(x($0), top($0) + d) })
            }
            for u in [0.36, 0.42] as [CGFloat] {
                p.polyline([pt(x(u), top(u) + 0.03), pt(x(u), top(u) + 0.29)])
            }
        }
        p.polyline([pt(0.5, 0.58), pt(0.5, 0.9)])
        return p.scaled(to: r)
    }
}

/// SQE Property practice — a Georgian terrace house with rolled title deeds before it.
private struct TerraceDeedsShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Chimney stacks with pots
        for x in [0.24, 0.68] as [CGFloat] {
            p.rect(x, 0.06, 0.08, 0.05)
            p.rect(x + 0.012, 0.035, 0.022, 0.025)
            p.rect(x + 0.046, 0.035, 0.022, 0.025)
        }
        // Parapet coping and facade; coping, string course and pavement run on into the terrace
        p.rect(0.18, 0.11, 0.64, 0.025)
        p.polyline([pt(0.1, 0.11), pt(0.18, 0.11)])
        p.polyline([pt(0.82, 0.11), pt(0.9, 0.11)])
        p.polyline([pt(0.2, 0.135), pt(0.2, 0.68), pt(0.8, 0.68), pt(0.8, 0.135)])
        p.polyline([pt(0.1, 0.48), pt(0.9, 0.48)])
        p.polyline([pt(0.1, 0.7), pt(0.9, 0.7)])
        // Sash windows: frame, meeting rail, glazing bar, flat-arch lintel, sill
        func window(_ cx: CGFloat, _ top: CGFloat, _ h: CGFloat) {
            let w: CGFloat = 0.09
            p.rect(cx - w / 2, top, w, h)
            p.polyline([pt(cx - w / 2, top + h / 2), pt(cx + w / 2, top + h / 2)])
            p.polyline([pt(cx, top), pt(cx, top + h)])
            p.polyline([pt(cx - w / 2 - 0.012, top - 0.015), pt(cx + w / 2 + 0.012, top - 0.015)])
            p.polyline([pt(cx - w / 2 - 0.01, top + h + 0.012), pt(cx + w / 2 + 0.01, top + h + 0.012)])
            p.hatch([pt(cx, top), pt(cx + w / 2, top), pt(cx + w / 2, top + h), pt(cx, top + h)], spacing: 0.02, angle: .degrees(90), inset: 0.008)
        }
        for cx in [0.3, 0.5, 0.7] as [CGFloat] {
            window(cx, 0.18, 0.07)
            window(cx, 0.3, 0.13)
        }
        window(0.5, 0.53, 0.1)
        window(0.7, 0.53, 0.1)
        // Front door: fanlight with radial bars, panelled door shaded dark, step
        let fan = pt(0.3, 0.56)
        p.arc(fan, 0.045, 0.045, from: 180, to: 360)
        p.radialHatch(fan, from: 0.012, to: 0.045, angles: stride(from: 210.0, through: 330.0, by: 30.0))
        p.polyline([pt(0.255, 0.56), pt(0.345, 0.56)])
        p.rect(0.255, 0.56, 0.09, 0.12)
        p.hatch([pt(0.255, 0.56), pt(0.345, 0.56), pt(0.345, 0.68), pt(0.255, 0.68)], spacing: 0.02, angle: .degrees(90), inset: 0.01)
        // Rolled deeds: one behind, one in front tied with ribbon, shaded beneath
        p.polyline([pt(0.4, 0.73), pt(0.88, 0.73)])
        p.polyline([pt(0.74, 0.81), pt(0.88, 0.81)])
        p.arc(pt(0.4, 0.77), 0.016, 0.04, from: 180, to: 360)
        p.arc(pt(0.88, 0.77), 0.016, 0.04, from: -90, to: 90)
        p.polyline([pt(0.12, 0.78), pt(0.72, 0.78)])
        p.polyline([pt(0.12, 0.9), pt(0.72, 0.9)])
        p.ellipse(pt(0.12, 0.84), 0.024, 0.06)
        p.ellipse(pt(0.122, 0.845), 0.011, 0.03)
        p.arc(pt(0.72, 0.84), 0.024, 0.06, from: -90, to: 90)
        p.hatch([pt(0.14, 0.86), pt(0.72, 0.86), pt(0.72, 0.9), pt(0.14, 0.9)], spacing: 0.014)
        for x in [0.42, 0.45] as [CGFloat] { p.arc(pt(x, 0.84), 0.014, 0.06, from: -90, to: 90) }
        p.polyline([pt(0.43, 0.9), pt(0.39, 0.95), pt(0.42, 0.94), pt(0.43, 0.96)])
        p.polyline([pt(0.455, 0.9), pt(0.5, 0.95), pt(0.47, 0.945)])
        return p.scaled(to: r)
    }
}

/// SQE Wills — a folded will closed with a wax seal, and a quill.
private struct WillQuillShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Folded packet, a second edge on the shaded side
        p.rect(0.08, 0.3, 0.54, 0.56)
        p.polyline([pt(0.11, 0.86), pt(0.11, 0.89), pt(0.65, 0.89), pt(0.65, 0.33), pt(0.62, 0.33)])
        // Flap folded down to a point, stopping at the seal, with its shadow beneath
        let seal = pt(0.35, 0.56)
        p.polyline([pt(0.08, 0.3), pt(0.285, 0.498)])
        p.polyline([pt(0.62, 0.3), pt(0.415, 0.498)])
        p.polyline([pt(0.08, 0.34), pt(0.275, 0.528)])
        p.polyline([pt(0.62, 0.34), pt(0.425, 0.528)])
        // Shade down the right of the packet
        p.hatch([pt(0.54, 0.6), pt(0.62, 0.6), pt(0.62, 0.86), pt(0.54, 0.86)], spacing: 0.028, angle: .degrees(90), inset: 0.012)
        // Endorsement on the outside
        p.polyline([pt(0.2, 0.72), pt(0.5, 0.72)])
        p.polyline([pt(0.25, 0.78), pt(0.45, 0.78)])
        // Wax seal: scalloped rim, inner die shaded
        p.closedPolygon((0..<120).map { i -> CGPoint in
            let t = CGFloat(i) / 120 * 2 * .pi
            let rad = 0.08 + 0.006 * cos(14 * t)
            return CGPoint(x: seal.x + rad * cos(t), y: seal.y + rad * sin(t))
        })
        p.circle(seal, 0.05)
        p.hatch(arcPoints(seal, 0.05, 0.05, from: 0, to: 360), spacing: 0.024, angle: .degrees(-45), inset: 0.008)
        // Quill, drawn level from the nib (origin) along +x, then stood up on the right
        var q = Path()
        // Barrel tapering to a slit nib
        q.polyline([pt(0, 0), pt(0.08, -0.014), pt(0.3, -0.014)])
        q.polyline([pt(0, 0), pt(0.08, 0.014), pt(0.3, 0.014)])
        q.polyline([pt(0.01, 0), pt(0.05, 0)])
        // Shaft running on to the tip
        q.polyline([pt(0.3, 0), pt(0.84, 0)])
        // Vane: broad on one side, narrow on the other, with a notch cut in the broad side
        q.move(to: pt(0.24, 0))
        q.addCurve(to: pt(0.5, -0.07), control1: pt(0.3, -0.05), control2: pt(0.4, -0.07))
        q.polyline([pt(0.5, -0.07), pt(0.54, -0.05), pt(0.56, -0.08)])
        q.addCurve(to: pt(0.86, 0), control1: pt(0.7, -0.085), control2: pt(0.82, -0.04))
        q.move(to: pt(0.28, 0))
        q.addCurve(to: pt(0.86, 0), control1: pt(0.45, 0.05), control2: pt(0.75, 0.04))
        // Barbs on the narrow, shaded side
        for x in stride(from: 0.36, through: 0.76, by: 0.04) as StrideThrough<CGFloat> {
            q.polyline([pt(x, 0.006), pt(x + 0.04, 0.026)])
        }
        p.addPath(q, transform: CGAffineTransform(translationX: 0.72, y: 0.93).rotated(by: -76 * .pi / 180))
        return p.scaled(to: r)
    }
}

/// SQE Accounts — a page of a two-column (debit and credit) account, ruled and cast.
private struct AccountBookShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Page with its lower corner turned up (shaded), sheets beneath
        p.polyline([pt(0.72, 0.9), pt(0.14, 0.9), pt(0.14, 0.08), pt(0.86, 0.08), pt(0.86, 0.76), pt(0.72, 0.9)])
        p.polyline([pt(0.72, 0.9), pt(0.74, 0.78), pt(0.86, 0.76)])
        p.hatch([pt(0.72, 0.9), pt(0.74, 0.78), pt(0.86, 0.76)], spacing: 0.025, angle: .degrees(-45), inset: 0.01)
        p.polyline([pt(0.17, 0.9), pt(0.17, 0.93), pt(0.73, 0.93)])
        p.polyline([pt(0.86, 0.79), pt(0.89, 0.79), pt(0.89, 0.11), pt(0.86, 0.11)])
        // Account heading and the T: a double rule across, a double rule down the middle
        p.polyline([pt(0.36, 0.14), pt(0.64, 0.14)])
        p.polyline([pt(0.14, 0.2), pt(0.86, 0.2)])
        p.polyline([pt(0.14, 0.215), pt(0.86, 0.215)])
        p.polyline([pt(0.493, 0.215), pt(0.493, 0.8)])
        p.polyline([pt(0.507, 0.215), pt(0.507, 0.8)])
        // Money column on each side
        p.polyline([pt(0.37, 0.215), pt(0.37, 0.8)])
        p.polyline([pt(0.74, 0.215), pt(0.74, 0.76)])
        // Entries: narrative and figure, one row each
        let debits: [(CGFloat, CGFloat)] = [(0.3, 0.4), (0.25, 0.42), (0.32, 0.39), (0.22, 0.41)]
        let credits: [(CGFloat, CGFloat)] = [(0.67, 0.77), (0.62, 0.79), (0.69, 0.76)]
        for (i, (text, figure)) in debits.enumerated() {
            let y = 0.28 + CGFloat(i) * 0.07
            p.polyline([pt(0.18, y), pt(text, y)])
            p.polyline([pt(figure, y), pt(0.475, y)])
        }
        for (i, (text, figure)) in credits.enumerated() {
            let y = 0.28 + CGFloat(i) * 0.07
            p.polyline([pt(0.54, y), pt(text, y)])
            p.polyline([pt(figure, y), pt(0.84, y)])
        }
        // Balance carried down, then both sides cast: rule, total, double rule
        p.polyline([pt(0.54, 0.49), pt(0.65, 0.49)])
        p.polyline([pt(0.79, 0.49), pt(0.84, 0.49)])
        for (a, b) in [(0.39, 0.475), (0.76, 0.84)] as [(CGFloat, CGFloat)] {
            p.polyline([pt(a, 0.6), pt(b, 0.6)])
            p.polyline([pt(a + 0.02, 0.65), pt(b, 0.65)])
            p.polyline([pt(a, 0.69), pt(b, 0.69)])
            p.polyline([pt(a, 0.705), pt(b, 0.705)])
        }
        return p.scaled(to: r)
    }
}

/// SQE Criminal practice — a police station's blue lamp on its bracket, and a custody
/// record on a clipboard.
private struct BlueLampClipboardShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let cx: CGFloat = 0.27
        // Wall plate, arm and scrolled brace
        p.rect(0.04, 0.05, 0.03, 0.2)
        p.polyline([pt(0.07, 0.09), pt(cx + 0.02, 0.09)])
        p.polyline([pt(0.07, 0.11), pt(cx + 0.02, 0.11)])
        p.move(to: pt(0.07, 0.22))
        p.addQuadCurve(to: pt(0.2, 0.11), control: pt(0.16, 0.2))
        p.polyline((0...30).map { i -> CGPoint in
            let f = CGFloat(i) / 30
            let t = f * 1.6 * .pi
            let rad = 0.025 * (1 - f * 0.7)
            return CGPoint(x: 0.1 + rad * cos(t + .pi / 2), y: 0.185 + rad * sin(t + .pi / 2))
        })
        // Hanging ring, finial and domed cap
        p.circle(pt(cx, 0.125), 0.014)
        p.circle(pt(cx, 0.152), 0.01)
        p.arc(pt(cx, 0.21), 0.06, 0.048, from: 180, to: 360)
        p.polyline([pt(cx - 0.06, 0.21), pt(cx + 0.06, 0.21)])
        // Roof and rim, overhanging the glass
        p.polyline([pt(cx - 0.06, 0.21), pt(cx - 0.13, 0.25), pt(cx + 0.13, 0.25), pt(cx + 0.06, 0.21)])
        p.rect(cx - 0.13, 0.25, 0.26, 0.02)
        p.hatch([pt(cx - 0.02, 0.215), pt(cx + 0.06, 0.215), pt(cx + 0.12, 0.25), pt(cx - 0.02, 0.25)], spacing: 0.02, angle: .degrees(90), inset: 0.004)
        // Glass: front face and a narrower side face in shade, tapering to the base
        let lt = pt(cx - 0.11, 0.27), lb = pt(cx - 0.08, 0.58)
        let ct = pt(cx + 0.05, 0.27), cb = pt(cx + 0.04, 0.58)
        let rt = pt(cx + 0.11, 0.27), rb = pt(cx + 0.08, 0.58)
        p.polyline([lt, lb])
        p.polyline([ct, cb])
        p.polyline([rt, rb])
        p.hatch([ct, rt, rb, cb], spacing: 0.02, angle: .degrees(90), inset: 0.006)
        // "POLICE" panel across the top of the front face: band with letter strokes
        p.polyline([pt(cx - 0.107, 0.3), pt(cx + 0.049, 0.3)])
        p.polyline([pt(cx - 0.102, 0.35), pt(cx + 0.048, 0.35)])
        for i in 0..<6 {
            let x = cx - 0.08 + CGFloat(i) * 0.022
            p.polyline([pt(x, 0.312), pt(x, 0.338)])
        }
        // Glazing bar, base rim, cone and drop
        p.polyline([pt(cx - 0.095, 0.46), pt(cx + 0.045, 0.46)])
        p.rect(cx - 0.09, 0.58, 0.18, 0.02)
        p.polyline([pt(cx - 0.08, 0.6), pt(cx, 0.68), pt(cx + 0.08, 0.6)])
        p.circle(pt(cx, 0.695), 0.015)
        // Clipboard: board with its edge showing, sheet, clip
        p.addRoundedRect(in: CGRect(x: 0.48, y: 0.26, width: 0.42, height: 0.66), cornerSize: CGSize(width: 0.03, height: 0.03))
        p.polyline([pt(0.51, 0.92), pt(0.51, 0.94), pt(0.9, 0.94), pt(0.92, 0.92), pt(0.92, 0.29), pt(0.9, 0.28)])
        p.polyline([pt(0.52, 0.3), pt(0.6, 0.3)])
        p.polyline([pt(0.78, 0.3), pt(0.86, 0.3)])
        p.polyline([pt(0.52, 0.3), pt(0.52, 0.88), pt(0.86, 0.88), pt(0.86, 0.3)])
        let clip = [pt(0.6, 0.32), pt(0.6, 0.25), pt(0.64, 0.21), pt(0.74, 0.21), pt(0.78, 0.25), pt(0.78, 0.32)]
        p.closedPolygon(clip)
        p.circle(pt(0.69, 0.245), 0.014)
        p.hatch([pt(0.6, 0.28), pt(0.78, 0.28), pt(0.78, 0.32), pt(0.6, 0.32)], spacing: 0.016, inset: 0.008)
        // Custody record: heading, tick-box rows, signature over its line
        p.polyline([pt(0.57, 0.38), pt(0.81, 0.38)])
        for (i, end) in ([0.81, 0.77, 0.8, 0.74] as [CGFloat]).enumerated() {
            let y = 0.46 + CGFloat(i) * 0.08
            p.rect(0.57, y - 0.02, 0.035, 0.035)
            p.polyline([pt(0.63, y), pt(end, y)])
        }
        p.move(to: pt(0.6, 0.81))
        p.addCurve(to: pt(0.68, 0.78), control1: pt(0.62, 0.75), control2: pt(0.66, 0.74))
        p.addCurve(to: pt(0.76, 0.79), control1: pt(0.7, 0.82), control2: pt(0.73, 0.75))
        p.polyline([pt(0.57, 0.83), pt(0.81, 0.83)])
        return p.scaled(to: r)
    }
}

// MARK: - Drawing helpers (unit coordinates)

private nonisolated func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// Points along an ellipse between two angles (degrees, clockwise from 3 o'clock).
private nonisolated func arcPoints(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, from: CGFloat, to: CGFloat, count: Int = 48) -> [CGPoint] {
    (0...count).map { i in
        let t = (from + (to - from) * CGFloat(i) / CGFloat(count)) * .pi / 180
        return CGPoint(x: c.x + rx * cos(t), y: c.y + ry * sin(t))
    }
}

/// An equilateral Gothic arch from (`a`, `spring`) up to its point and down to (`b`, `spring`).
private nonisolated func pointedArch(_ a: CGFloat, _ b: CGFloat, spring y: CGFloat) -> [CGPoint] {
    let w = b - a
    return arcPoints(pt(b, y), w, w, from: 180, to: 240, count: 16) + arcPoints(pt(a, y), w, w, from: 300, to: 360, count: 16).dropFirst()
}

/// A point and its tangent on a cubic Bézier at `t`.
private nonisolated func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> (CGPoint, CGPoint) {
    let u = 1 - t
    let point = CGPoint(x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
                        y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y)
    let tangent = CGPoint(x: 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x),
                          y: 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y))
    return (point, tangent)
}

private nonisolated extension Path {
    /// Scales a unit-square drawing up to `r`.
    func scaled(to r: CGRect) -> Path {
        applying(CGAffineTransform(a: r.width, b: 0, c: 0, d: r.height, tx: r.minX, ty: r.minY))
    }

    mutating func polyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for q in points.dropFirst() { addLine(to: q) }
    }

    mutating func closedPolygon(_ points: [CGPoint]) {
        polyline(points)
        closeSubpath()
    }

    mutating func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        addRect(CGRect(x: x, y: y, width: w, height: h))
    }

    mutating func circle(_ c: CGPoint, _ r: CGFloat) {
        addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    mutating func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) {
        addEllipse(in: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    mutating func arc(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, from: CGFloat, to: CGFloat) {
        polyline(arcPoints(c, rx, ry, from: from, to: to, count: 24))
    }

    /// A polyline with the stretches where `hidden` holds left out (over/under crossings).
    mutating func brokenPolyline(_ points: [CGPoint], hidden: (CGPoint) -> Bool) {
        var run: [CGPoint] = []
        for q in points {
            if hidden(q) {
                polyline(run)
                run = []
            } else {
                run.append(q)
            }
        }
        polyline(run)
    }

    /// Short radial strokes across a ring's band — engraved shade on a round object.
    mutating func radialHatch(_ c: CGPoint, from r0: CGFloat, to r1: CGFloat, angles: StrideThrough<Double>) {
        for deg in angles {
            let t = CGFloat(deg) * .pi / 180
            polyline([CGPoint(x: c.x + r0 * cos(t), y: c.y + r0 * sin(t)),
                      CGPoint(x: c.x + r1 * cos(t), y: c.y + r1 * sin(t))])
        }
    }

    /// A straight line drawn as dashes (the stroke style itself stays solid).
    mutating func dashes(from a: CGPoint, to b: CGPoint, dash: CGFloat, gap: CGFloat) {
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return }
        var s: CGFloat = 0
        while s < length {
            let e = min(s + dash, length)
            polyline([CGPoint(x: a.x + (b.x - a.x) * s / length, y: a.y + (b.y - a.y) * s / length),
                      CGPoint(x: a.x + (b.x - a.x) * e / length, y: a.y + (b.y - a.y) * e / length)])
            s += dash + gap
        }
    }

    /// Parallel engraving lines filling a polygon, at `angle` (0 = horizontal), each
    /// pulled in by `inset` from the outline so the hatching doesn't touch it.
    mutating func hatch(_ polygon: [CGPoint], spacing: CGFloat, angle: Angle = .zero, inset: CGFloat = 0) {
        guard polygon.count > 2, spacing > 0 else { return }
        let (cosA, sinA) = (CGFloat(cos(angle.radians)), CGFloat(sin(angle.radians)))
        // Rotate so the hatch lines run horizontally, scan, then rotate back
        let rotated = polygon.map { CGPoint(x: $0.x * cosA + $0.y * sinA, y: -$0.x * sinA + $0.y * cosA) }
        let unrotate = { (q: CGPoint) in CGPoint(x: q.x * cosA - q.y * sinA, y: q.x * sinA + q.y * cosA) }
        guard let minY = rotated.map(\.y).min(), let maxY = rotated.map(\.y).max() else { return }
        var y = minY + spacing / 2
        while y < maxY {
            var xs: [CGFloat] = []
            for i in rotated.indices {
                let (a, b) = (rotated[i], rotated[(i + 1) % rotated.count])
                if (a.y <= y) != (b.y <= y) {
                    xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let (x0, x1) = (xs[k] + inset, xs[k + 1] - inset)
                if x1 > x0 { polyline([unrotate(CGPoint(x: x0, y: y)), unrotate(CGPoint(x: x1, y: y))]) }
                k += 2
            }
            y += spacing
        }
    }

    /// A laurel leaf: pointed oval from its base at `q`, pointing along `angle` (radians).
    mutating func leaf(at q: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) {
        let (dx, dy) = (cos(angle), sin(angle))
        let tip = CGPoint(x: q.x + dx * length, y: q.y + dy * length)
        let mid = CGPoint(x: q.x + dx * length / 2, y: q.y + dy * length / 2)
        move(to: q)
        addQuadCurve(to: tip, control: CGPoint(x: mid.x - dy * width, y: mid.y + dx * width))
        addQuadCurve(to: q, control: CGPoint(x: mid.x + dy * width, y: mid.y - dx * width))
    }
}
