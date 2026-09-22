import SwiftUI

/// screens/01-splash.png — the "R." mark in its ring on a dark full-screen moment.
struct SplashView: View {
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                RatioRings(diameter: 170)
                RatioMark(size: 96)
            }
            Spacer()
            Text("Entering chambers")
                .ratioFont(.monoData)
                .foregroundStyle(Color.ratioInk2)
                .padding(.bottom, 28)
            Text("Ratio · LLB")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    SplashView()
}
