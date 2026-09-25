import SwiftUI

/// Renders one lecture component — screens/00-design-system/02-components.png, cells
/// 05–11 (PRD: "Content components").
struct LessonComponentView: View {
    let component: LessonComponent
    let moduleTitle: String

    var body: some View {
        switch component {
        case .caseCard(let card):
            CaseCardView(card: card, moduleTitle: moduleTitle)
        case .statute(let citation, let text, let elements):
            StatuteBlockView(citation: citation, text: text, elements: elements)
        case .keyConcept(let term, let definition):
            KeyConceptView(term: term, definition: definition)
        case .ratioPanel(let label, let points):
            RatioPanelView(label: label, points: points)
        case .trap(let wrong, let why):
            RatioTrapCard(commonWrongAnswer: wrong, whyItsWrong: why)
        case .doctrineMap(let map):
            DoctrineMapView(map: map)
        case .timeline(let title, let events):
            LessonTimelineView(title: title, events: events)
        }
    }
}

/// Case names are always italic in the accent colour (PRD: "Case card"); the "v"
/// between the parties stays upright.
enum CaseName {
    static func text(_ name: String) -> Text {
        let parties = name.components(separatedBy: " v ")
        guard parties.count == 2 else { return Text(name).italic().foregroundStyle(Color.ratioOxblood) }
        return Text("\(Text(parties[0]).italic().foregroundStyle(Color.ratioOxblood)) v \(Text(parties[1]).italic().foregroundStyle(Color.ratioOxblood))")
    }
}

// MARK: - Case card (cell 05)

struct CaseCardView: View {
    let card: LessonComponent.CaseCard
    let moduleTitle: String

    @State private var isExpanded = false
    @State private var showsReport = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let citation = Text("\(card.citation) · \(courtAbbreviation)")
            .ratioFont(.monoData)
            .foregroundStyle(Color.ratioInk2)
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    RatioTag("Case")
                    Spacer(minLength: RatioSpace.xs)
                    citation
                }
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    RatioTag("Case")
                    citation
                }
            }
            CaseName.text(card.caseName).ratioFont(.h2)
            Text("\(card.court) · \(String(card.year))")
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
            Text(card.factsShort).ratioFont(.body)
            VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                Text("Ratio").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                Text(card.ratioShort).ratioFont(.body)
            }
            .ratioPanel()

            if let expanded = card.expanded {
                if isExpanded {
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Text(expanded.facts).ratioFont(.body)
                        Text("Significance").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        Text(expanded.significance).ratioFont(.body)
                        RatioButton("Read the full report", style: .link) { showsReport = true }
                    }
                    .transition(.opacity)
                }
                Button {
                    withAnimation(reduceMotion ? nil : RatioMotion.reveal) { isExpanded.toggle() }
                } label: {
                    Label(isExpanded ? "Show less" : "Show more", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                        .ratioFont(.monoLabel)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.ratioPress)
            }
        }
        .ratioCard()
        .sheet(isPresented: $showsReport) {
            LawReportSheet(card: card, moduleTitle: moduleTitle)
                // iPad: a centred reading sheet over the lecture (screens/iPad/3-lesson/04).
                .presentationSizing(.page)
                .ratioMeasuresWidth()
        }
    }

    private var courtAbbreviation: String {
        switch card.court {
        case "House of Lords": "HL"
        case "Supreme Court": "UKSC"
        case "Court of Appeal": "CA"
        case "Privy Council": "PC"
        default: card.court
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RatioSpace.xs) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - Statute block (cell 06)

struct StatuteBlockView: View {
    let citation: String
    let text: String
    let elements: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(citation)
                .ratioFont(.h3)
                .italic()
                .foregroundStyle(Color.ratioOnInk)
                .padding(RatioSpace.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ratioInk)
                .environment(\.colorScheme, .light)
            VStack(alignment: .leading, spacing: RatioSpace.s) {
                Text(text).ratioFont(.body)
                ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                    HStack(alignment: .firstTextBaseline, spacing: RatioSpace.xs) {
                        Text("(\(index + 1))").ratioFont(.monoData).foregroundStyle(Color.ratioOxblood)
                        Text(element).ratioFont(.body)
                    }
                }
                Text("Open Government Licence · legislation.gov.uk")
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
            }
            .padding(RatioSpace.s)
        }
        .background(Color.ratioPaper)
        .clipShape(RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(Color.ratioRule, lineWidth: 1) }
    }
}

// MARK: - Key concept (cell 07)

struct KeyConceptView: View {
    let term: String
    let definition: String

    @Environment(\.ratioDyslexiaFriendly) private var dyslexiaFriendly

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.xs) {
            Text("Key concept · \(term)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            // The oxblood initial stands in for a drop cap.
            Text("\(Text(String(definition.prefix(1))).font(RatioTypography.font(for: .h1, dyslexiaFriendly: dyslexiaFriendly)).foregroundStyle(Color.ratioOxblood))\(Text(String(definition.dropFirst())))")
                .ratioFont(.body)
        }
        .padding(.vertical, RatioSpace.xxs)
    }
}

// MARK: - Ratio panel (cell 08)

struct RatioPanelView: View {
    let label: String
    let points: [String]

    private static let numerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii"]

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                    Text(Self.numerals.indices.contains(index) ? Self.numerals[index] + "." : "\(index + 1).")
                        .ratioFont(.bodyEmphasis)
                        .foregroundStyle(Color.ratioOxblood)
                        .frame(minWidth: 32, alignment: .leading)
                    Text(point).ratioFont(.body)
                }
            }
        }
        .ratioPanel(padding: RatioSpace.m)
    }
}

// MARK: - Doctrine map (cell 10)

/// A decision flowchart drawn as a tree from its first node: each step, then its
/// branches, labelled. VoiceOver reads the content's own text alternative, which
/// describes the logic rather than the shapes (PRD: Accessibility, "Diagrams").
struct DoctrineMapView: View {
    let map: LessonComponent.DoctrineMap

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Doctrine map · \(map.title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            // Usually one root; a map of separate propositions has no edges, so every node is one.
            let targets = Set(map.edges.map(\.to))
            let roots = map.nodes.filter { !targets.contains($0.id) }
            ForEach(roots.isEmpty ? Array(map.nodes.prefix(1)) : roots, id: \.id) { root in
                branch(from: root.id, visited: [])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(map.textAlternative)
    }

    private func branch(from nodeId: String, visited: Set<String>) -> AnyView {
        let node = map.nodes.first { $0.id == nodeId }
        let children = map.edges.filter { $0.from == nodeId && !visited.contains($0.to) }
        let isOutcome = children.isEmpty
        return AnyView(
            VStack(alignment: .leading, spacing: RatioSpace.xs) {
                Text(node?.label ?? nodeId)
                    .ratioFont(.small)
                    .foregroundStyle(isOutcome ? Color.ratioInk : Color.ratioOnInk)
                    .padding(RatioSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOutcome ? Color.ratioOxWash : Color.ratioInk,
                                in: RoundedRectangle(cornerRadius: RatioRadius.chip, style: .continuous))
                    // Steps are always ink boxes with paper text, even in dark mode.
                    .environment(\.colorScheme, isOutcome ? colorScheme : .light)
                ForEach(children, id: \.to) { edge in
                    VStack(alignment: .leading, spacing: RatioSpace.xs) {
                        Text(edge.label.map { "\($0) ↓" } ?? "↓").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                        branch(from: edge.to, visited: visited.union([nodeId]))
                    }
                    .padding(.leading, RatioSpace.s)
                    .overlay(alignment: .leading) { Rectangle().fill(Color.ratioRule).frame(width: 1) }
                }
            }
        )
    }
}

// MARK: - Timeline (cell 11)

struct LessonTimelineView: View {
    let title: String
    let events: [LessonComponent.TimelineEvent]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("Timeline · \(title)").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
            ForEach(events, id: \.self) { event in
                if typeSize.isAccessibilitySize {
                    // Large text: the date sits above the event instead of in a column.
                    VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                        date(event)
                        details(event)
                    }
                } else {
                    HStack(alignment: .top, spacing: RatioSpace.s) {
                        date(event).frame(width: 80, alignment: .leading)
                        Circle().fill(Color.ratioInk).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
                        details(event)
                    }
                }
            }
        }
    }

    private func date(_ event: LessonComponent.TimelineEvent) -> some View {
        Text(event.date ?? event.label)
            .ratioFont(.monoData)
            .foregroundStyle(Color.ratioInk2)
    }

    private func details(_ event: LessonComponent.TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: RatioSpace.xxs) {
            if event.date != nil {
                Text(event.label).ratioFont(.body).italic().foregroundStyle(Color.ratioOxblood)
            }
            if let description = event.description {
                Text(description).ratioFont(.small)
            }
        }
    }
}
