import FirebaseFirestore
import SwiftUI

/// One line on the notifications page. The feed is built from what the student's
/// documents already hold — challenges, briefs, reviews, tests, the news — so nothing
/// extra is stored; only when the page was last opened (`notificationsReadAt`).
struct FeedItem: Identifiable {
    enum Category: String, CaseIterable {
        case duels = "Duels"
        case streak = "Streak & brief"
        case reviews = "Reviews & progress"
        case news = "News & quiz"
    }

    enum Action {
        case duel, brief, news, lesson(String)
    }

    let id: String
    let category: Category
    let title: String
    var detail: String?
    let date: Date
    /// Something to do now; kept at the top until it's done.
    var pinned = false
    var action: Action?
}

extension StudentStore {
    /// The last 30 days, pinned items first, then newest first.
    func feed(content: ContentStore, now: Date = .now) -> [FeedItem] {
        let since = now.addingTimeInterval(-30 * 86_400)
        var items: [FeedItem] = []

        // Duels
        for challenge in challengeHistory {
            let opponent = challenge.opponent(of: uid).name
            let created = challenge.createdAt ?? now
            let open = challenge.status == "open" && challenge.expiresAt > now
            let myTurn = challenge.done[uid] != true
            if challenge.isFrom(uid) {
                if open, myTurn, challenge.done[challenge.opponent(of: uid).uid] == true {
                    items.append(FeedItem(id: "c-\(challenge.id)", category: .duels, title: "\(opponent) played their half — your go",
                                          detail: DuelScope.title(of: challenge.moduleId), date: created, pinned: true, action: .duel))
                } else if challenge.status == "declined" {
                    items.append(FeedItem(id: "c-\(challenge.id)", category: .duels, title: "\(opponent) declined your challenge",
                                          date: challenge.declinedAt ?? created, action: .duel))
                }
            } else if open, myTurn {
                items.append(FeedItem(id: "c-\(challenge.id)", category: .duels, title: "\(opponent) challenged you",
                                      detail: "\(DuelScope.title(of: challenge.moduleId)) · \(max(1, Int(challenge.expiresAt.timeIntervalSince(now) / 3600))) h left",
                                      date: created, pinned: true, action: .duel))
            } else if !challenge.isFrom(uid), challenge.status != "declined", challenge.status != "complete" {
                items.append(FeedItem(id: "c-\(challenge.id)", category: .duels, title: "\(opponent) challenged you", date: created, action: .duel))
            }
            if challenge.status == "complete", let result = challenge.results?[uid] {
                let verdict = result.winner == 0 ? "You won" : result.winner == nil ? "You drew" : "You lost"
                items.append(FeedItem(id: "r-\(challenge.id)", category: .duels, title: "\(verdict) \(result.score[0])–\(result.score[1]) v \(opponent)",
                                      detail: "Challenge · \(DuelScope.title(of: challenge.moduleId))", date: challenge.completedAt ?? created, action: .duel))
            }
        }

        // Streak & brief
        if let brief, let current = currentStep(of: brief, content: content) {
            let kind = brief.steps[current].kind.rawValue
            items.append(FeedItem(id: "brief-\(brief.date)", category: .streak, title: "Today's brief: \(brief.title)",
                                  detail: "\(brief.minutes) min · next, the \(kind)", date: UKDate.calendar.startOfDay(for: now), pinned: true, action: .brief))
        }
        let week = streak
        let activeToday = week.week[safe: week.todayIndex]?.active ?? false
        let remaining = week.target - week.daysThisWeek
        if !week.isPaused, !activeToday, remaining > 0, remaining <= 7 - week.todayIndex,
           let evening = Self.time(settings.streakTime ?? "19:00", on: now), now >= evening {
            items.append(FeedItem(id: "streak-\(UKDate.key())", category: .streak, title: "\(remaining) more \(remaining == 1 ? "day" : "days") to keep your week",
                                  detail: "\(week.daysThisWeek) of \(week.target) so far", date: evening, pinned: true, action: .brief))
        }

        // Reviews & progress
        let due = self.items.filter { $0.due <= now }
        if let latest = due.map(\.due).max() {
            items.append(FeedItem(id: "reviews", category: .reviews, title: "\(due.count) \(due.count == 1 ? "review" : "reviews") due",
                                  detail: "They're in today's brief.", date: latest, pinned: true, action: .brief))
        }
        for attempt in attempts {
            guard let id = attempt.lessonId, let at = attempt.createdAt, at > since, let lesson = content.lesson(id: id) else { continue }
            items.append(FeedItem(id: "t-\(id)-\(at.timeIntervalSince1970)", category: .reviews, title: "Tests marked: \(lesson.title)",
                                  detail: "Your profile has moved.", date: at, action: .lesson(id)))
        }

        // News & quiz
        if let quiz, let sunday = UKDate.date(fromKey: quiz.sunday), sunday > since {
            items.append(FeedItem(id: "quiz-\(quiz.sunday)", category: .news, title: "The Sunday quiz is out",
                                  detail: "\(quiz.questions.count) questions on the week's stories", date: sunday, action: .news))
        }
        for story in news where story.whyItMatters != nil && story.publishedAt > since {
            items.append(FeedItem(id: "n-\(story.id)", category: .news, title: story.title,
                                  detail: "Why it matters · \(story.source)", date: story.publishedAt, action: .news))
        }

        return items.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
    }

    func hasUnreadNotifications(content: ContentStore) -> Bool {
        let readAt = profile.notificationsReadAt ?? .distantPast
        return feed(content: content).contains { $0.date > readAt }
    }

    /// "19:00" today, UK time.
    fileprivate static func time(_ hhmm: String, on day: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return UKDate.calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}

/// The bell on Today: duels, streak & brief, reviews & progress, news & quiz. Opening
/// the page marks everything read.
struct NotificationsView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    /// Captured on opening, so what was new stays marked while the page is open.
    @State private var readAt: Date?

    var body: some View {
        let items = student.feed(content: content)
        let pinned = items.filter(\.pinned)
        let history = items.filter { !$0.pinned }
        List {
            Text("Notifications\(Text(".").foregroundStyle(Color.ratioOxblood))")
                .ratioFont(.display)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            if items.isEmpty {
                Text("Nothing yet. Challenges, reviews and the week's news will show up here.")
                    .ratioFont(.body)
                    .foregroundStyle(Color.ratioInk2)
                    .listRowBackground(Color.clear)
            }
            if !pinned.isEmpty {
                Section("To do") {
                    ForEach(pinned) { row($0) }
                }
            }
            if !history.isEmpty {
                Section("Last 30 days") {
                    ForEach(history) { row($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard readAt == nil else { return }
            readAt = student.profile.notificationsReadAt ?? .distantPast
            try? await UserRepository().update(uid: student.uid, ["notificationsReadAt": FieldValue.serverTimestamp()])
        }
    }

    private func row(_ item: FeedItem) -> some View {
        let unread = item.date > (readAt ?? .distantPast)
        return Button { perform(item.action) } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon(item.category))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.ratioInk2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).ratioFont(.h3).multilineTextAlignment(.leading)
                    Text([item.category.rawValue, item.detail, item.date.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: 0)
                if unread {
                    Circle().fill(Color.ratioOxblood).frame(width: 8, height: 8).padding(.top, 8).accessibilityLabel("New")
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.ratioPaper)
        .disabled(item.action.map { _ in false } ?? true)
        .accessibilityElement(children: .combine)
    }

    private func icon(_ category: FeedItem.Category) -> String {
        switch category {
        case .duels: "bolt"
        case .streak: "flame"
        case .reviews: "arrow.triangle.2.circlepath"
        case .news: "newspaper"
        }
    }

    private func perform(_ action: FeedItem.Action?) {
        switch action {
        case .duel: navigator.tab = .duel
        case .brief: navigator.todayPath = [.brief]
        case .news: navigator.todayPath = [.news]
        case .lesson(let id): navigator.pathwayPath = [.overview(id)]; navigator.tab = .pathway
        case nil: break
        }
    }
}
