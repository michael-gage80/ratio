import Charts
import PhotosUI
import SwiftUI

/// screens/27-me.png — the student's profile with honest bands, retention, and a way
/// into each module's topics (PRD: "Me tab"). Duel ratings join when duels do.
struct MeView: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var showsSettings = false

    private var profile: UserProfile { student.profile }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                identity
                ProfileCard(headline: student.headline, updatedAt: profile.headlineUpdatedAt)
                RetentionCard(retention: student.retention)
                modules
                duels
            }
            .padding(24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsSheet() }
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

    // MARK: Identity

    private var identity: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ProfilePhoto(uid: student.uid, initial: profile.displayName ?? "?", version: profile.avatarVersion, size: 112)
                    .overlay {
                        if uploading {
                            Circle().fill(.black.opacity(0.4))
                            ProgressView().tint(.white)
                        }
                    }
                PhotosPicker(selection: $photo, matching: .images) {
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.ratioPaper, in: Circle())
                        .overlay(Circle().strokeBorder(Color.ratioRule))
                        .foregroundStyle(Color.ratioInk)
                }
                .disabled(uploading)
                .accessibilityLabel("Change photo")
            }
            Text(name).ratioFont(.h1)
            Text(details).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if uploading {
                Text("Checking your photo…").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var name: String {
        [profile.displayName, profile.initial.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    /// "UCL · LLB · Year 2"
    private var details: String {
        let university = profile.universityId.flatMap { id in UniversityDirectory.all.first { $0.id == id } }
            .map { $0.aliases?.first ?? $0.name } ?? profile.universityOther
        return [university, "LLB", profile.year.map { "Year \($0)" }].compactMap { $0 }.joined(separator: " · ")
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
    private var duels: some View {
        let rated = Module.allCases.compactMap { module in student.ratings[module].map { (module, $0) } }
        let finished = student.matches.filter { $0.status == "complete" && $0.result(for: student.uid) != nil }
        if !rated.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Duel ratings").ratioFont(.h2).padding(.bottom, 12)
                HStack {
                    Text("Module")
                    Spacer()
                    Text("Rating").frame(width: 70, alignment: .trailing)
                    Text("Duels").frame(width: 56, alignment: .trailing)
                    Text("Won").frame(width: 44, alignment: .trailing)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .padding(.bottom, 8)
                ForEach(rated, id: \.0) { module, rating in
                    Divider().overlay(Color.ratioRule)
                    HStack {
                        Text(module.title).ratioFont(.h3)
                        Spacer()
                        Text(Int(rating.rating.rounded()).formatted()).frame(width: 70, alignment: .trailing)
                        Text("\(rating.duels)").frame(width: 56, alignment: .trailing)
                        Text("\(rating.wins)").frame(width: 44, alignment: .trailing)
                    }
                    .ratioFont(.monoData)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
                if !finished.isEmpty {
                    Text("Recent duels").ratioFont(.h2).padding(.top, 24).padding(.bottom, 4)
                    ForEach(finished) { match in
                        Divider().overlay(Color.ratioRule)
                        MatchRow(match: match, uid: student.uid)
                    }
                }
            }
        }
    }

    // MARK: Modules

    private var modules: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modules").ratioFont(.h2).padding(.bottom, 12)
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            ForEach(profile.modules ?? Module.allCases) { module in
                let mastery = student.mastery(of: content.lessons(in: module))
                NavigationLink(value: Route.module(module)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(module.title).ratioFont(.h3)
                            Spacer()
                            Text(mastery.map { "\($0)%" } ?? "In preparation")
                                .ratioFont(mastery == nil ? .monoLabel : .monoData)
                                .foregroundStyle(Color.ratioInk2)
                            Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(Color.ratioInk2)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ratioRule)
                                Capsule().fill(Color.ratioInk).frame(width: proxy.size.width * Double(mastery ?? 0) / 100)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(module.title), \(mastery.map { "\($0)% of lessons secure" } ?? "in preparation")")
                Divider().overlay(Color.ratioRule)
            }
            Text("Mastery is the share of a module's lessons that are secure.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
                .padding(.top, 12)
        }
    }
}

/// The archetype, the three-axis chart and each score with its band.
private struct ProfileCard: View {
    let headline: Headline
    let updatedAt: Date?

    var body: some View {
        let archetype = Archetype(headline)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Current profile · Hypothesis").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Spacer()
                RatioTag("Hypothesis", style: .tint(.ratioOxblood))
            }
            Text("The \(Text(archetype.name + ".").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.h1)
            Text("\(archetype.summary)\(updated)").ratioFont(.body)
            ProfileTriangle(headline: headline, highlight: Archetype.growthEdge(headline))
                .padding(.horizontal, 8)
            Divider().overlay(Color.ratioRule)
            ForEach(Skill.allCases) { skill in
                SkillRow(title: skill.title, estimate: headline[skill])
            }
            Text("The shaded band is our uncertainty. It narrows as you answer more.")
                .ratioFont(.small)
                .italic()
                .foregroundStyle(Color.ratioInk2)
        }
        .padding(20)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
    }

    private var updated: String {
        updatedAt.map { " Updated \($0.formatted(.relative(presentation: .named)))." } ?? ""
    }
}

/// Delayed retention (PRD north star), with its trend once there's enough of it.
private struct RetentionCard: View {
    let retention: Retention?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Retention").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            if let retention {
                HStack(alignment: .center, spacing: 16) {
                    Text("\(Text("\(retention.percent)%").font(.custom("NewsreaderDisplay-Regular", size: 34, relativeTo: .largeTitle))) remembered at 7+ days")
                        .ratioFont(.h3)
                    Spacer(minLength: 0)
                    if retention.points.count > 1 {
                        Chart(retention.points) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Retention", point.percent))
                                .foregroundStyle(Color.ratioInk)
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(width: 90, height: 36)
                        .accessibilityHidden(true)
                    }
                }
                if let change = retention.change {
                    Text("\(change >= 0 ? "↑" : "↓") \(abs(change)) pts in 4 weeks")
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
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.ratioRule) }
    }
}

/// Until the full Settings screen (Phase 15): the account, logging out, and debug tools.
private struct SettingsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dismiss) private var dismiss
    @AppStorage("tour.today.seen") private var tourSeen = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Full settings arrive in a later build.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                    Button("Replay the Today tour") {
                        tourSeen = false
                        navigator.backToToday()
                        dismiss()
                    }
                    Button("Replay the duel tutorial") {
                        navigator.tab = .duel
                        navigator.showsDuelTutorial = true
                        dismiss()
                    }
                    Button("Log out", role: .destructive) { session.signOut() }
                }
                #if DEBUG
                Section("Debug") {
                    RatioGlassDebugToggle()
                    NavigationLink("Interaction gallery") { InteractionGalleryView() }
                    NavigationLink("Design system catalog") { DesignSystemCatalogView() }
                }
                #endif
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
