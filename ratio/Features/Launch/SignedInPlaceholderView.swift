import SwiftUI

/// Temporary landing screen after sign-in, until onboarding (Phase 3) replaces it.
struct SignedInPlaceholderView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsCatalog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            RatioMark(size: 56)
            Text("You're in.")
                .ratioFont(.h1)
            Text("Onboarding arrives in the next phase.")
                .ratioFont(.body)
                .foregroundStyle(.secondary)
            Spacer()
            #if DEBUG
            RatioButton("Design system catalog", style: .tertiary) { showsCatalog = true }
            #endif
            RatioButton("Log out", style: .secondary) { session.signOut() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        #if DEBUG
        .sheet(isPresented: $showsCatalog) { DesignSystemCatalogView() }
        #endif
    }
}
