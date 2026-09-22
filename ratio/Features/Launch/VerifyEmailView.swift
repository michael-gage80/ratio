import SwiftUI

/// Shown after email sign-up until the verification link has been tapped. Checks
/// again automatically whenever the app comes back to the foreground, which is
/// usually straight after tapping the link in Mail.
struct VerifyEmailView: View {
    let email: String

    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Check your inbox.")
                .ratioFont(.h1)
            Text("We've sent a link to \(Text(email).italic()). Tap it, then come back here.")
                .ratioFont(.body)
                .foregroundStyle(Color.ratioInk2)
            if let note {
                Text(note)
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            Spacer()
            VStack(spacing: 12) {
                RatioButton("I've verified my email", isEnabled: !session.isWorking) {
                    Task {
                        await session.refreshEmailVerification()
                        note = "Not verified yet — the link can take a minute to arrive."
                    }
                }
                RatioButton("Send the link again", style: .tertiary, isEnabled: !session.isWorking) {
                    Task {
                        if await session.resendVerificationEmail() {
                            note = "Sent. Check your spam folder if it doesn't appear."
                        }
                    }
                }
                RatioButton("Use a different account", style: .link) {
                    session.signOut()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.refreshEmailVerification() }
            }
        }
    }
}
