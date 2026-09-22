import SwiftUI

/// Loads the student's profile after sign-in and sends them to onboarding if it's
/// unfinished (PRD flowchart: "Onboarded? No → Name…"), or into the app if it's done.
struct SignedInRootView: View {
    let uid: String

    @State private var onboarding: OnboardingModel?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let onboarding {
                if onboarding.isComplete {
                    SignedInPlaceholderView()
                } else {
                    OnboardingView(model: onboarding)
                }
            } else if loadFailed {
                retry
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ratioParchment.ignoresSafeArea())
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboarding?.isComplete)
        .task(id: uid) { await load() }
    }

    private var retry: some View {
        VStack(spacing: 20) {
            Text("We couldn't load your profile.")
                .ratioFont(.h3)
            RatioButton("Try again", style: .secondary) {
                Task { await load() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }

    private func load() async {
        loadFailed = false
        do {
            let profile = try await UserRepository().loadProfile(uid: uid)
            onboarding = OnboardingModel(uid: uid, profile: profile)
        } catch {
            loadFailed = true
        }
    }
}
