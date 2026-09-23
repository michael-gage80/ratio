import FirebaseFirestore
import SwiftUI

/// Which board: the period (resetting at UK midnight, Monday, and the 1st) and the
/// students on it (PRD: "Filters: everyone, my university, friends").
enum BoardPeriod: String, CaseIterable, Identifiable {
    case daily, weekly, monthly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Same keys as functions/src/boards.ts: "day-2026-09-23", "week-2026-09-21", "month-2026-09".
    func key(for date: Date = .now) -> String {
        let calendar = UKDate.calendar
        switch self {
        case .daily:
            return "day-\(UKDate.key(for: date))"
        case .weekly:
            let monday = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            return "week-\(UKDate.key(for: monday))"
        case .monthly:
            return "month-\(UKDate.key(for: date).prefix(7))"
        }
    }

    var resets: String {
        switch self {
        case .daily: "Daily board resets at 00:00 UK"
        case .weekly: "Weekly board resets Monday 00:00 UK"
        case .monthly: "Monthly board resets on the 1st, 00:00 UK"
        }
    }
}

enum BoardScope: String, CaseIterable, Identifiable {
    case everyone, university, friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: "Everyone"
        case .university: "My university"
        case .friends: "Friends"
        }
    }
}

/// boards/{key}/entries/{uid}.
nonisolated struct BoardEntry: Decodable, Identifiable, Equatable {
    var id: String { uid }
    var uid: String
    var name: String
    var initial: String
    var avatarVersion: Int?
    var universityId: String?
    var universityName: String?
    var rating: Int
    var wins: Int
}

/// Reads the boards. Ranks past the top 100 are counted rather than listed.
enum BoardService {
    static let listed = 100

    private static func entries(_ period: BoardPeriod) -> CollectionReference {
        Firestore.firestore().collection("boards").document(period.key()).collection("entries")
    }

    /// The top of the board for everyone or a university, or everyone in `friends`.
    static func top(_ period: BoardPeriod, scope: BoardScope, universityId: String?, friends: [String]) async throws -> [BoardEntry] {
        switch scope {
        case .everyone:
            return try await entries(period).order(by: "wins", descending: true).order(by: "rating", descending: true)
                .limit(to: listed).getDocuments().documents.compactMap { try? $0.data(as: BoardEntry.self) }
        case .university:
            guard let universityId else { return [] }
            return try await entries(period).whereField("universityId", isEqualTo: universityId)
                .order(by: "wins", descending: true).order(by: "rating", descending: true)
                .limit(to: listed).getDocuments().documents.compactMap { try? $0.data(as: BoardEntry.self) }
        case .friends:
            var found: [BoardEntry] = []
            // Firestore's `in` takes up to 30 values at a time.
            for chunk in stride(from: 0, to: friends.count, by: 30).map({ Array(friends[$0..<min($0 + 30, friends.count)]) }) {
                found += try await entries(period).whereField(FieldPath.documentID(), in: chunk).getDocuments()
                    .documents.compactMap { try? $0.data(as: BoardEntry.self) }
            }
            return found.sorted { ($0.wins, $0.rating) > ($1.wins, $1.rating) }
        }
    }

    static func entry(_ period: BoardPeriod, uid: String) async -> BoardEntry? {
        try? await entries(period).document(uid).getDocument().data(as: BoardEntry.self)
    }

    /// 1 + everyone with more wins — for a student outside the listed top.
    static func rank(of entry: BoardEntry, period: BoardPeriod, scope: BoardScope) async -> Int? {
        var query: Query = entries(period).whereField("wins", isGreaterThan: entry.wins)
        if scope == .university {
            guard let universityId = entry.universityId else { return nil }
            query = query.whereField("universityId", isEqualTo: universityId)
        }
        guard let count = try? await query.count.getAggregation(source: .server).count else { return nil }
        return count.intValue + 1
    }
}

/// screens/41-boards.png (and 42, dark) — the podium, the top 100, and the student's
/// own row pinned at the bottom wherever they are (PRD: "Boards").
struct BoardsView: View {
    @Environment(StudentStore.self) private var student
    @AppStorage("boards.period") private var period: BoardPeriod = .weekly
    @AppStorage("boards.scope") private var scope: BoardScope = .everyone
    @State private var entries: [BoardEntry] = []
    @State private var mine: BoardEntry?
    @State private var myRank: Int?
    @State private var loading = true
    @State private var failed = false

    private var loadKey: String { "\(period.rawValue)-\(scope.rawValue)-\(student.friends.count)-\(student.matches.count)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Boards.").ratioFont(.display)
                    Text("Ranked by wins in human duels. Sparring partners never count.").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                }
                picker(BoardPeriod.allCases, selection: $period) { $0.title }
                picker(BoardScope.allCases, selection: $scope) { $0.title }
                content
                Text(period.resets).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            if let mine {
                PinnedRow(entry: mine, rank: myRank)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: loadKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else if failed {
            empty("The boards didn't load. Pull to try again.")
        } else if scope == .university && student.profile.universityId == nil {
            empty("Boards by university need a listed university on your profile.")
        } else if scope == .friends && student.friends.isEmpty {
            empty("Students you duel appear here. Play a friend lobby or a ranked match to start your list.")
        } else if entries.allSatisfy({ $0.wins == 0 }) {
            empty(period == .daily ? "No wins yet today. Win a human duel to get on the board." : "No wins yet this \(period == .weekly ? "week" : "month"). Win a human duel to get on the board.")
        } else {
            let ranked = entries.filter { $0.wins > 0 }
            Podium(entries: Array(ranked.prefix(3)))
            VStack(spacing: 0) {
                HStack {
                    Text("No.").frame(width: 36, alignment: .leading)
                    Text("Name")
                    Spacer()
                    Text("Wins").frame(width: 44, alignment: .trailing)
                    Text("Rating").frame(width: 64, alignment: .trailing)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .padding(.vertical, 10)
                .accessibilityHidden(true)
                ForEach(Array(ranked.enumerated()).dropFirst(3), id: \.element.id) { index, entry in
                    Divider().overlay(Color.ratioRule)
                    BoardRow(entry: entry, rank: index + 1, isMine: entry.uid == student.uid)
                }
            }
        }
    }

    private func picker<Option: Identifiable & Hashable>(_ options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) -> some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button { selection.wrappedValue = option } label: {
                    Text(title(option))
                        .ratioFont(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection.wrappedValue == option ? Color.ratioOnInk : Color.ratioInk)
                        .background(selection.wrappedValue == option ? Color.ratioInk : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == option ? .isSelected : [])
            }
        }
        .padding(4)
        .ratioGlassCapsule()
        .overlay(Capsule().strokeBorder(Color.ratioRule))
    }

    private func empty(_ text: String) -> some View {
        VStack(spacing: 16) {
            RatioSpotArt.pediment.view.frame(width: 110).foregroundStyle(Color.ratioInk2)
            Text(text).ratioFont(.body).multilineTextAlignment(.center).foregroundStyle(Color.ratioInk2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let friends = Array(Set(student.friends + [student.uid]))
            entries = try await BoardService.top(period, scope: scope, universityId: student.profile.universityId, friends: friends)
            failed = false
        } catch {
            failed = true
        }
        mine = await BoardService.entry(period, uid: student.uid)
        if let mine, mine.wins > 0 {
            if let index = entries.firstIndex(where: { $0.uid == mine.uid }) {
                myRank = index + 1
            } else if scope == .friends {
                myRank = nil
            } else {
                myRank = await BoardService.rank(of: mine, period: period, scope: scope)
            }
        } else {
            myRank = nil
        }
    }
}

private struct Podium: View {
    let entries: [BoardEntry]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach([1, 0, 2], id: \.self) { index in
                if let entry = entries[safe: index] {
                    column(entry, place: index + 1)
                } else {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.ratioInk).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func column(_ entry: BoardEntry, place: Int) -> some View {
        VStack(spacing: 6) {
            if place == 1 {
                Image(systemName: "laurel.leading").font(.title3).foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            }
            ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: place == 1 ? 72 : 56)
            Text(entry.name).ratioFont(.h3).lineLimit(1).minimumScaleFactor(0.8)
            Text(university(entry)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).lineLimit(1)
            Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins")").ratioFont(.monoData)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.ratioPaper)
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ratioRule) }
                Text("\(place)").ratioFont(.h1).italic().foregroundStyle(place == 1 ? Color.ratioOxblood : Color.ratioInk2).padding(.top, 8)
            }
            .frame(height: place == 1 ? 110 : place == 2 ? 80 : 60)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place == 1 ? "First" : place == 2 ? "Second" : "Third"): \(entry.name), \(entry.wins) wins")
    }
}

private func university(_ entry: BoardEntry) -> String {
    UniversityDirectory.shortName(id: entry.universityId) ?? entry.universityName ?? ""
}

private struct BoardRow: View {
    let entry: BoardEntry
    let rank: Int
    let isMine: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)").ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(width: 30, alignment: .leading)
            ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).ratioFont(.h3).lineLimit(1)
                Text(university(entry)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).lineLimit(1)
            }
            Spacer()
            Text("\(entry.wins)").ratioFont(.monoData).frame(width: 44, alignment: .trailing)
            Text(entry.rating.formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isMine ? 8 : 0)
        .background(isMine ? Color.ratioSunk : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(entry.name)\(isMine ? ", you" : ""), \(university(entry)), \(entry.wins) wins, rating \(entry.rating)")
    }
}

/// The student's own row, always visible (PRD: "pinned, even when they're outside the top 100").
private struct PinnedRow: View {
    let entry: BoardEntry
    let rank: Int?

    var body: some View {
        HStack(spacing: 12) {
            Text(rank.map { "\($0)" } ?? "–").ratioFont(.monoData).foregroundStyle(Color.ratioOxblood).frame(minWidth: 28, alignment: .leading)
            ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: 36)
            Text(entry.name).ratioFont(.h3).lineLimit(1)
            Text(university(entry)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).lineLimit(1)
            Spacer()
            Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins")").ratioFont(.monoData)
            Text(entry.rating.formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .ratioGlassCapsule()
        .overlay(Capsule().strokeBorder(Color.ratioRule))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You: \(rank.map { "rank \($0)" } ?? "not ranked yet"), \(entry.wins) wins, rating \(entry.rating)")
    }
}
