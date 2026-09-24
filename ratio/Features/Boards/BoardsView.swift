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
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("boards.period") private var period: BoardPeriod = .weekly
    @AppStorage("boards.scope") private var scope: BoardScope = .everyone
    @State private var entries: [BoardEntry] = []
    @State private var mine: BoardEntry?
    @State private var myRank: Int?
    @State private var loading = true
    @State private var failed = false
    /// "Share my result": the student's place as an image card.
    @State private var shareCard: Image?

    private var loadKey: String { "\(period.rawValue)-\(scope.rawValue)-\(student.friends.count)-\(student.matches.count)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                RatioPageHeader(title: "Boards", subtitle: "\(scope.title) · ranked by wins in human duels. Sparring partners never count.") {
                    scopeFilter
                }
                picker(BoardPeriod.allCases, selection: $period) { $0.title }
                content
                if let shareCard {
                    ShareLink(item: shareCard, preview: SharePreview("My place on Ratio's \(period.title.lowercased()) board", image: shareCard)) {
                        Label("Share my result", systemImage: "square.and.arrow.up")
                            .ratioFont(.h3)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule) }
                    }
                    .buttonStyle(.ratioPress)
                }
                Text(period.resets)
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.vertical, RatioSpace.s)
        }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            if let mine {
                PinnedRow(entry: mine, rank: myRank)
                    .padding(.horizontal, RatioSpace.s)
                    .padding(.bottom, RatioSpace.xs)
            }
        }
        .ratioPage()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: loadKey) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && entries.isEmpty {
            table(Self.placeholders).ratioSkeleton()
        } else if failed {
            RatioErrorState(message: "The boards didn't load. Check your connection and try again.") { Task { await load() } }
        } else if scope == .university && student.profile.universityId == nil {
            empty("Boards by university need a listed university on your profile.")
        } else if scope == .friends && student.friends.isEmpty {
            empty("Students you duel appear here. Play a friend lobby or a ranked match to start your list.")
        } else if entries.allSatisfy({ $0.wins == 0 }) {
            empty(period == .daily ? "No wins yet today. Win a human duel to get on the board." : "No wins yet this \(period == .weekly ? "week" : "month"). Win a human duel to get on the board.")
        } else {
            table(entries.filter { $0.wins > 0 })
        }
    }

    /// The podium and the rows below it; at accessibility text sizes, one list from 1st.
    @ViewBuilder
    private func table(_ ranked: [BoardEntry]) -> some View {
        let large = typeSize.isAccessibilitySize
        if !large {
            Podium(entries: Array(ranked.prefix(3)))
        }
        VStack(spacing: 0) {
            if !large {
                HStack(spacing: RatioSpace.s) {
                    Text("No.").frame(width: 32, alignment: .leading)
                    Text("Name")
                    Spacer()
                    Text("Wins").frame(width: 48, alignment: .trailing)
                    Text("Rating").frame(width: 64, alignment: .trailing)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .padding(.vertical, RatioSpace.xs)
                .accessibilityHidden(true)
            }
            ForEach(Array(ranked.enumerated()).dropFirst(large ? 0 : 3), id: \.element.id) { index, entry in
                Divider().overlay(Color.ratioRule)
                BoardRow(entry: entry, rank: index + 1, isMine: entry.uid == student.uid)
            }
        }
    }

    /// Shaped like a board while it loads.
    private static let placeholders = (1...8).map { n in
        BoardEntry(uid: "placeholder-\(n)", name: "Student name", initial: "R", universityName: "University", rating: 1200, wins: 10 - n)
    }

    /// Everyone, my university or friends, behind a small filter icon.
    private var scopeFilter: some View {
        Menu {
            Picker("Show", selection: $scope) {
                ForEach(BoardScope.allCases) { Text($0.title).tag($0) }
            }
        } label: {
            Image(systemName: scope == .everyone ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Filter: \(scope.title)")
    }

    /// Daily, weekly, monthly: a solid paper track with the chosen period in ink
    /// (screens/41-boards.png).
    private func picker<Option: Identifiable & Hashable>(_ options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String) -> some View {
        // Stacked at accessibility sizes, so words never break mid-way.
        let stacked = typeSize.isAccessibilitySize
        let shape = RoundedRectangle(cornerRadius: stacked ? RatioRadius.panel : 100, style: .continuous)
        return (stacked ? AnyLayout(VStackLayout(spacing: RatioSpace.xxs)) : AnyLayout(HStackLayout(spacing: RatioSpace.xxs))) {
            ForEach(options) { option in
                let selected = selection.wrappedValue == option
                Button {
                    withAnimation(RatioMotion.tap) { selection.wrappedValue = option }
                } label: {
                    Text(title(option))
                        .ratioFont(.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        // Parchment on ink flips with the theme (ink turns light in dark mode).
                        .foregroundStyle(selected ? Color.ratioParchment : Color.ratioInk)
                        .background(selected ? Color.ratioInk : Color.clear, in: shape)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(RatioSpace.xxs)
        .background(Color.ratioPaper, in: shape)
        .overlay(shape.strokeBorder(Color.ratioRule))
    }

    private func empty(_ text: String) -> some View {
        RatioEmptyState(art: .pediment, message: text)
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
        shareCard = mine.flatMap { $0.wins > 0 ? renderShareCard($0) : nil }
    }

    private func renderShareCard(_ entry: BoardEntry) -> Image? {
        let renderer = ImageRenderer(content: BoardShareCard(entry: entry, rank: myRank, period: period, scope: scope))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The image shared from "Share my result" — always in light colours, like a printed card.
private struct BoardShareCard: View {
    let entry: BoardEntry
    let rank: Int?
    let period: BoardPeriod
    let scope: BoardScope

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack {
                Text("R\(Text(".").foregroundStyle(Color.ratioOxblood))").font(.custom("NewsreaderDisplay-Regular", size: 34))
                Spacer()
                Text("\(period.title) board · \(scope.title)".uppercased()).font(.custom("IBMPlexMono-Regular", size: 11)).foregroundStyle(Color.ratioInk2)
            }
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            Spacer(minLength: 0)
            if let rank {
                Text("\(rank)\(Text(Ordinal.suffix(rank)).font(.custom("NewsreaderDisplay-Italic", size: 44)))")
                    .font(.custom("NewsreaderDisplay-Regular", size: 120))
            }
            Text(entry.name).font(.custom("NewsreaderDisplay-Regular", size: 30))
            Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins") in human duels · rating \(entry.rating)")
                .font(.custom("NewsreaderText-Italic", size: 18))
                .foregroundStyle(Color.ratioInk2)
            Spacer(minLength: 0)
            Rectangle().fill(Color.ratioRule).frame(height: 1)
            Text("RATIO · LAW, LEARNT AND DUELLED").font(.custom("IBMPlexMono-Regular", size: 11)).foregroundStyle(Color.ratioInk2)
        }
        .padding(32)
        .frame(width: 360, height: 450)
        .background(Color.ratioParchment)
        .foregroundStyle(Color.ratioInk)
        .environment(\.colorScheme, .light)
    }
}

enum Ordinal {
    /// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
    static func suffix(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

private struct Podium: View {
    let entries: [BoardEntry]

    var body: some View {
        HStack(alignment: .bottom, spacing: RatioSpace.xs) {
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
        VStack(spacing: RatioSpace.xs) {
            if place == 1 {
                Image(systemName: "laurel.leading").font(.title3).foregroundStyle(Color.ratioInk2).accessibilityHidden(true)
            }
            ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: place == 1 ? 72 : 56)
            VStack(spacing: RatioSpace.xxs) {
                Text(entry.name).ratioFont(.h3).multilineTextAlignment(.center)
                Text(university(entry)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center)
                Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins")").ratioFont(.monoData)
            }
            // A plinth: a paper cap with the place, hatched below (screens/41-boards.png).
            VStack(spacing: 0) {
                Text("\(place)")
                    .ratioFont(.h1)
                    .italic()
                    .foregroundStyle(place == 1 ? Color.ratioOxblood : Color.ratioInk2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, RatioSpace.xxs)
                Rectangle().fill(Color.ratioRule).frame(height: 1)
                PlinthHatching()
                    .stroke(Color.ratioRule, lineWidth: 1)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
            .frame(height: place == 1 ? 112 : place == 2 ? 80 : 56)
            .background(Color.ratioPaper, in: UnevenRoundedRectangle(topLeadingRadius: RatioRadius.panel, topTrailingRadius: RatioRadius.panel, style: .continuous))
            .overlay { UnevenRoundedRectangle(topLeadingRadius: RatioRadius.panel, topTrailingRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(place == 1 ? "First" : place == 2 ? "Second" : "Third"): \(entry.name), \(entry.wins) wins")
    }
}

/// Fine diagonal hatching for the podium plinths.
private struct PlinthHatching: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 8
        }
        return path
    }
}

private func university(_ entry: BoardEntry) -> String {
    UniversityDirectory.shortName(id: entry.universityId) ?? entry.universityName ?? ""
}

private struct BoardRow: View {
    let entry: BoardEntry
    let rank: Int
    let isMine: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Two lines: who, then the numbers.
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                        Text("\(rank)").ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                        Text(entry.name).ratioFont(.h3)
                    }
                    Text([university(entry), "\(entry.wins) \(entry.wins == 1 ? "win" : "wins")", entry.rating.formatted()].filter { !$0.isEmpty }.joined(separator: " · "))
                        .ratioFont(.monoData)
                        .foregroundStyle(Color.ratioInk2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: RatioSpace.s) {
                    Text("\(rank)").ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(width: 32, alignment: .leading)
                    ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: 40)
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text(entry.name).ratioFont(.h3)
                        Text(university(entry)).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    }
                    Spacer(minLength: RatioSpace.xs)
                    Text("\(entry.wins)").ratioFont(.monoData).frame(width: 48, alignment: .trailing)
                    Text(entry.rating.formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2).frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, RatioSpace.s)
        .padding(.horizontal, isMine ? RatioSpace.xs : 0)
        .background(isMine ? Color.ratioSunk : Color.clear, in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank). \(entry.name)\(isMine ? ", you" : ""), \(university(entry)), \(entry.wins) wins, rating \(entry.rating)")
    }
}

/// The student's own row, always visible (PRD: "pinned, even when they're outside the top 100").
private struct PinnedRow: View {
    let entry: BoardEntry
    let rank: Int?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: RatioSpace.xxs)) : AnyLayout(HStackLayout(spacing: RatioSpace.s))
        layout {
            HStack(spacing: RatioSpace.s) {
                Text(rank.map { "\($0)" } ?? "–").ratioFont(.monoData).foregroundStyle(Color.ratioOxblood).frame(minWidth: 24, alignment: .leading)
                if !large {
                    ProfilePhoto(uid: entry.uid, initial: entry.initial, version: entry.avatarVersion, size: 36)
                }
                Text(entry.name).ratioFont(.h3)
            }
            if !large { Spacer(minLength: RatioSpace.xs) }
            HStack(spacing: RatioSpace.s) {
                Text("\(entry.wins) \(entry.wins == 1 ? "win" : "wins")").ratioFont(.monoData)
                Text(entry.rating.formatted()).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(.horizontal, RatioSpace.m)
        .padding(.vertical, RatioSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ratioGlass(in: RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: RatioRadius.card, style: .continuous).strokeBorder(Color.ratioRule) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You: \(rank.map { "rank \($0)" } ?? "not ranked yet"), \(entry.wins) wins, rating \(entry.rating)")
    }
}
