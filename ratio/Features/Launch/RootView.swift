import SwiftUI

/// Routes between splash, the signed-out flow, email verification and the signed-in
/// app (PRD: "Onboarding, splash and diagnostic" flowchart).
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var splashFinished = false

    var body: some View {
        Group {
            if !splashFinished || session.state == .launching {
                SplashView()
            } else {
                switch session.state {
                case .launching, .signedOut:
                    WelcomeView()
                case .awaitingEmailVerification(let email):
                    VerifyEmailView(email: email)
                case .signedIn(let uid):
                    SignedInRootView(uid: uid)
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: splashFinished)
        .animation(.easeInOut(duration: 0.35), value: session.state)
        .task {
            // Long enough for the ring to read as deliberate; well inside the PRD's
            // "hands off in under 2 s".
            try? await Task.sleep(for: .seconds(1.2))
            splashFinished = true
        }
        .alert(
            session.errorMessage ?? "",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}
