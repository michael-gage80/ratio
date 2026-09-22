import AuthenticationServices
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// The single source of truth for who is signed in. Wraps Firebase Auth's state
/// listener and the three sign-in routes on the Welcome screen (Apple, Google, email),
/// which all resolve to one Firebase identity per person (PRD: "Account").
@Observable
final class SessionStore {
    enum State: Equatable {
        case launching
        case signedOut
        /// Signed up with email and password but hasn't tapped the verification link.
        case awaitingEmailVerification(email: String)
        case signedIn(uid: String)
    }

    private(set) var state: State = .launching
    private(set) var isWorking = false
    var errorMessage: String?

    private let users = UserRepository()
    private var appleNonce: String?

    init() {
        // The store lives for the app's lifetime, so the listener is never removed.
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.update(for: user)
        }
    }

    // MARK: Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.make()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        await perform {
            let authorization = try result.get()
            guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce
            else { throw SessionError.missingCredential }
            // Passing fullName sets the Firebase user's displayName on first sign-in, so
            // onboarding can prefill the name step instead of asking again.
            let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: apple.fullName)
            try await Auth.auth().signIn(with: credential)
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        guard let presenter = UIApplication.shared.topViewController else { return }
        await perform {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw SessionError.missingCredential }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
        }
    }

    // MARK: Email

    func createAccount(email: String, password: String) async {
        await perform {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            try await result.user.sendEmailVerification()
        }
    }

    func logIn(email: String, password: String) async {
        await perform {
            try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }

    /// Returns `true` once the request has been sent. Firebase deliberately doesn't say
    /// whether the account exists, so the caller's copy shouldn't either.
    func sendPasswordReset(email: String) async -> Bool {
        var sent = false
        await perform {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            sent = true
        }
        return sent
    }

    func resendVerificationEmail() async -> Bool {
        var sent = false
        await perform {
            try await Auth.auth().currentUser?.sendEmailVerification()
            sent = true
        }
        return sent
    }

    /// Re-reads the user from Firebase — the auth listener doesn't fire when the
    /// verification link is tapped in Mail, so the app has to ask.
    func refreshEmailVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        try? await user.reload()
        update(for: Auth.auth().currentUser)
    }

    /// The display name Apple or Google supplied at sign-in, if any — used to prefill
    /// onboarding's name step rather than asking for it from scratch.
    var suggestedName: String? {
        Auth.auth().currentUser?.displayName
    }

    /// Under-18s can't use Ratio (PRD: "Safety, privacy and compliance"). Their
    /// profile holds nothing but a timestamp at this point; remove it and the account,
    /// then explain on the Welcome screen.
    func removeUnderageAccount(uid: String) async {
        try? await users.deleteProfile(uid: uid)
        do {
            try await Auth.auth().currentUser?.delete()
        } catch {
            // Deleting needs a recent sign-in; if it's gone stale, signing out still
            // leaves no personal data behind.
            signOut()
        }
        GIDSignIn.sharedInstance.signOut()
        errorMessage = "Ratio is for students aged 18 and over, so we haven't kept your account or any of your details."
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = AuthErrorMessage.message(for: error)
        }
    }

    // MARK: Private

    private func update(for user: User?) {
        guard let user else {
            state = .signedOut
            return
        }
        let isEmailOnly = user.providerData.allSatisfy { $0.providerID == AuthProviderID.email.rawValue }
        if isEmailOnly && !user.isEmailVerified {
            state = .awaitingEmailVerification(email: user.email ?? "")
        } else {
            state = .signedIn(uid: user.uid)
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = AuthErrorMessage.message(for: error)
        }
    }
}

enum SessionError: Error {
    case missingCredential
}

private extension UIApplication {
    /// The view controller Google Sign-In presents its web sheet from.
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
