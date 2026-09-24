import SwiftUI

/// screens/23-debrief.png — secure or revisit for each item, what moved in the
/// profile (with the band narrowing), and when each item comes back for review
/// (PRD: lesson stage 4, "Debrief").
struct DebriefView: View {
    let lesson: Lesson
    let model: TestModel
    let result: TestModel.Result
    let onFinish: () -> Void

    @State private var reviewingMisses = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var misses: [Item] { model.items.filter { !result.correct($0.id) } }
    private var secureCount: Int { model.items.count - misses.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                HStack {
                    // Nudged so the glyph, not its 44pt target, sits on the margin.
                    RatioIconButton(systemImage: "xmark", label: "Close", action: onFinish)
                        .padding(.leading, -12)
                    Spacer()
                    Text("Judgment entered").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                header
                itemResults
                profileChanges
                reviewSchedule
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    Text("Profile").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    let archetype = Archetype(result.headline)
                    Text("\(Text("The \(archetype.name)").italic()) — \(archetype.summary)").ratioFont(.body)
                }
                .ratioCard(.ratioSunk, bordered: false)
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.top, RatioSpace.s)
            .padding(.bottom, RatioSpace.m)
        }
        .safeAreaInset(edge: .bottom) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RatioSpace.xs) { finishButtons }
                VStack(spacing: RatioSpace.xs) { finishButtons }
            }
            .padding(.horizontal, RatioSpace.m)
            .padding(.vertical, RatioSpace.s)
            .background(Color.ratioParchment)
        }
        .ratioPage()
        .sheet(isPresented: $reviewingMisses) { missesSheet }
    }

    @ViewBuilder private var finishButtons: some View {
        if !misses.isEmpty {
            RatioButton(misses.count == 1 ? "Review my miss" : "Review my misses", style: .tertiary) { reviewingMisses = true }
        }
        RatioButton("Back to Today", style: .secondary, action: onFinish)
    }

    private var header: some View {
        let ring = SecureRing(fraction: model.items.isEmpty ? 0 : Double(secureCount) / Double(model.items.count))
        let text = VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Lesson complete · \(lesson.moduleId.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("Secure on\n\(Text("\(secureCount) of \(model.items.count).").italic().foregroundStyle(Color.ratioOxblood))")
                .ratioFont(.h1)
            Text(misses.isEmpty ? "Every item is holding." : "\(misses.count == 1 ? "One line" : "\(misses.count) lines") to revisit; the rest is holding.")
                .ratioFont(.body)
        }
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: RatioSpace.s) { text; ring }
            } else {
                HStack(alignment: .top, spacing: RatioSpace.s) {
                    text
                    Spacer(minLength: 0)
                    ring
                }
            }
        }
    }

    private var itemResults: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let correct = result.correct(item.id)
                let number = Text(String(format: "%02d", index + 1)).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                let verdict = Label(correct ? "Secure" : "Revisit", systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(correct ? Color.ratioVerdigris : Color.ratioOxblood)
                    .fixedSize()
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    if typeSize.isAccessibilitySize {
                        number
                        Text(item.prompt).ratioFont(.body)
                        verdict
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                            number
                            Text(item.prompt).ratioFont(.body)
                            Spacer(minLength: RatioSpace.xs)
                            verdict
                        }
                    }
                    if !correct, let why = item.trapExplanation ?? item.feedback(correct: false) {
                        Text(why)
                            .ratioFont(.small)
                            .ratioPanel(.ratioOxWash)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.ratioOxblood).frame(width: 3) }
                            .clipShape(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                    }
                }
                .padding(.vertical, RatioSpace.s)
                .accessibilityElement(children: .combine)
                if index < model.items.count - 1 { Divider().overlay(Color.ratioRule) }
            }
        }
        .padding(.horizontal, RatioSpace.m)
        .ratioCard(padding: 0)
    }

    /// The skills this attempt moved, for this lesson's topic, with the band before and after.
    private var profileChanges: some View {
        let changed = Skill.allCases.compactMap { skill -> (Skill, Estimate, Estimate)? in
            guard let after = result.topicAfter[skill.rawValue] else { return nil }
            return (skill, result.topicBefore[skill.rawValue] ?? .prior, after)
        }
        return VStack(alignment: .leading, spacing: RatioSpace.m) {
            Text("What changed in your profile").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(changed, id: \.0) { skill, before, after in
                BandChange(skill: skill, before: before, after: after)
            }
        }
        .ratioCard()
    }

    private var reviewSchedule: some View {
        let dated = model.items.compactMap { item in result.dueDate(item.id).map { (item, $0) } }.sorted { $0.1 < $1.1 }
        return VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Reviews scheduled").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            Text("They'll come back in your daily brief, spaced so they stick.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
            ForEach(dated, id: \.0.id) { item, due in
                let date = Text(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .ratioFont(.monoData)
                    .foregroundStyle(Color.ratioInk2)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                        Text(item.prompt).ratioFont(.small)
                        Spacer(minLength: RatioSpace.xs)
                        date.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        Text(item.prompt).ratioFont(.small)
                        date
                    }
                }
                .padding(.vertical, RatioSpace.xs)
                .accessibilityElement(children: .combine)
                Divider().overlay(Color.ratioRule)
            }
        }
        .ratioCard()
    }

    /// Each missed item again, with the student's answer and the correct one revealed.
    private var missesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RatioSpace.l) {
                    ForEach(misses) { item in
                        ItemInteractionView(item: item, lockedResponse: model.responses.first { $0.itemId == item.id },
                                            context: InteractionContext(lessonId: lesson.id)) { _ in }
                        Divider().overlay(Color.ratioRule)
                    }
                }
                .padding(RatioSpace.m)
            }
            .ratioPage()
            .navigationTitle(misses.count == 1 ? "Your miss" : "Your misses")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { reviewingMisses = false } }
            }
        }
    }
}

/// The percentage-secure ring in the debrief header.
private struct SecureRing: View {
    let fraction: Double
    /// Grows with Dynamic Type so the percentage always fits inside.
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 104

    var body: some View {
        ZStack {
            Circle().stroke(Color.ratioRule, lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.ratioVerdigris, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((fraction * 100).rounded()))%").ratioFont(.h2)
                Text("Secure").ratioFont(.monoLabel).foregroundStyle(Color.ratioVerdigris)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent secure")
    }
}

/// A skill's score moving on the 0–100 track, with the old band dashed and the new one
/// shaded — so a narrowing band reads as "firmer" as well as higher or lower.
struct BandChange: View {
    let skill: Skill
    let before: Estimate
    let after: Estimate

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(skill.title).ratioFont(.h3)
                Spacer(minLength: RatioSpace.xs)
                Text("\(before.displayScore) → \(after.displayScore)").ratioFont(.h3)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = { (score: Int) in width * CGFloat(score) / 100 }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ratioSunk).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.ratioInk2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: max(4, x(2 * before.band)), height: 16)
                        .offset(x: x(max(0, before.displayScore - before.band)))
                    Capsule()
                        .fill(Color.ratioOxblood.opacity(0.22))
                        .frame(width: max(4, x(2 * after.band)), height: 10)
                        .offset(x: x(max(0, after.displayScore - after.band)))
                    Circle().fill(Color.ratioInk).frame(width: 14, height: 14).offset(x: x(after.displayScore) - 7)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            Text(caption).ratioFont(.small).foregroundStyle(Color.ratioInk2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skill.title): \(before.displayScore) plus or minus \(before.band) to \(after.displayScore) plus or minus \(after.band). \(caption)")
    }

    private var caption: String {
        let firmer = after.band < before.band ? "Band narrowed \(before.band) → \(after.band): the estimate is firmer" : "Band \(after.band)"
        switch after.displayScore - before.displayScore {
        case 1...: return "\(firmer) as well as higher."
        case ..<0: return "\(firmer). A dip is normal — it's what reviews are for."
        default: return "\(firmer)."
        }
    }
}
