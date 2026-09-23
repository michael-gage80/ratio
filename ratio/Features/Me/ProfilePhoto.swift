import FirebaseFunctions
import FirebaseStorage
import PhotosUI
import SwiftUI

/// The student's approved photo, or their initial-letter avatar while there's none
/// (PRD: "Falls back to the initial-letter avatar").
struct ProfilePhoto: View {
    let uid: String
    let initial: String
    /// `users/{uid}.avatarVersion`: changes whenever a new photo is approved.
    let version: Int?
    var size: CGFloat = 40

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.ratioRule, lineWidth: 1))
            } else {
                RatioAvatar(initial: initial, seed: uid, size: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: version) {
            guard let version else { image = nil; return }
            image = await AvatarImages.image(uid: uid, version: version)
        }
    }
}

enum AvatarImages {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(uid: String, version: Int) async -> UIImage? {
        let key = "\(uid)-\(version)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = try? await Storage.storage().reference(withPath: "avatars/\(uid)/avatar.jpg").data(maxSize: 1 << 20),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    enum UploadError: LocalizedError {
        case unreadable, refused

        var errorDescription: String? {
            switch self {
            case .unreadable: "That photo couldn't be read. Try another."
            case .refused: "That photo can't be used as an avatar. Try another."
            }
        }
    }

    /// Crops to a 512 px square JPEG, uploads it, and waits for moderation. The photo
    /// only appears once `users/{uid}.avatarVersion` changes.
    static func upload(_ item: PhotosPickerItem, uid: String) async throws {
        guard let data = try await item.loadTransferable(type: Data.self),
              let jpeg = UIImage(data: data)?.squareJPEG(side: 512) else { throw UploadError.unreadable }
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await Storage.storage().reference(withPath: "avatars/\(uid)/upload.jpg").putDataAsync(jpeg, metadata: metadata)
        let result = try await Functions.functions(region: "europe-west2").httpsCallable("moderateAvatar").call()
        guard (result.data as? [String: Any])?["approved"] as? Bool == true else { throw UploadError.refused }
    }
}

private extension UIImage {
    /// Centre-cropped to a square, drawn upright (respects the photo's orientation).
    func squareJPEG(side: CGFloat) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in
            let scale = side / min(size.width, size.height)
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
    }
}
