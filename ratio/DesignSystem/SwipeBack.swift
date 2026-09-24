import UIKit

/// Full-screen pages (the Week in Law, Notifications, the Library, Settings) hide the
/// navigation bar and its back button; UIKit then drops the edge swipe back unless the
/// gesture has a delegate that allows it. This keeps swipe-back on every pushed page.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
