import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import StoreKit
import SwiftUI

/// screens/30-settings.png — the index of everything the student can change (PRD: "Me tab
/// and settings"): account, appearance, study, accessibility, content, subscription,
/// privacy and legal, and the danger zone.
struct SettingsView: View {
    @Environment(StudentStore.self) private var student
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigator.self) private var navigator
    @Environment(Purchases.self) private var purchases

    @AppStorage(RatioPreferences.appearance) private var appearance = "auto"
    @AppStorage(RatioPreferences.dyslexia) private var dyslexia = false
    @AppStorage(RatioPreferences.reduceMotion) private var reduceMotion = false
    @AppStorage(RatioPreferences.haptics) private var haptics = true
    @AppStorage("duel.extendedSeconds") private var extendedSeconds = 0
    @AppStorage("tour.today.seen") private var tourSeen = false
    @AppStorage("duel.tutorialSeen") private var duelTutorialSeen = false

    @State private var sheet: Sheet?
    @State private var message: String?
    @State private var confirming: Confirmation?
    @State private var working = false
    @State private var exportFile: URL?
    @State private var managingSubscription = false
    @State private var iconName = UIApplication.shared.alternateIconName

    private enum Sheet: String, Identifiable {
        case name, modules, year, freeModule, report, licence, notice
        var id: String { rawValue }
    }

    private enum Confirmation: Identifiable {
        case reset, delete
        var id: Int { hashValue }
    }

    private var profile: UserProfile { student.profile }
    private var settings: StudySettings { student.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RatioPageHeader(eyebrow: "Me", title: "Settings")
                account
                appearanceSection
                study
                accessibility
                content
                subscription
                privacy
                danger
                Text("Ratio \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RatioSpace.l)
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.s)
        }
        .ratioPage()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .name: NameSheet(profile: profile, uid: student.uid)
            case .modules: ModulesSheet(profile: profile, uid: student.uid)
            case .year: YearSheet(uid: student.uid, year: profile.year).presentationDetents([.height(260)])
            case .freeModule: FreeModuleSheet()
            case .report: ReportErrorSheet(itemId: "general", lessonId: nil)
            case .licence: LicenceCodeSheet().presentationDetents([.medium])
            case .notice: NoticeSheet().presentationDetents([.medium])
            }
        }
        .manageSubscriptionsSheet(isPresented: $managingSubscription)
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { confirmation in
            switch confirmation {
            case .reset: Button("Reset my progress", role: .destructive) { Task { await reset() } }
            case .delete: Button("Delete my account", role: .destructive) { Task { await deleteAccount() } }
            }
        } message: { confirmation in
            switch confirmation {
            case .reset: Text("Clears your scores, reviews, briefs and history. Your account, modules and plan stay.")
            case .delete: Text("Deletes your account and everything in it, now. A subscription is cancelled separately, in Settings → Apple ID → Subscriptions.")
            }
        }
        .alert("Settings", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .reset: "Reset your progress?"
        case .delete: "Delete your account?"
        case nil: ""
        }
    }

    // MARK: I · Account

    private var account: some View {
        SettingsSection(number: "I", title: "Account") {
            SettingsRow("Email", value: Auth.auth().currentUser?.email ?? "Not shared")
            if providers.contains("password") {
                SettingsRow("Password", value: "Change") { Task { await resetPassword() } }
            }
            SettingsRow("Linked sign-in", value: linkedSignIn)
            SettingsRow("Display name", value: displayName) { sheet = .name }
        }
    }

    private var providers: [String] { Auth.auth().currentUser?.providerData.map(\.providerID) ?? [] }

    private var linkedSignIn: String {
        let names = ["apple.com": "Apple", "google.com": "Google", "password": "Email"]
        return providers.compactMap { names[$0] }.map { "\($0) ✓" }.joined(separator: " · ")
    }

    private var displayName: String {
        [profile.displayName, profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: II · Appearance

    private var appearanceSection: some View {
        SettingsSection(number: "II", title: "Appearance") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.s) {
                    Text("Theme").ratioFont(.body)
                    Spacer()
                    themePicker.frame(width: 216)
                }
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Theme").ratioFont(.body)
                    themePicker
                }
            }
            .padding(.vertical, RatioSpace.s)
            Divider().overlay(Color.ratioRule)
            Text("App icon").ratioFont(.body).padding(.top, RatioSpace.s)
            ScrollView(.horizontal) {
                HStack(spacing: RatioSpace.s) {
                    ForEach(AppIconChoice.all) { icon in
                        let selected = iconName == icon.assetName
                        Button { setIcon(icon) } label: {
                            VStack(spacing: RatioSpace.xs) {
                                icon.preview
                                    .frame(width: 64, height: 64)
                                    .padding(RatioSpace.xxs)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: RatioRadius.panel + RatioSpace.xxs, style: .continuous)
                                            .strokeBorder(selected ? Color.ratioInk : .clear, lineWidth: 2)
                                    }
                                Text(icon.title).ratioFont(.monoLabel).foregroundStyle(selected ? Color.ratioInk : Color.ratioInk2)
                            }
                        }
                        .buttonStyle(.ratioPress)
                        .accessibilityLabel("\(icon.title) app icon")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, RatioSpace.s)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var themePicker: some View {
        RatioSegmentedControl(options: [("light", "Light"), ("dark", "Dark"), ("auto", "Auto")], selection: $appearance)
    }

    private func setIcon(_ icon: AppIconChoice) {
        UIApplication.shared.setAlternateIconName(icon.assetName) { error in
            Task { @MainActor in
                if error == nil { iconName = icon.assetName } else { message = "The icon couldn't be changed." }
            }
        }
    }

    // MARK: III · Study

    private var study: some View {
        SettingsSection(number: "III", title: "Study") {
            SettingsRow("Modules", value: "\(profile.modules?.count ?? 0) of \(Module.allCases.count)") { sheet = .modules }
            SettingsRow("Year of study", value: profile.year.map { "Year \($0)" } ?? "Add") { sheet = .year }
            if !student.isPlus {
                SettingsRow("Free module", detail: profile.freeModuleChanges ?? 0 >= 1 ? "Changed once already" : "You can change it once",
                            value: student.freeModule?.title ?? "—") { sheet = .freeModule }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.s) {
                    weeklyTargetLabel
                    Spacer()
                    weeklyTargetStepper
                }
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    weeklyTargetLabel
                    weeklyTargetStepper
                }
            }
            .padding(.vertical, RatioSpace.s)
            Divider().overlay(Color.ratioRule)
            examPause
            SettingsToggle("Daily brief reminder", detail: "One a day. Mentions any reviews due", isOn: Binding(
                get: { settings.briefReminder ?? true },
                set: { on in
                    save(["settings.briefReminder": on])
                    if on { Task { await RatioNotifications.requestPermission() } }
                }
            ))
            if settings.briefReminder ?? true {
                SettingsTime("Reminder time", time: settings.briefTime ?? "08:30") { save(["settings.briefTime": $0]) }
            }
            SettingsToggle("Streak reminder", detail: "One evening nudge when your week is still within reach", isOn: Binding(
                get: { settings.streakReminder ?? true },
                set: { save(["settings.streakReminder": $0]) }
            ))
            if settings.streakReminder ?? true {
                SettingsTime("Streak reminder time", time: settings.streakTime ?? "19:00") { save(["settings.streakTime": $0]) }
            }
            SettingsTime("Quiet from", time: settings.quietStart ?? "22:00") { save(["settings.quietStart": $0]) }
            SettingsTime("Quiet until", time: settings.quietEnd ?? "08:00") { save(["settings.quietEnd": $0]) }
        }
    }

    private var weeklyTargetLabel: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            Text("Weekly target").ratioFont(.body)
            Text("Days a week you aim to study").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
        }
    }

    private var weeklyTargetStepper: some View {
        Stepper("\(settings.weeklyTarget ?? Streak.defaultTarget) of 7 days", value: Binding(
            get: { settings.weeklyTarget ?? Streak.defaultTarget },
            set: { save(["settings.weeklyTarget": $0]) }
        ), in: 1...7)
        .ratioFont(.monoData)
        .fixedSize()
    }

    /// PRD: "Exam pause: up to 3 weeks a year, which the student switches on."
    private var examPause: some View {
        let thisWeek = UKDate.key(for: UKDate.calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now)
        let year = String(thisWeek.prefix(4))
        let paused = settings.pausedWeeks ?? []
        let usedThisYear = paused.count { $0.hasPrefix(year) }
        let isPaused = paused.contains(thisWeek)
        return SettingsToggle("Exam pause", detail: "This week · up to 3 weeks a year · \(max(0, Streak.pausesPerYear - usedThisYear)) left", isOn: Binding(
            get: { isPaused },
            set: { on in
                let weeks = on ? paused + [thisWeek] : paused.filter { $0 != thisWeek }
                save(["settings.pausedWeeks": Array(weeks.suffix(12))])
            }
        ))
        .disabled(!isPaused && usedThisYear >= Streak.pausesPerYear)
    }

    // MARK: IV · Accessibility

    private var accessibility: some View {
        SettingsSection(number: "IV", title: "Accessibility") {
            SettingsToggle("Dyslexia-friendly mode", detail: "Atkinson Hyperlegible, wider spacing", isOn: $dyslexia)
            SettingsToggle("Extra duel time (30 s)", detail: "Matched with other extra-time players",
                           isOn: Binding(get: { extendedSeconds == DuelTime.extended }, set: { extendedSeconds = $0 ? DuelTime.extended : 0 }))
            SettingsToggle("Reduce motion", detail: "Changes without movement", isOn: $reduceMotion)
            SettingsToggle("Haptics", isOn: $haptics)
            Text("Accessibility features are always free.").ratioFont(.small).italic().foregroundStyle(Color.ratioInk2).padding(.top, RatioSpace.s)
        }
    }

    // MARK: V · Content

    private var content: some View {
        SettingsSection(number: "V", title: "Content") {
            SettingsRow("Report an error", value: "→") { sheet = .report }
            SettingsRow("Replay tutorials", detail: "The Today tour, then the duel tutorial", value: "→") {
                tourSeen = false
                duelTutorialSeen = false
                navigator.replayingTutorials = true
                navigator.backToToday()
            }
        }
    }

    // MARK: VI · Subscription

    private var subscription: some View {
        SettingsSection(number: "VI", title: "Subscription") {
            SettingsRow("Plan", value: planTitle)
            if let subscription = profile.subscription, student.isPlus {
                SettingsRow(subscription.revoked == true ? "Ended" : "Renews", value: subscription.expiresAt.formatted(.dateTime.day().month(.abbreviated).year()))
            } else if let licence = profile.licence, student.isPlus {
                SettingsRow("Licence until", value: licence.expiresAt.formatted(.dateTime.day().month(.abbreviated).year()))
            }
            if !student.isPlus {
                SettingsRow("Ratio Plus", value: "See plans →") { navigator.paywall = "" }
            }
            SettingsRow("Restore purchases", value: "→") {
                Task {
                    let restored = (try? await purchases.restore()) ?? false
                    message = restored ? "Your purchases are restored." : "No Ratio Plus purchase was found for this Apple ID."
                }
            }
            SettingsRow("Manage subscription", value: "↗") { managingSubscription = true }
            SettingsRow("University licence code", value: profile.licence?.universityName ?? "Enter") { sheet = .licence }
        }
    }

    private var planTitle: String {
        if !student.isPlus { return "Free" }
        if student.plusForEveryone && profile.subscription == nil && profile.licence == nil { return "Ratio Plus · Beta" }
        if let subscription = profile.subscription, subscription.expiresAt > .now {
            return "Ratio Plus · \(subscription.plan == "annual" ? "Annual" : "Monthly")"
        }
        return "Ratio Plus · \(profile.licence?.universityName ?? "Licence")"
    }

    // MARK: VII · Privacy and legal

    private var privacy: some View {
        SettingsSection(number: "VII", title: "Privacy and legal") {
            SettingsLink("Privacy policy", url: RatioLinks.privacy)
            SettingsLink("Terms", url: RatioLinks.terms)
            SettingsRow("Educational, not legal advice", value: "→") { sheet = .notice }
            if let exportFile {
                ShareLink(item: exportFile) {
                    SettingsRowLabel(title: "Export my data", detail: "UK GDPR · ready to share", value: "Share ↗")
                }
                .buttonStyle(.ratioPress)
            } else {
                SettingsRow("Export my data", detail: "UK GDPR", value: working ? "Preparing…" : "→") { Task { await export() } }
            }
            SettingsToggle("Share my progress with my university", detail: "Off unless you turn it on", isOn: Binding(
                get: { profile.consents?.universitySharing ?? false },
                set: { save(["consents.universitySharing": $0]) }
            ))
            SettingsToggle("Usage analytics", detail: "Anonymous; crash reports are always on", isOn: Binding(
                get: { profile.consents?.analytics ?? false },
                set: { save(["consents.analytics": $0]) }
            ))
        }
    }

    // MARK: VIII · Danger zone

    private var danger: some View {
        SettingsSection(number: "VIII", title: "Danger zone") {
            SettingsRow("Log out", value: "→") { session.signOut() }
            SettingsRow("Reset progress", detail: "Clears scores and history", value: "→") { confirming = .reset }
            SettingsRow("Delete account", detail: "Deleted now, with everything in it", value: "→", destructive: true) { confirming = .delete }
        }
    }

    // MARK: Actions

    private func save(_ fields: [String: Any]) {
        Task {
            do { try await UserRepository().update(uid: student.uid, fields) } catch { message = "That didn't save. Check your connection." }
        }
    }

    private func resetPassword() async {
        guard let email = Auth.auth().currentUser?.email else { return }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            message = "We've sent a link to \(email) to set a new password."
        } catch {
            message = "The reset email didn't send. Try again in a moment."
        }
    }

    private func export() async {
        working = true
        defer { working = false }
        do {
            let result = try await Functions.functions(region: "europe-west2").httpsCallable("exportData").call()
            guard let json = (result.data as? [String: Any])?["json"] as? String else { throw URLError(.cannotParseResponse) }
            let url = FileManager.default.temporaryDirectory.appending(path: "ratio-data-\(UKDate.key()).json")
            try Data(json.utf8).write(to: url)
            exportFile = url
        } catch {
            message = "Your data couldn't be exported just now. Try again."
        }
    }

    private func reset() async {
        do {
            _ = try await Functions.functions(region: "europe-west2").httpsCallable("resetProgress").call()
            message = "Your progress has been reset."
        } catch {
            message = "Reset didn't go through. Try again."
        }
    }

    private func deleteAccount() async {
        do {
            _ = try await Functions.functions(region: "europe-west2").httpsCallable("deleteAccount").call()
            session.signOut()
        } catch {
            message = "Your account couldn't be deleted just now. Try again, or contact us from the website."
        }
    }
}

// MARK: - Rows

private struct SettingsSection<Content: View>: View {
    let number: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                Text(number).ratioFont(.h1).italic().foregroundStyle(Color.ratioOxblood).accessibilityHidden(true)
                Text(title).ratioFont(.monoLabel)
            }
            .padding(.top, RatioSpace.l)
            .padding(.bottom, RatioSpace.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            content
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    var detail: String?
    let value: String
    var destructive = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    // The value under the title rather than squeezed beside it.
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        labels
                        Text(value).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Title, a dotted leader, the value (screens/30-settings.png).
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                        labels
                        DottedLeader().frame(minWidth: RatioSpace.s)
                        Text(value).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.vertical, RatioSpace.s)
            .contentShape(Rectangle())
            Divider().overlay(Color.ratioRule)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            Text(title).ratioFont(.body).foregroundStyle(destructive ? Color.ratioOxblood : Color.ratioInk)
            if let detail { Text(detail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2) }
        }
        .layoutPriority(1)
    }
}

/// A dotted rule leading from a label to its value.
private struct DottedLeader: View {
    var body: some View {
        Line()
            .stroke(Color.ratioRule, style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

private struct SettingsRow: View {
    let title: String
    var detail: String?
    let value: String
    var destructive = false
    var action: (() -> Void)?

    init(_ title: String, detail: String? = nil, value: String, destructive: Bool = false, action: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.value = value
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { SettingsRowLabel(title: title, detail: detail, value: value, destructive: destructive) }
                .buttonStyle(.ratioPress)
        } else {
            SettingsRowLabel(title: title, detail: detail, value: value).accessibilityElement(children: .combine)
        }
    }
}

private struct SettingsLink: View {
    let title: String
    let url: URL

    init(_ title: String, url: URL) {
        self.title = title
        self.url = url
    }

    var body: some View {
        Link(destination: url) { SettingsRowLabel(title: title, value: "↗") }.buttonStyle(.ratioPress)
    }
}

private struct SettingsToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(title).ratioFont(.body)
                    if let detail { Text(detail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2) }
                }
            }
            .tint(Color.ratioControl)
            .padding(.vertical, RatioSpace.s)
            Divider().overlay(Color.ratioRule)
        }
    }
}

/// A time of day stored as "HH:mm".
private struct SettingsTime: View {
    let title: String
    let time: String
    let save: (String) -> Void

    init(_ title: String, time: String, save: @escaping (String) -> Void) {
        self.title = title
        self.time = time
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            DatePicker(title, selection: Binding(get: { date(time) }, set: { save(Self.format($0)) }), displayedComponents: .hourAndMinute)
                .ratioFont(.body)
                .padding(.vertical, RatioSpace.xs)
            Divider().overlay(Color.ratioRule)
        }
    }

    private func date(_ time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts.first ?? 8, minute: parts.last ?? 0, second: 0, of: .now) ?? .now
    }

    private static func format(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

// MARK: - App icons

/// The alternate icons (screens/00-logo), previewed as the mark on each ground.
struct AppIconChoice: Identifiable {
    let title: String
    /// Nil for the primary icon.
    let assetName: String?
    let ground: Color
    let glyph: Color
    let dot: Color

    var id: String { title }

    static let all: [AppIconChoice] = [
        AppIconChoice(title: "Ink", assetName: nil, ground: Color(red: 0.114, green: 0.106, blue: 0.094), glyph: Color(red: 0.953, green: 0.937, blue: 0.906), dot: Color(red: 0.608, green: 0.165, blue: 0.141)),
        AppIconChoice(title: "Parchment", assetName: "AppIcon-Parchment", ground: Color(red: 0.953, green: 0.937, blue: 0.906), glyph: Color(red: 0.114, green: 0.106, blue: 0.094), dot: Color(red: 0.608, green: 0.165, blue: 0.141)),
        AppIconChoice(title: "Oxblood", assetName: "AppIcon-Oxblood", ground: Color(red: 0.608, green: 0.165, blue: 0.141), glyph: Color(red: 0.953, green: 0.937, blue: 0.906), dot: Color(red: 0.953, green: 0.937, blue: 0.906)),
        AppIconChoice(title: "Chambers", assetName: "AppIcon-Chambers", ground: Color(red: 0.16, green: 0.17, blue: 0.19), glyph: Color(red: 0.953, green: 0.937, blue: 0.906), dot: Color(red: 0.608, green: 0.165, blue: 0.141)),
        AppIconChoice(title: "Gold", assetName: "AppIcon-Gold", ground: Color(red: 0.580, green: 0.396, blue: 0.094), glyph: Color(red: 0.953, green: 0.937, blue: 0.906), dot: Color(red: 0.114, green: 0.106, blue: 0.094)),
        AppIconChoice(title: "Green", assetName: "AppIcon-Green", ground: Color(red: 0.110, green: 0.443, blue: 0.278), glyph: Color(red: 0.953, green: 0.937, blue: 0.906), dot: Color(red: 0.953, green: 0.937, blue: 0.906)),
    ]

    var preview: some View {
        RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous)
            .fill(ground)
            .overlay(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule))
            .overlay {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("R").font(.custom("NewsreaderDisplay-Regular", size: 30)).foregroundStyle(glyph)
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
            }
    }
}

// MARK: - Sheets

private struct NameSheet: View {
    let profile: UserProfile
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var initial = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Display name").ratioFont(.h2)
            Text("Other players see your first name and the first letter of your surname.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            RatioTextField("First name", placeholder: "Amara", text: $name)
            RatioTextField("Surname initial (optional)", placeholder: "O", text: $initial)
            if failed { Text("That didn't save. Check the name and try again.").ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
            RatioButton("Save", isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && name.count <= 40) {
                Task {
                    let letter = initial.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
                    var fields: [String: Any] = ["displayName": name.trimmingCharacters(in: .whitespaces)]
                    fields["initial"] = letter.isEmpty ? FieldValue.delete() : letter
                    do { try await UserRepository().update(uid: uid, fields); dismiss() } catch { failed = true }
                }
            }
            Spacer()
        }
        .padding(RatioSpace.m)
        .ratioPage()
        .onAppear {
            name = profile.displayName ?? ""
            initial = profile.initial ?? ""
        }
    }
}

private struct ModulesSheet: View {
    let profile: UserProfile
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @State private var modules: Set<Module> = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Module.allCases) { module in
                        Button {
                            if modules.contains(module) { modules.remove(module) } else { modules.insert(module) }
                        } label: {
                            HStack {
                                Text(module.title).foregroundStyle(Color.ratioInk)
                                Spacer()
                                if modules.contains(module) { Image(systemName: "checkmark").foregroundStyle(Color.ratioOxblood) }
                            }
                        }
                        .accessibilityAddTraits(modules.contains(module) ? .isSelected : [])
                    }
                } header: {
                    Text("Modules this year")
                } footer: {
                    Text(failed ? "That didn't save. Try again." : "They set the order of your lessons.")
                }
            }
            .navigationTitle("Modules")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let ordered = Module.allCases.filter(modules.contains).map(\.rawValue)
                            do { try await UserRepository().update(uid: uid, ["modules": ordered]); dismiss() } catch { failed = true }
                        }
                    }
                    .disabled(modules.isEmpty)
                }
            }
        }
        .onAppear { modules = Set(profile.modules ?? []) }
    }
}

/// Year of study — optional, set from Me or Settings.
struct YearSheet: View {
    let uid: String
    let year: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var failed = false

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: RatioSpace.xs)) : AnyLayout(HStackLayout(spacing: RatioSpace.xs))
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Year of study").ratioFont(.h2)
            layout {
                ForEach(1...3, id: \.self) { option in
                    Button {
                        Task {
                            do { try await UserRepository().update(uid: uid, ["year": option]); dismiss() } catch { failed = true }
                        }
                    } label: {
                        Text("Year \(option)")
                            .ratioFont(.h3)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            // Parchment on ink flips with the theme (ink turns light in dark mode).
                            .foregroundStyle(year == option ? Color.ratioParchment : Color.ratioInk)
                            .background(year == option ? Color.ratioInk : Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule) }
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityAddTraits(year == option ? .isSelected : [])
                }
            }
            if failed { Text("That didn't save. Try again.").ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
            Spacer()
        }
        .padding(RatioSpace.m)
        .ratioPage()
    }
}

private struct FreeModuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StudentStore.self) private var student
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(student.profile.modules ?? []) { module in
                        Button {
                            Task {
                                do { try await PlanService.chooseFreeModule(module); dismiss() } catch { message = (error as NSError).localizedDescription }
                            }
                        } label: {
                            HStack {
                                Text(module.title).foregroundStyle(Color.ratioInk)
                                Spacer()
                                if module == student.freeModule { Image(systemName: "checkmark").foregroundStyle(Color.ratioOxblood) }
                            }
                        }
                    }
                } footer: {
                    Text(message ?? "The free plan includes one module in full. You can change it once.")
                }
            }
            .navigationTitle("Free module")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NoticeSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Educational, not legal advice").ratioFont(.h2)
            Text("Ratio helps you learn the law of England and Wales for your degree. It isn't legal advice, and nothing in it should be relied on for a real legal problem. The law is stated as at the date shown on each lesson and may have changed since. If you need advice, speak to a solicitor or an advice service.")
                .ratioFont(.body)
            Spacer()
        }
        .padding(RatioSpace.m)
        .ratioPage()
    }
}
