import AuthenticationServices
import SwiftUI

/// screens/02-welcome.png — sign up or log in. A dark full-screen moment; the email
/// screens it pushes follow the system appearance.
struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var emailMode: EmailAuthView.Mode?

    var body: some View {
        NavigationStack {
            content
                .environment(\.colorScheme, .dark)
                .navigationDestination(item: $emailMode) { mode in
                    EmailAuthView(mode: mode)
                        .environment(\.colorScheme, systemColorScheme)
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: RatioSpace.m)
            hero
            Spacer(minLength: RatioSpace.m)
            VStack(spacing: RatioSpace.s) {
                Text("Ratio · for LLB students")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                Text("Think like a \(Text("lawyer.").italic().foregroundStyle(Color.ratioOxblood))\nLearn like a \(Text("game.").italic().foregroundStyle(Color.ratioOxblood))")
                    .ratioFont(.h1)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: RatioSpace.l)
            buttons
            footer
        }
        .padding(.horizontal, RatioSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ratioPage()
        .disabled(session.isWorking)
        .overlay {
            if session.isWorking { ProgressView().controlSize(.large) }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        ZStack {
            RatioSpotArt.pediment.view
                .foregroundStyle(Color.ratioRule)
                .frame(width: 280)
            Circle()
                .stroke(Color.ratioOxblood, lineWidth: 2)
                .frame(width: 170, height: 170)
                .background(Circle().fill(Color.ratioParchment))
            RatioMark(size: 96)
        }
        .accessibilityHidden(true)
    }

    private var buttons: some View {
        VStack(spacing: RatioSpace.s) {
            SignInWithAppleButton(.continue) { request in
                session.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await session.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))

            RatioButton("Continue with Google", style: .tertiary) {
                Task { await session.signInWithGoogle() }
            }
            RatioButton("Create account with email", style: .tertiary) {
                emailMode = .createAccount
            }

            // One line when it fits, stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.xs) { alreadyHaveAccount; logIn }
                VStack(spacing: 0) { alreadyHaveAccount; logIn }
            }
            .ratioFont(.body)
            .multilineTextAlignment(.center)
            .padding(.top, RatioSpace.xs)
        }
    }

    private var alreadyHaveAccount: some View {
        Text("I already have an account ·").foregroundStyle(Color.ratioInk2)
    }

    private var logIn: some View {
        Button("Log in") { emailMode = .logIn }
            .italic()
            .underline()
            .foregroundStyle(Color.ratioInk)
            .frame(minHeight: 44)
    }

    private var footer: some View {
        Text("You must be 18 or over.\nRatio is educational, not legal advice.")
            .ratioFont(.monoData)
            .foregroundStyle(Color.ratioInk2)
            .multilineTextAlignment(.center)
            .padding(.vertical, RatioSpace.m)
    }
}
