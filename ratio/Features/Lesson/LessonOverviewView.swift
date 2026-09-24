import SwiftUI

/// screens/17-lesson-overview.png — the title page (PRD: lesson stage 1, "Overview").
struct LessonOverviewView: View {
    let lesson: Lesson
    let headline: Headline?
    let onBegin: () -> Void

    private static let numerals = ["i.", "ii.", "iii.", "iv.", "v."]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ModuleIllustration(module: lesson.moduleId)
                    .foregroundStyle(Color.ratioInk)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.ratioRule) }

                VStack(alignment: .leading, spacing: 12) {
                    Text("\(lesson.moduleId.title) · Lesson \(lesson.lessonNumber)")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    Text(lesson.title).ratioFont(.h1)
                    Text(lesson.subtitle).ratioFont(.h3).foregroundStyle(Color.ratioInk2)
                    Text("Lecture · \(lesson.parts.count) parts · \(lesson.estimatedMinutes) min / Tests · \(lesson.itemCounts.testServedPerAttempt) items / Law stated as at \(lesson.lawStatedDate)")
                        .ratioFont(.monoLabel)
                        .foregroundStyle(Color.ratioInk2)
                    if !lesson.isReviewed {
                        RatioTag("Draft · not yet reviewed", icon: "exclamationmark.triangle", style: .tint(.ratioOxblood))
                    }
                }

                Text(lesson.overview.hook).ratioFont(.body)

                section("Objectives") {
                    ForEach(Array(lesson.objectives.enumerated()), id: \.offset) { index, objective in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(Self.numerals.indices.contains(index) ? Self.numerals[index] : "\(index + 1).")
                                .ratioFont(.bodyEmphasis)
                                .foregroundStyle(Color.ratioOxblood)
                                .frame(width: 28, alignment: .leading)
                            Text(objective).ratioFont(.body)
                        }
                    }
                }

                section("Table of cases") {
                    ForEach(lesson.leadingAuthorities, id: \.self) { authority in
                        AuthorityRow(authority: authority)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why this matters to you").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text(lesson.whyThisMatters(for: headline)).ratioFont(.body)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(lesson.overview.lawStatedNotice ?? "Law stated as at \(lesson.lawStatedDate).")
                    .ratioFont(.small)
                    .foregroundStyle(Color.ratioInk2)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                RatioButton("Begin", action: onBegin)
                Text("Educational, not legal advice").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            }
            .padding(24)
            .background(Color.ratioParchment)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .toolbarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            Text(title).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            content()
        }
    }
}

/// A leading authority: case name in italic oxblood, year on the right, its one-line
/// role, then the citation in mono. Statutes (no bracketed report) show as-is.
private struct AuthorityRow: View {
    let authority: Lesson.Authority

    var body: some View {
        let parsed = Self.parse(authority.citation)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                if parsed.report == nil {
                    Text(parsed.name).ratioFont(.h3)
                } else {
                    CaseName.text(parsed.name).ratioFont(.h3)
                }
                Spacer()
                if let year = parsed.year {
                    Text(year).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
                }
            }
            Text(authority.role).ratioFont(.small).foregroundStyle(Color.ratioInk2)
            if let report = parsed.report {
                Text(report).ratioFont(.monoData).foregroundStyle(Color.ratioInk2)
            }
        }
        .padding(.vertical, 6)
    }

    /// "R v Woollin [1999] 1 AC 82" → name "R v Woollin", report "[1999] 1 AC 82", year "1999".
    private static func parse(_ citation: String) -> (name: String, report: String?, year: String?) {
        guard let match = citation.firstMatch(of: /^(.+?)\s+([\[(](\d{4})[\])].*)$/) else {
            return (citation, nil, nil)
        }
        return (String(match.1), String(match.2), String(match.3))
    }
}
