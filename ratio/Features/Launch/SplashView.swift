import SwiftUI
import UIKit

/// screens/01-splash.png, without the ring: a quiet "R." on the dark ground, "Entering
/// chambers" over a hairline rule that fills while the app loads.
struct SplashView: View {
    /// Set once everything's loaded: the rule completes and the check appears.
    var ready = false

    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RatioMark(size: 96)
            Spacer()
            HStack(spacing: RatioSpace.xs) {
                Text("Entering chambers")
                if ready { Image(systemName: "checkmark").foregroundStyle(Color.ratioVerdigris) }
            }
            .ratioFont(.monoData)
            .foregroundStyle(Color.ratioInk2)
            .padding(.bottom, RatioSpace.s)
            Capsule()
                .fill(Color.ratioRule)
                .frame(width: 160, height: 1.5)
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.ratioOxblood).frame(width: 160 * (ready ? 1 : progress), height: 1.5)
                }
                .padding(.bottom, RatioSpace.xl)
        }
        .padding(RatioSpace.m)
        // Fill the screen: nothing inside is full width, and the page-curl host would
        // otherwise size the page to its content.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ratioParchment.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ready ? "Ratio. Ready." : "Ratio. Loading.")
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { progress = 0.8 }
        }
    }
}

/// The splash turning away like a page in Apple Books to reveal the app beneath, on
/// every launch; a fade with Reduce Motion.
struct SplashCover: View {
    let ready: Bool
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(RatioPreferences.reduceMotion) private var reduceMotion = false
    @State private var faded = false

    var body: some View {
        if reduceMotion || systemReduceMotion {
            SplashView(ready: ready)
                .opacity(faded ? 0 : 1)
                .task(id: ready) {
                    guard ready else { return }
                    try? await Task.sleep(for: .seconds(0.25))
                    withAnimation(RatioMotion.reveal) { faded = true }
                    try? await Task.sleep(for: .seconds(0.35))
                    done()
                }
        } else {
            PageCurl(turning: ready, done: done) { SplashView(ready: ready) }
                .ignoresSafeArea()
        }
    }
}

/// A one-page `UIPageViewController` in page-curl style: when `turning` becomes true the
/// page curls forward onto a clear page, showing whatever is behind.
private struct PageCurl<Page: View>: UIViewControllerRepresentable {
    let turning: Bool
    let done: () -> Void
    @ViewBuilder let page: Page

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        controller.view.backgroundColor = .clear
        controller.isDoubleSided = false
        controller.gestureRecognizers.forEach { $0.isEnabled = false }
        let hosting = UIHostingController(rootView: page)
        hosting.view.backgroundColor = .clear
        context.coordinator.hosting = hosting
        controller.setViewControllers([hosting], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.hosting?.rootView = page
        guard turning, !context.coordinator.turned else { return }
        context.coordinator.turned = true
        // A beat for the check to show, then the turn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let blank = UIViewController()
            blank.view.backgroundColor = .clear
            controller.setViewControllers([blank], direction: .forward, animated: true) { _ in done() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hosting: UIHostingController<Page>?
        var turned = false
    }
}
