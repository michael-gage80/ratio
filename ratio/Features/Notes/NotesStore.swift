import FirebaseFirestore
import FirebaseStorage
import PencilKit
import SwiftUI

/// Apple Pencil notes on one lesson's lecture parts: one PencilKit drawing per part,
/// kept in Storage at notes/{uid}/{lessonId}/{part}.drawing (the owner's alone), listed
/// in users/{uid}/notes, and cached on the device so they open offline.
@Observable
final class NotesStore {
    let uid: String
    let lessonId: String

    /// Each part's drawing (1-based part numbers) and the width it was drawn at.
    private(set) var drawings: [Int: (drawing: PKDrawing, width: CGFloat)] = [:]

    @ObservationIgnored private var saves: [Int: Task<Void, Never>] = [:]

    init(uid: String, lessonId: String) {
        self.uid = uid
        self.lessonId = lessonId
    }

    var hasNotes: Bool { drawings.values.contains { !$0.drawing.strokes.isEmpty } }

    /// The part's drawing scaled to `width` (a part drawn at another width is scaled to
    /// fit; ink over reflowed text is best-effort).
    func drawing(part: Int, width: CGFloat) -> PKDrawing {
        guard let saved = drawings[part], saved.width > 0, width > 0 else { return PKDrawing() }
        let scale = width / saved.width
        return abs(scale - 1) < 0.01 ? saved.drawing : saved.drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Cached copies first, then the server's.
    func load() async {
        for (part, note) in Self.cached(uid: uid, lessonId: lessonId) { drawings[part] = note }
        let index = try? await Firestore.firestore().collection("users/\(uid)/notes")
            .whereField("lessonId", isEqualTo: lessonId).getDocuments()
        for document in index?.documents ?? [] {
            guard let part = document.data()["part"] as? Int, let width = document.data()["width"] as? Double,
                  let data = try? await storage(part).data(maxSize: 2 * 1024 * 1024),
                  let drawing = try? PKDrawing(data: data) else { continue }
            drawings[part] = (drawing, width)
            Self.cache(data, width: width, uid: uid, lessonId: lessonId, part: part)
        }
    }

    /// Saves a part's drawing a moment after the last stroke.
    func save(_ drawing: PKDrawing, part: Int, width: CGFloat) {
        drawings[part] = (drawing, width)
        saves[part]?.cancel()
        let (uid, lessonId) = (uid, lessonId)
        saves[part] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self else { return }
            let data = drawing.dataRepresentation()
            Self.cache(data, width: width, uid: uid, lessonId: lessonId, part: part)
            let index = Firestore.firestore().document("users/\(uid)/notes/\(lessonId)_\(part)")
            if drawing.strokes.isEmpty {
                try? await storage(part).delete()
                try? await index.delete()
            } else {
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                _ = try? await storage(part).putDataAsync(data, metadata: metadata)
                try? await index.setData(["lessonId": lessonId, "part": part, "width": Double(width), "updatedAt": FieldValue.serverTimestamp()])
            }
        }
    }

    private func storage(_ part: Int) -> StorageReference {
        Storage.storage().reference(withPath: "notes/\(uid)/\(lessonId)/\(part).drawing")
    }

    // MARK: Device cache

    private static func folder(uid: String, lessonId: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "notes/\(uid)/\(lessonId)", directoryHint: .isDirectory)
    }

    private static func cache(_ data: Data, width: Double, uid: String, lessonId: String, part: Int) {
        let folder = folder(uid: uid, lessonId: lessonId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The width goes in the name: "2@812.drawing".
        if let old = try? FileManager.default.contentsOfDirectory(atPath: folder.path()) {
            for name in old where name.hasPrefix("\(part)@") { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
        }
        try? data.write(to: folder.appending(path: "\(part)@\(Int(width.rounded())).drawing"))
    }

    private static func cached(uid: String, lessonId: String) -> [Int: (drawing: PKDrawing, width: CGFloat)] {
        let folder = folder(uid: uid, lessonId: lessonId)
        var result: [Int: (drawing: PKDrawing, width: CGFloat)] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path())) ?? [] {
            let parts = name.replacingOccurrences(of: ".drawing", with: "").split(separator: "@")
            guard parts.count == 2, let part = Int(parts[0]), let width = Double(parts[1]),
                  let data = try? Data(contentsOf: folder.appending(path: name)),
                  let drawing = try? PKDrawing(data: data) else { continue }
            result[part] = (drawing, width)
        }
        return result
    }
}
