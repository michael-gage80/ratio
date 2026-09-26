import FirebaseFirestore
import SwiftUI

/// Continue learning on Today: the most recent thing the student opened and hasn't
/// finished — a lesson (back to the part they were on), a library entry, or an unfinished
/// duel — within the last 14 days. Hidden when there's nothing, or after its ×.
struct ContinueLearningCard: View {
    @Environment(StudentStore.self) private var student
    @Environment(ContentStore.self) private var content
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.ratioWidth) private var width

    var body: some View {
        if let target = student.continueTarget(content: content) {
            HStack(alignment: .top, spacing: RatioSpace.s) {
                Button { open(target) } label: {
                    HStack(alignment: .center, spacing: RatioSpace.s) {
                        if !width.isCompact, let module = target.module {
                            ModuleIllustration(module: module)
                                .frame(width: 56, height: 56)
                                .foregroundStyle(Color.ratioInk)
                        }
                        VStack(alignment: .leading, spacing: RatioSpace.xs) {
                            Text(target.eyebrow).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                            Group {
                                if target.isCase { CaseName.text(target.title) } else { Text(target.title) }
                            }
                            .ratioFont(.h3)
                            .multilineTextAlignment(.leading)
                            if let progress = target.progress {
                                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.ratioRule)
                                            Capsule().fill(Color.ratioInk).frame(width: proxy.size.width * progress.fraction)
                                        }
                                    }
                                    .frame(height: 3)
                                    Text(progress.label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                                }
                            }
                        }
                        Spacer(minLength: RatioSpace.xs)
                        Image(systemName: target.locked ? "lock" : "arrow.right").foregroundStyle(Color.ratioInk2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
                .accessibilityHint(target.locked ? "Part of Ratio Plus" : "Continues where you left off")

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(Color.ratioInk2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.ratioPress)
                .padding(.top, -RatioSpace.s)
                .padding(.trailing, -RatioSpace.s)
                .accessibilityLabel("Hide until you open something new")
            }
            .ratioCard()
        }
    }

    private func open(_ target: ContinueTarget) {
        if target.locked, let module = target.module {
            navigator.showPaywall(for: module, freeModule: student.freeModule)
            return
        }
        switch target.item.kind {
        case .lesson:
            if let part = target.item.part {
                navigator.resumeLecture = (target.item.id, part)
                navigator.pathwayPath = [.overview(target.item.id), .lecture(target.item.id)]
            } else {
                navigator.pathwayPath = [.overview(target.item.id)]
            }
            navigator.tab = .pathway
        case .library:
            navigator.pathwayPath = [.library, .libraryEntry(target.item.id)]
            navigator.tab = .pathway
        case .challenge:
            navigator.openChallengeId = target.item.id
            navigator.tab = .duel
        case .lobby:
            navigator.lobbyCode = target.item.id
            navigator.tab = .duel
        }
    }

    private func dismiss() {
        Task { try? await UserRepository().update(uid: student.uid, ["recentDismissedAt": FieldValue.serverTimestamp()]) }
    }
}

/// What Continue learning offers, ready to show.
struct ContinueTarget {
    let item: RecentItem
    let eyebrow: String
    let title: String
    var module: Module?
    var progress: (fraction: Double, label: String)?
    var locked = false
    var isCase = false
}

extension StudentStore {
    /// The newest recent item that's still unfinished, opened in the last 14 days since
    /// the card was last dismissed, and not today's brief lesson (the brief covers that).
    func continueTarget(content: ContentStore, now: Date = .now) -> ContinueTarget? {
        let cutoff = max(now.addingTimeInterval(-14 * 86_400), profile.recentDismissedAt ?? .distantPast)
        for item in profile.recent ?? [] where item.at > cutoff {
            if let target = target(for: item, content: content, now: now) { return target }
        }
        return nil
    }

    private func target(for item: RecentItem, content: ContentStore, now: Date) -> ContinueTarget? {
        switch item.kind {
        case .lesson:
            guard let lesson = content.lesson(id: item.id), lesson.id != brief?.lessonId,
                  !attempts.contains(where: { $0.lessonId == lesson.id }) else { return nil }
            let done = partsCompleted[lesson.id] ?? 0
            let parts = lesson.parts.count
            return ContinueTarget(
                item: item,
                eyebrow: "Continue · \(item.part == nil ? "Lesson" : "Lecture") · \(lesson.moduleId.title)",
                title: lesson.title,
                module: lesson.moduleId,
                progress: done > 0 ? (Double(done) / Double(parts), done >= parts ? "Tests next" : "Part \(min(done + 1, parts)) of \(parts)") : nil,
                locked: !canStudy(lesson.moduleId)
            )
        case .library:
            guard let entry = content.library().first(where: { $0.id == item.id }) else { return nil }
            return ContinueTarget(item: item, eyebrow: "Continue · \(entry.kind.singular) · \(entry.module.title)", title: entry.title,
                                  module: entry.module, locked: !canStudy(entry.module), isCase: entry.kind == .cases)
        case .challenge:
            guard let challenge = challenges.first(where: { $0.id == item.id }), challenge.done[uid] != true else { return nil }
            let opponent = challenge.opponent(of: uid).name
            return ContinueTarget(item: item, eyebrow: "Continue · Challenge · \(DuelScope.title(of: challenge.moduleId))",
                                  title: "Your half v \(opponent)")
        case .lobby:
            // Lobbies expire after 15 minutes.
            guard now.timeIntervalSince(item.at) < 15 * 60 else { return nil }
            return ContinueTarget(item: item, eyebrow: "Continue · Friend lobby", title: "Lobby \(item.id)")
        }
    }
}

private extension LibraryEntry.Kind {
    var singular: String {
        switch self {
        case .cases: "Case"
        case .legislation: "Legislation"
        case .maps: "Doctrine map"
        }
    }
}
