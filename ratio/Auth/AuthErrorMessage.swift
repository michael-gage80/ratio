import AuthenticationServices
import FirebaseAuth
import GoogleSignIn

/// Plain-English copy for sign-in failures. Returns `nil` when the person simply
/// cancelled, which isn't an error worth showing.
enum AuthErrorMessage {
    static func message(for error: Error) -> String? {
        if (error as? ASAuthorizationError)?.code == .canceled { return nil }
        if (error as? GIDSignInError)?.code == .canceled { return nil }

        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain, let code = AuthErrorCode(rawValue: nsError.code) else {
            return fallback
        }
        switch code {
        case .emailAlreadyInUse:
            return "There's already an account with that email. Log in instead."
        case .invalidEmail:
            return "That email address doesn't look right."
        case .weakPassword:
            return "Choose a longer password — at least 8 characters."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "That email and password don't match."
        case .accountExistsWithDifferentCredential:
            return "You already have a Ratio account with this email. Sign in the way you did before — you can link other sign-in methods in Settings."
        case .networkError:
            return "You're offline. Check your connection and try again."
        case .tooManyRequests:
            return "Too many attempts. Wait a moment and try again."
        default:
            return fallback
        }
    }

    private static let fallback = "Something went wrong. Please try again."
}
