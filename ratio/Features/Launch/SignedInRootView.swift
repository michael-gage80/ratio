import SwiftUI

/// Loads the student's profile after sign-in and sends them to onboarding if it's
/// unfinished (PRD flowchart: "Onboarded? No → Name…"), or into the app if it's done.
struct SignedInRootView: View {
    let uid: String

    @Environment(ContentStore.self) private var content
    @State private var onboarding: OnboardingModel?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let onboarding {
                if onboarding.isComplete {
                    MainTabView(uid: uid, profile: onboarding.profile)
                } else {
                    OnboardingView(model: onboarding)
                }
            } else if loadFailed {
                retry
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ratioPage()
            }
        }
        .animation(RatioMotion.reveal, value: onboarding?.isComplete)
        .task(id: uid) { await load() }
        .task(id: uid) { await content.refresh() }
    }

    private var retry: some View {
        RatioErrorState(message: "Your profile didn't load. Check your connection and try again.") {
            Task { await load() }
        }
        .padding(RatioSpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ratioPage()
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
