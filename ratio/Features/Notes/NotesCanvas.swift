import PencilKit
import SwiftUI

/// The Pencil tools and whether notes show, shared by a lecture's canvases and palette.
@Observable
final class NotesSession {
    enum Tool: CaseIterable {
        case pen, highlighter, eraser, lasso

        var symbol: String {
            switch self {
            case .pen: "pencil.tip"
            case .highlighter: "highlighter"
            case .eraser: "eraser"
            case .lasso: "lasso"
            }
        }

        var label: String {
            switch self {
            case .pen: "Pen"
            case .highlighter: "Highlighter"
            case .eraser: "Eraser"
            case .lasso: "Lasso"
            }
        }
    }

    /// Ink, oxblood and verdigris — fixed values; PencilKit lightens them in dark mode.
    enum Ink: CaseIterable {
        case ink, oxblood, verdigris

        var color: UIColor {
            switch self {
            case .ink: UIColor(red: 0.114, green: 0.106, blue: 0.094, alpha: 1)
            case .oxblood: UIColor(red: 0.608, green: 0.165, blue: 0.141, alpha: 1)
            case .verdigris: UIColor(red: 0.110, green: 0.443, blue: 0.278, alpha: 1)
            }
        }

        var label: String {
            switch self {
            case .ink: "Ink"
            case .oxblood: "Oxblood"
            case .verdigris: "Green"
            }
        }
    }

    var tool = Tool.pen
    var ink = Ink.oxblood
    /// Draw with a finger too (otherwise a finger scrolls and taps).
    var fingerDrawing = false
    var paletteShown = true
    /// The canvas last drawn on, for undo and redo.
    @ObservationIgnored weak var activeCanvas: PKCanvasView?

    var pkTool: PKTool {
        switch tool {
        case .pen: PKInkingTool(.pen, color: ink.color, width: 3)
        case .highlighter: PKInkingTool(.marker, color: ink.color.withAlphaComponent(0.35), width: 18)
        case .eraser: PKEraserTool(.vector)
        case .lasso: PKLassoTool()
        }
    }

    func undo() { activeCanvas?.undoManager?.undo() }
    func redo() { activeCanvas?.undoManager?.redo() }
}

/// A transparent PencilKit canvas over a lecture part. Only Pencil touches land on it
/// (unless finger drawing is on), so fingers still scroll the page and tap what's
/// underneath.
struct NotesCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let session: NotesSession
    let onChange: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PencilOnlyCanvas {
        let canvas = PencilOnlyCanvas()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        let pencil = UIPencilInteraction(delegate: context.coordinator)
        canvas.addInteraction(pencil)
        return canvas
    }

    func updateUIView(_ canvas: PencilOnlyCanvas, context: Context) {
        context.coordinator.parent = self
        canvas.tool = session.pkTool
        canvas.drawingPolicy = session.fingerDrawing ? .anyInput : .pencilOnly
        canvas.fingerDrawing = session.fingerDrawing
        if canvas.drawing != drawing && !context.coordinator.isEditing { canvas.drawing = drawing }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: NotesCanvas
        var isEditing = false

        init(parent: NotesCanvas) { self.parent = parent }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            isEditing = true
            parent.session.activeCanvas = canvasView
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { isEditing = false }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onChange(canvasView.drawing)
        }

        /// Double-tap on Apple Pencil: pen and eraser.
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
            parent.session.tool = parent.session.tool == .eraser ? .pen : .eraser
        }

        /// Squeeze on Apple Pencil Pro: show or hide the palette.
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            guard squeeze.phase == .ended else { return }
            withAnimation(RatioMotion.tap) { parent.session.paletteShown.toggle() }
        }
    }
}

/// Lets finger touches fall through to the page (scrolling, buttons) unless finger
/// drawing is on.
final class PencilOnlyCanvas: PKCanvasView {
    var fingerDrawing = false

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        if fingerDrawing { return true }
        return event?.allTouches?.contains { $0.type == .pencil } ?? false
    }
}

/// Read-only notes (iPhone): the drawing as an image, scaled to fit.
struct NotesImage: View {
    let drawing: PKDrawing
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var image = UIImage()
        traits.performAsCurrent { image = drawing.image(from: bounds, scale: displayScale) }
        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Your handwritten notes")
    }
}

/// The floating palette (screens/iPad/3-lesson/02): tools, colours, undo and redo.
struct NotesPalette: View {
    @Bindable var session: NotesSession

    var body: some View {
        HStack(spacing: RatioSpace.xs) {
            Text("Pencil").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).padding(.leading, RatioSpace.s)
            ForEach(NotesSession.Tool.allCases, id: \.self) { tool in
                Button { session.tool = tool } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 44, height: 44)
                        .foregroundStyle(session.tool == tool ? Color.ratioParchment : Color.ratioInk)
                        .background(session.tool == tool ? Color.ratioInk : .clear, in: Circle())
                }
                .buttonStyle(.ratioPress)
                .accessibilityLabel(tool.label)
                .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
            }
            Divider().frame(height: 28)
            ForEach(NotesSession.Ink.allCases, id: \.self) { ink in
                Button { session.ink = ink } label: {
                    Circle()
                        .fill(Color(uiColor: ink.color))
                        .frame(width: 24, height: 24)
                        .padding(4)
                        .overlay(Circle().strokeBorder(session.ink == ink ? Color.ratioInk : .clear, lineWidth: 2))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.ratioPress)
                .accessibilityLabel(ink.label)
                .accessibilityAddTraits(session.ink == ink ? .isSelected : [])
            }
            Divider().frame(height: 28)
            Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                .buttonStyle(.ratioPress).accessibilityLabel("Undo")
            Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                .buttonStyle(.ratioPress).accessibilityLabel("Redo")
            Button { session.fingerDrawing.toggle() } label: {
                Image(systemName: "hand.draw")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(session.fingerDrawing ? Color.ratioParchment : Color.ratioInk)
                    .background(session.fingerDrawing ? Color.ratioInk : .clear, in: Circle())
            }
            .buttonStyle(.ratioPress)
            .accessibilityLabel("Draw with a finger")
            .accessibilityAddTraits(session.fingerDrawing ? .isSelected : [])
        }
        .padding(.horizontal, RatioSpace.xs)
        .padding(.vertical, RatioSpace.xxs)
        .foregroundStyle(Color.ratioInk)
        .ratioGlassCapsule()
        .overlay(Capsule().strokeBorder(Color.ratioRule))
    }
}
