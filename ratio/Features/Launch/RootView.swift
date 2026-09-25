import SwiftUI

/// Routes between splash, the signed-out flow, email verification and the signed-in
/// app (PRD: "Onboarding, splash and diagnostic" flowchart).
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var minimumShown = false
    @State private var splashGone = false

    var body: some View {
        #if DEBUG
        if DebugHooks.screen?.hasPrefix("gallery") == true {
            NavigationStack { InteractionGalleryView() }.ratioMeasuresWidth()
        } else {
            app
        }
        #else
        app
        #endif
    }

    private var app: some View {
        ZStack {
            Group {
                switch session.state {
                case .launching:
                    Color.ratioParchment.ignoresSafeArea()
                case .signedOut:
                    WelcomeView()
                case .awaitingEmailVerification(let email):
                    VerifyEmailView(email: email)
                case .signedIn(let uid):
                    SignedInRootView(uid: uid)
                }
            }
            .animation(RatioMotion.reveal, value: session.state)
            // The splash sits on top and turns away once the session is known.
            if !splashGone {
                SplashCover(ready: minimumShown && session.state != .launching) { splashGone = true }
            }
        }
        .task {
            // Long enough for the splash to read as deliberate; well inside the PRD's
            // "hands off in under 2 s".
            try? await Task.sleep(for: .seconds(1.2))
            minimumShown = true
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
