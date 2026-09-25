import Charts
import PhotosUI
import SwiftUI

/// screens/27-me.png — "Dossier + story": four numbers, the archetype (its K/U/A bands
/// behind an arrow), retention, twelve weeks of activity, dated milestones, then the
/// modules the student has started and their duels (PRD: "Me tab"). On iPad
/// (screens/iPad/4-pathway-me-settings/04-me.png) the identity runs across the top and
/// the dossier sits in two columns.
struct MeView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ratioWidth) private var width
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var choosingYear = false

    private var profile: UserProfile { student.profile }

    var body: some View {
        ScrollView {
            if width.isCompact {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    identity
                    StatTiles()
                    ProfileCard(headline: student.headline, updatedAt: profile.headlineUpdatedAt)
                    RetentionCard(retention: student.retention)
                    ActivityHeatmap(activeDays: student.activeDays)
                    MilestoneTimeline()
                    modules
                    ratings
                    recentDuels
                }
                .padding(.horizontal, RatioSpace.m)
                .padding(.vertical, RatioSpace.s)
            } else {
                wideDossier
            }
        }
        .ratioPage()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigator.mePath.append(.settings) } label: {
                    Image(systemName: "gearshape").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $choosingYear) {
            if student.programme == .sqe1 {
                SittingSheet(uid: student.uid, sitting: profile.sqeSitting).presentationDetents([.medium])
            } else {
                YearSheet(uid: student.uid, year: profile.year).presentationDetents([.medium])
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        .alert("Photo not updated", isPresented: Binding(get: { uploadError != nil }, set: { if !$0 { uploadError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadError ?? "")
        }
    }

    // MARK: iPad

    /// Identity across the top; stat tiles and the archetype on the left; scores,
    /// retention, activity and the story on the right; then modules beside duel ratings,
    /// and recent duels.
    private var wideDossier: some View {
        VStack(alignment: .leading, spacing: RatioSpace.l) {
            HStack(alignment: .center, spacing: RatioSpace.m) {
                photo(size: 88)
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text(name).ratioFont(.display)
                    Text(([details] + [modulesLine].compactMap { $0 }).joined(separator: " · "))
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    addStageButton
                    if uploading {
                        Text("Checking your photo…").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                    }
                }
                Spacer(minLength: 0)
            }
            ColumnsLayout(fraction: 0.56, spacing: RatioSpace.m) {
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    StatTiles()
                    ProfileCard(headline: student.headline, updatedAt: profile.headlineUpdatedAt, showsScores: false)
                }
                VStack(alignment: .leading, spacing: RatioSpace.m) {
                    ScoresCard(headline: student.headline)
                    RetentionCard(retention: student.retention)
                    ActivityHeatmap(activeDays: student.activeDays).ratioCard()
                    MilestoneTimeline()
                }
            }
            ColumnsLayout(fraction: 0.5, spacing: RatioSpace.l) {
                modules
                ratings
            }
            recentDuels
        }
        .padding(.horizontal, RatioSpace.l)
        .padding(.vertical, RatioSpace.m)
    }

    /// "Crime, Contract, Tort, Public law"
    private var modulesLine: String? {
        let names = student.modules.map(\.title)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: RatioSpace.xs) {
            photo(size: 112)
                .padding(.bottom, RatioSpace.xs)
            Text(name).ratioFont(.h1).multilineTextAlignment(.center)
            Text(details).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center)
            addStageButton
            if uploading {
                Text("Checking your photo…").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Add your year" (or SQE1 sitting) when it isn't set.
    @ViewBuilder
    private var addStageButton: some View {
        if student.programme == .sqe1 ? profile.sqeSitting == nil : profile.year == nil {
            Button(student.programme == .sqe1 ? "Add your SQE1 sitting" : "Add your year") { choosingYear = true }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioOxblood)
                .frame(minHeight: 44)
        }
    }

    /// The photo with its change badge.
    private func photo(size: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ProfilePhoto(uid: student.uid, initial: profile.displayName ?? "?", version: profile.avatarVersion, size: size)
                .overlay {
                    if uploading {
                        Circle().fill(Color.ratioInk.opacity(0.45))
                        ProgressView().tint(Color.ratioParchment)
                    }
                }
            PhotosPicker(selection: $photo, matching: .images) {
                // A 32pt badge inside a 44pt target.
                Image(systemName: "pencil")
                    .font(.footnote)
                    .frame(width: 32, height: 32)
                    .background(Color.ratioPaper, in: Circle())
                    .overlay(Circle().strokeBorder(Color.ratioRule))
                    .foregroundStyle(Color.ratioInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .offset(x: 6, y: 6)
            .disabled(uploading)
            .accessibilityLabel("Change photo")
        }
    }

    private var name: String {
        [profile.displayName, profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    /// "UCL · LLB · Year 2", or "BPP · SQE1 · January 2027 · 18 weeks to go".
    private var details: String {
        let university = UniversityDirectory.shortName(id: profile.universityId) ?? profile.universityOther
        let stage: [String?] = student.programme == .sqe1
            ? [profile.sqeSitting.map { SQESitting.title($0) }, profile.sqeSitting.flatMap { SQESitting.countdown($0) }]
            : [profile.year.map { "Year \($0)" }]
        return ([university, student.programme.title] + stage).compactMap { $0 }.joined(separator: " · ")
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; photo = nil }
        do {
            try await AvatarImages.upload(item, uid: student.uid)
        } catch {
            uploadError = (error as? LocalizedError)?.errorDescription ?? "We couldn't upload your photo. Check your connection and try again."
        }
    }

    // MARK: Duels

    @ViewBuilder
    private var ratings: some View {
        let rated = ([DuelScope.mixed] + Module.allCases.map { .module($0) }).compactMap { scope in student.ratings[scope].map { (scope, $0) } }
        if !rated.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Duel ratings").ratioFont(.h2).padding(.bottom, RatioSpace.s)
                if !typeSize.isAccessibilitySize {
                    HStack(spacing: RatioSpace.xs) {
                        Text("Module")
                        Spacer()
                        Text("Rating").frame(width: 72, alignment: .trailing)
                        Text("Duels").frame(width: 56, alignment: .trailing)
                        Text("Won").frame(width: 48, alignment: .trailing)
                    }
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .padding(.bottom, RatioSpace.xs)
                    .accessibilityHidden(true)
                }
                ForEach(rated, id: \.0) { scope, rating in
                    Divider().overlay(Color.ratioRule)
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                                Text(scope.title).ratioFont(.h3)
                                Text("Rating \(Int(rating.rating.rounded()).formatted()) · \(rating.duels) \(rating.duels == 1 ? "duel" : "duels") · \(rating.wins) won")
                                    .ratioFont(.monoData)
                                    .foregroundStyle(Color.ratioInk2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            HStack(spacing: RatioSpace.xs) {
                                Text(scope.title).ratioFont(.h3)
                                Spacer()
                                Text(Int(rating.rating.rounded()).formatted()).frame(width: 72, alignment: .trailing)
                                Text("\(rating.duels)").frame(width: 56, alignment: .trailing)
                                Text("\(rating.wins)").frame(width: 48, alignment: .trailing)
                            }
                            .ratioFont(.monoData)
                        }
                    }
                    .padding(.vertical, RatioSpace.s)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(scope.title): rating \(Int(rating.rating.rounded())), \(rating.duels) duels, \(rating.wins) won")
                }
            }
        }
    }

    /// Shown with the ratings (only once there are any), as before.
    @ViewBuilder
    private var recentDuels: some View {
        let hasRatings = !student.ratings.isEmpty
        let finished = student.matches.filter { $0.status == "complete" && $0.result(for: student.uid) != nil }
        if hasRatings && !finished.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent duels").ratioFont(.h2).padding(.bottom, RatioSpace.xs)
                ForEach(finished) { match in
                    Divider().overlay(Color.ratioRule)
                    MatchRow(match: match, uid: student.uid)
                }
            }
        }
    }

    // MARK: Modules

    /// Only modules with a lesson begun.
    private var started: [Module] {
        Module.allCases.filter { module in content.lessons(in: module).contains { student.state(of: $0) != .notStarted } }
    }

    private var modules: some View {
        let started = started
        return VStack(alignment: .leading, spacing: 0) {
            Text("Modules").ratioFont(.h2).padding(.bottom, RatioSpace.s)
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            if started.isEmpty {
                Text("Modules appear here once you've started one of their lessons.")
                    .ratioFont(.body)
                    .foregroundStyle(Color.ratioInk2)
                    .padding(.vertical, RatioSpace.s)
            }
            ForEach(started) { module in
                let mastery = student.mastery(of: content.lessons(in: module))
                Button {
                    if student.isPlus { navigator.mePath.append(.module(module)) } else { navigator.paywall = "Topic drill-down and trends are part of Ratio Plus." }
                } label: {
                    VStack(alignment: .leading, spacing: RatioSpace.s) {
                        HStack(spacing: RatioSpace.xs) {
                            Text(module.title).ratioFont(.h3)
                            Spacer()
                            Text(mastery.map { "\($0)%" } ?? "In preparation")
                                .ratioFont(mastery == nil ? .monoLabel : .monoData)
                                .foregroundStyle(Color.ratioInk2)
                            Image(systemName: "arrow.right").foregroundStyle(Color.ratioInk2)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ratioRule)
                                Capsule().fill(Color.ratioInk).frame(width: proxy.size.width * Double(mastery ?? 0) / 100)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.vertical, RatioSpace.s)
                }
                .buttonStyle(.ratioPress)
                .accessibilityLabel("\(module.title), \(mastery.map { "\($0)% of lessons secure" } ?? "in preparation")")
                Divider().overlay(Color.ratioRule)
            }
            Text("Mastery is the share of a module's lessons that are secure.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
                .padding(.top, RatioSpace.s)
        }
    }
}

/// The archetype, the three-axis chart and each score with its band.
private struct ProfileCard: View {
    let headline: Headline
    let updatedAt: Date?
    /// On iPad the scores have their own card beside this one.
    var showsScores = true
    @State private var expanded = false

    var body: some View {
        let archetype = Archetype(headline)
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Current profile").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer()
                RatioTag("Hypothesis", style: .tint(.ratioOxblood))
            }
            Text("The \(Text(archetype.name + ".").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.h1)
            Text("\(archetype.summary)\(updated)").ratioFont(.body)
            ProfileTriangle(headline: headline, highlight: Archetype.growthEdge(headline))
                .padding(.horizontal, RatioSpace.xs)
            if showsScores {
                Divider().overlay(Color.ratioRule)
                Button {
                    withAnimation(RatioMotion.tap) { expanded.toggle() }
                } label: {
                    HStack(spacing: RatioSpace.xs) {
                        Text("Knowledge, understanding, application").ratioFont(.h3).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.ratioPress)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                if expanded {
                    ForEach(Skill.allCases) { skill in
                        SkillRow(title: skill.title, estimate: headline[skill])
                    }
                    Text("The shaded band is our uncertainty. It narrows as you answer more.")
                        .ratioFont(.small)
                        .italic()
                        .foregroundStyle(Color.ratioInk2)
                }
            }
        }
        .ratioCard()
    }

    private var updated: String {
        updatedAt.map { " Updated \($0.formatted(.relative(presentation: .named)))." } ?? ""
    }
}

/// iPad: each score with its band, beside the archetype ("Scores · with uncertainty").
private struct ScoresCard: View {
    let headline: Headline

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Scores · with uncertainty").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(Skill.allCases) { skill in
                SkillRow(title: skill.title, estimate: headline[skill])
            }
            Text("The shaded band is our uncertainty. It narrows as you answer more.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
        }
        .ratioCard()
    }
}

/// Delayed retention (PRD north star), with its trend once there's enough of it.
private struct RetentionCard: View {
    let retention: Retention?

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Retention").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if let retention {
                HStack(alignment: .center, spacing: RatioSpace.s) {
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text("\(retention.percent)%").ratioFont(.figure)
                        Text("remembered a week or more later").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    if retention.points.count > 1 {
                        Chart(retention.points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Retention", point.percent))
                                .foregroundStyle(Color.ratioInk)
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(width: 88, height: 40)
                        .accessibilityHidden(true)
                    }
                }
                if let change = retention.change {
                    Text("\(change >= 0 ? "↑" : "↓") \(abs(change)) points in 4 weeks")
                        .ratioFont(.monoData)
                        .foregroundStyle(change >= 0 ? Color.ratioVerdigris : Color.ratioOxblood)
                } else {
                    Text("From \(retention.items) items that came back a week or more later.")
                        .ratioFont(.small)
                        .foregroundStyle(Color.ratioInk2)
                }
            } else {
                Text("How much you still know a week later. It appears once items you've learnt start coming back for review.")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
        }
        .ratioCard()
    }
}
