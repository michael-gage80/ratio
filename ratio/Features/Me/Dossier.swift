import SwiftUI

/// The four numbers at the top of Me: lessons secure, the weekly streak, duel win rate
/// against students, and the best board place this week or month.
struct StatTiles: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @State private var bestPlace: Int?

    var body: some View {
        let lessons = Module.allCases.flatMap { content.lessons(in: $0) }
        let secure = lessons.count { student.state(of: $0) == .secure }
        let streak = student.streak
        let weeks = streak.previousWeeks + (streak.daysThisWeek >= streak.target ? 1 : 0)
        let human = student.matches.filter { $0.isBot == false && $0.status == "complete" }.compactMap { $0.result(for: student.uid) }
        let wins = human.count { $0.winner == 0 }
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Lessons secure", "\(secure)")
                tile("Week streak", "\(weeks)", unit: weeks == 1 ? "week" : "weeks")
            }
            GridRow {
                tile("Duel win rate", human.isEmpty ? "—" : "\(Int((100 * Double(wins) / Double(human.count)).rounded()))%",
                     unit: human.isEmpty ? nil : "of \(human.count)")
                tile("Best board place", bestPlace.map { "\($0)\(Ordinal.suffix($0))" } ?? "—", unit: bestPlace == nil ? nil : "this week or month")
            }
        }
        .task(id: student.matches.count) { bestPlace = await Self.bestPlace(uid: student.uid) }
    }

    private func tile(_ label: String, _ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text(value).font(.custom("NewsreaderDisplay-Regular", size: 34, relativeTo: .largeTitle))
            if let unit { Text(unit).ratioFont(.small).foregroundStyle(Color.ratioInk2) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.ratioRule) }
        .accessibilityElement(children: .combine)
    }

    private static func bestPlace(uid: String) async -> Int? {
        var places: [Int] = []
        for period in [BoardPeriod.weekly, .monthly] {
            if let entry = await BoardService.entry(period, uid: uid), entry.wins > 0,
               let rank = await BoardService.rank(of: entry, period: period, scope: .everyone) {
                places.append(rank)
            }
        }
        return places.min()
    }
}

/// The last 12 weeks, a square a day (Monday at the top), filled where the student was active.
struct ActivityHeatmap: View {
    let activeDays: Set<String>
    private static let weeks = 12

    var body: some View {
        let calendar = UKDate.calendar
        let monday = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let start = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: monday) ?? monday
        let days = (0..<(Self.weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let active = days.count { activeDays.contains(UKDate.key(for: $0)) && $0 <= .now }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity").ratioFont(.h2)
                Spacer()
                Text("\(active) \(active == 1 ? "day" : "days") in 12 weeks").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            HStack(spacing: 4) {
                ForEach(0..<Self.weeks, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = days[week * 7 + weekday]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day > .now ? Color.clear : activeDays.contains(UKDate.key(for: day)) ? Color.ratioInk : Color.ratioRule)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Quiet, dated moments in the student's story — firsts, not collectibles.
struct MilestoneTimeline: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content

    private struct Milestone: Identifiable {
        let date: Date
        let text: String
        var id: String { text }
    }

    private var milestones: [Milestone] {
        var list: [Milestone] = []
        let tests = student.attempts.filter { $0.lessonId != nil && $0.createdAt != nil }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        if let first = tests.first, let date = first.createdAt {
            list.append(Milestone(date: date, text: "First tests marked — \(first.lessonId.flatMap { content.lesson(id: $0)?.title } ?? "a lesson")"))
        }
        if let date = student.attempts.filter({ ($0.delayed?.total ?? 0) > 0 }).compactMap(\.createdAt).min() {
            list.append(Milestone(date: date, text: "First review a week or more later"))
        }
        if let date = firstFullWeek {
            list.append(Milestone(date: date, text: "First week at your target"))
        }
        let duels = student.matches.filter { $0.status == "complete" }
        if let date = duels.compactMap(\.createdAt).min() {
            list.append(Milestone(date: date, text: "First duel"))
        }
        if let date = duels.filter({ $0.isBot == false && $0.result(for: student.uid)?.winner == 0 }).compactMap(\.createdAt).min() {
            list.append(Milestone(date: date, text: "First win against another student"))
        }
        if tests.count >= 10, let date = tests[9].createdAt {
            list.append(Milestone(date: date, text: "Ten lessons tested"))
        }
        return list.sorted { $0.date < $1.date }
    }

    /// The last active day of the first week that met the weekly target.
    private var firstFullWeek: Date? {
        let calendar = UKDate.calendar
        let weeks = Dictionary(grouping: student.activeDays.compactMap { UKDate.date(fromKey: $0) }) {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start ?? $0
        }
        guard let start = weeks.filter({ $0.value.count >= student.streak.target }).keys.min() else { return nil }
        return weeks[start]?.max()
    }

    var body: some View {
        let milestones = milestones
        if !milestones.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your story so far").ratioFont(.h2).padding(.bottom, 12)
                ForEach(milestones) { milestone in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle().strokeBorder(Color.ratioInk, lineWidth: 1).frame(width: 9, height: 9).padding(.top, 6)
                            if milestone.id != milestones.last?.id {
                                Rectangle().fill(Color.ratioRule).frame(width: 1).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.date.formatted(.dateTime.day().month(.abbreviated).year())).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Text(milestone.text).ratioFont(.body)
                        }
                        .padding(.bottom, 16)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
