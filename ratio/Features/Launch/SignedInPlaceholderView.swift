import SwiftUI

/// Temporary landing screen after onboarding so far, until Today (Phase 10) replaces it.
struct SignedInPlaceholderView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsCatalog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            RatioMark(size: 56)
            Text("You're in.")
                .ratioFont(.h1)
            Text("University, modules and the diagnostic come next.")
                .ratioFont(.body)
                .foregroundStyle(Color.ratioInk2)
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
