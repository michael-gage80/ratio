import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UserNotifications

/// Notifications (PRD: "Boards, streaks and notifications"). The daily brief reminder and
/// the streak rescue are scheduled on the phone, so quiet hours hold offline; duel
/// challenges arrive as pushes from Functions through Firebase Cloud Messaging. There are
/// no spaced-review or marketing notifications, and nothing says "you're falling behind".
enum RatioNotifications {
    private static let briefPrefix = "brief-"
    private static let rescue = "streak-rescue"
    /// Evening nudge time, before a typical quiet period starts.
    private static let rescueTime = "19:00"

    /// Asks once, at a moment the student can see why (after the Today tour).
    @discardableResult
    static func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// Re-plans the next week's reminders from the student's settings and progress.
    static func reschedule(for student: StudentStore) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.hasPrefix(briefPrefix) || $0 == rescue })

        let settings = student.settings
        let quiet = (settings.quietStart ?? "22:00", settings.quietEnd ?? "08:00")
        let calendar = UKDate.calendar

        // The daily brief, for the next 7 days, each mentioning the reviews due that day.
        if settings.briefReminder ?? true {
            let time = settings.briefTime ?? "08:30"
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: .now),
                      let fire = date(day, at: time), fire > .now, !isQuiet(time, quiet) else { continue }
                let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
                let due = student.items.count { $0.due <= endOfDay }
                let content = UNMutableNotificationContent()
                content.title = "Your brief is ready"
                content.body = due > 0 ? "About 15 minutes, with \(due) \(due == 1 ? "review" : "reviews") that \(due == 1 ? "has" : "have") come due." : "About 15 minutes, built from yesterday's answers."
                content.sound = .default
                await add(content, id: "\(briefPrefix)\(UKDate.key(for: day))", at: fire)
            }
        }

        // The streak rescue: one evening nudge, only if the week is still reachable and
        // today would count (PRD). Neutral tone.
        let streak = student.streak
        let remaining = streak.target - streak.daysThisWeek
        let daysLeft = 7 - streak.todayIndex
        let activeToday = streak.week[safe: streak.todayIndex]?.active ?? false
        if !streak.isPaused, !activeToday, remaining > 0, remaining <= daysLeft,
           let fire = date(.now, at: rescueTime), fire > .now, !isQuiet(rescueTime, quiet) {
            let content = UNMutableNotificationContent()
            content.title = "One short session keeps your week on track"
            content.body = "\(streak.daysThisWeek) of \(streak.target) days so far this week."
            await add(content, id: rescue, at: fire)
        }
    }

    private static func add(_ content: UNNotificationContent, id: String, at date: Date) async {
        let parts = UKDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func date(_ day: Date, at time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return UKDate.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// Whether "HH:mm" falls inside quiet hours, which may run past midnight.
    static func isQuiet(_ time: String, _ quiet: (String, String)) -> Bool {
        let (start, end) = quiet
        return start <= end ? (time >= start && time < end) : (time >= start || time < end)
    }

    /// Stores this phone's push token so challenge notifications can reach it.
    static func saveToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid).collection("devices").document(token)
            .setData(["platform": "ios", "updatedAt": FieldValue.serverTimestamp()])
    }
}

/// Hooks for push notifications, which the SwiftUI app lifecycle doesn't provide.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    /// A tapped challenge notification, for the tabs to open.
    static var openChallenge: ((String) -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in RatioNotifications.saveToken(fcmToken) }
    }

    /// Show notifications while the app is open, too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let challengeId = response.notification.request.content.userInfo["challengeId"] as? String
        await MainActor.run {
            if let challengeId { AppDelegate.openChallenge?(challengeId) }
        }
    }
}
