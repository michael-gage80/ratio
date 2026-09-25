import SwiftUI

/// Create an account or log in with email and password (PRD: "Account" — email and
/// password with email verification). Not in the mockups; styled like the onboarding
/// steps (screens/03-name.png).
struct EmailAuthView: View {
    enum Mode: Hashable {
        case createAccount, logIn
    }

    let mode: Mode

    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var resetSent = false

    private static let minimumPasswordLength = 8

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text(mode == .createAccount ? "Create your account." : "Welcome back.")
                        .ratioFont(.h1)
                    Text(mode == .createAccount
                         ? "We'll send a link to confirm your email before you start."
                         : "Log in with the email you signed up with.")
                        .ratioFont(.body)
                        .foregroundStyle(Color.ratioInk2)
                }

                RatioTextField("Email", placeholder: "you@university.ac.uk", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    RatioTextField("Password", text: $password, isSecure: true)
                        .textContentType(mode == .createAccount ? .newPassword : .password)
                    if mode == .createAccount {
                        Text("At least \(Self.minimumPasswordLength) characters.")
                            .ratioFont(.caption)
                            .foregroundStyle(Color.ratioInk2)
                    }
                }

                if mode == .logIn {
                    resetPassword
                }
            }
            .padding(RatioSpace.m)
            .ratioReadableWidth(560)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            RatioButton(mode == .createAccount ? "Create account" : "Log in", isEnabled: canSubmit) {
                Task { await submit() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .padding(RatioSpace.m)
            .ratioReadableWidth(560)
        }
        .overlay {
            if session.isWorking { ProgressView().controlSize(.large) }
        }
        .ratioPage()
    }

    @ViewBuilder
    private var resetPassword: some View {
        if resetSent {
            Text("If there's an account for that email, a reset link is on its way.")
                .ratioFont(.small)
                .foregroundStyle(Color.ratioInk2)
        } else {
            Button("Forgot your password?") {
                Task { resetSent = await session.sendPasswordReset(email: trimmedEmail) }
            }
            .ratioFont(.small)
            .underline()
            .frame(minHeight: 44)
            .disabled(!looksLikeEmail)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var looksLikeEmail: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    private var canSubmit: Bool {
        guard looksLikeEmail, !session.isWorking else { return false }
        return mode == .createAccount ? password.count >= Self.minimumPasswordLength : !password.isEmpty
    }

    private func submit() async {
        switch mode {
        case .createAccount: await session.createAccount(email: trimmedEmail, password: password)
        case .logIn: await session.logIn(email: trimmedEmail, password: password)
        }
    }
}
