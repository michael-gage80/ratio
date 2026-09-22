import SwiftUI

/// Phase 1 verification screen only — exercises every design-system token and
/// component in one place so it can be checked by eye against
/// screens/00-design-system/01-foundations.png and 02-components.png, in light, dark
/// and dyslexia-friendly mode. Debug-only; stripped once the app has real screens
/// (Phase 3 onward) to replace it. See ContentView.swift.
#if DEBUG
struct DesignSystemCatalogView: View {
    @State private var dyslexiaFriendly = false
    @State private var segment = "weekly"
    @State private var examPause = false
    @State private var weeklyTarget = 4
    @State private var firstName = ""
    @State private var selectedOption: Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    colorSection
                    typographySection
                    buttonSection
                    tagSection
                    controlSection
                    optionRowSection
                    feedbackSection
                    spotArtSection
                    glassSection
                    iconSection
                }
                .padding(20)
            }
            .background(Color.ratioParchment)
            .navigationTitle("Design system")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Dyslexia mode", isOn: $dyslexiaFriendly)
                        .labelsHidden()
                }
            }
        }
        .environment(\.ratioDyslexiaFriendly, dyslexiaFriendly)
        .tint(.ratioOxblood)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ratio.").ratioFont(.display).foregroundStyle(Color.ratioInk)
            Text("Phase 1 · design system catalog").ratioFont(.monoLabel).foregroundStyle(.secondary)
        }
    }

    private var colorSection: some View {
        sectionCard("Colour") {
            HStack(spacing: 10) {
                swatch("Ink", .ratioInk)
                swatch("Parchment", .ratioParchment)
                swatch("Paper", .ratioPaper)
                swatch("Oxblood", .ratioOxblood)
                swatch("Verdigris", .ratioVerdigris)
                swatch("Rule", .ratioRule)
            }
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10).fill(color).frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ratioRule))
            Text(name).ratioFont(.caption).foregroundStyle(.secondary)
        }
    }

    private var typographySection: some View {
        sectionCard("Typography") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Good morning, Amara.").ratioFont(.display)
                Text("The intent he never aimed for.").ratioFont(.h1)
                Text("When may a jury find intent?").ratioFont(.h2)
                Text("Find an opponent").ratioFont(.h3)
                Text("A lesson covers one case or concept in 12 to 20 minutes, broken up by checks.").ratioFont(.body)
                HStack(spacing: 0) {
                    Text("The line between ").ratioFont(.body)
                    Text("aim").ratioFont(.bodyEmphasis).foregroundStyle(Color.ratioOxblood)
                    Text(" and ").ratioFont(.body)
                    Text("foresight.").ratioFont(.bodyEmphasis).foregroundStyle(Color.ratioOxblood)
                }
                Text("Updated 4 lessons ago.").ratioFont(.small).foregroundStyle(.secondary)
                Text("One more day keeps the week.").ratioFont(.caption).foregroundStyle(.secondary)
                Text("[1999] 1 AC 82 · HL").ratioFont(.monoLabel).foregroundStyle(.secondary)
                Text("[1999] 1 AC 82 · 1,412 · 8:09").ratioFont(.monoData).foregroundStyle(.secondary)
                Text("Regina v Woollin").ratioFont(.displayAccent).foregroundStyle(Color.ratioOxblood)
            }
        }
    }

    private var buttonSection: some View {
        sectionCard("Buttons") {
            VStack(spacing: 10) {
                RatioButton("Begin — R v Woollin", style: .primary) {}
                RatioButton("Back to chambers", style: .secondary) {}
                RatioButton("Review my one miss", style: .tertiary) {}
                RatioButton("Lock it in · choose an answer", style: .primary, isEnabled: false) {}
                RatioButton("Read the full report", style: .link) {}
            }
        }
    }

    private var tagSection: some View {
        sectionCard("Chips and tags") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    RatioTag("Crime")
                    RatioTag("Contract")
                    RatioTag("Tort", style: .filledDark)
                }
                HStack(spacing: 8) {
                    RatioTag("Soon")
                    RatioTag("Ratio Plus", icon: "lock.fill")
                    RatioTag("Sparring partner", icon: "circle.dashed")
                }
                HStack(spacing: 8) {
                    RatioTag("Law moved", style: .tint(.ratioOxblood))
                    RatioTag("Hypothesis")
                    RatioTag("Under review", style: .tint(.ratioOxblood))
                }
            }
        }
    }

    private var controlSection: some View {
        sectionCard("Controls") {
            VStack(alignment: .leading, spacing: 16) {
                RatioSegmentedControl(
                    options: [("daily", "Daily"), ("weekly", "Weekly"), ("monthly", "Monthly")],
                    selection: $segment
                )
                RatioToggle("Exam pause", caption: "Up to 3 weeks a year · 3 left", isOn: $examPause)
                RatioStepper("Weekly target", value: $weeklyTarget, in: 1...7) { "\($0) of 7" }
                RatioTextField("First name", placeholder: "Amara", text: $firstName)
            }
        }
    }

    private var optionRowSection: some View {
        sectionCard("Option rows and feedback") {
            VStack(spacing: 10) {
                RatioOptionRow(letter: "A", text: "He intended it: he lit the fire.", state: .default) {}
                RatioOptionRow(letter: "B", text: "They may find intention if death was virtually certain and he saw it", state: .selected) {}
                RatioOptionRow(text: "They may find intention…", state: .correct)
                RatioOptionRow(text: "No intent: he wanted money, not death", state: .incorrect)
            }
        }
    }

    private var feedbackSection: some View {
        sectionCard("Why and the trap") {
            VStack(spacing: 12) {
                RatioWhyCard("Motive is not the test. If death or serious injury was a virtual certainty and Dev appreciated that, the jury may find intention.")
                RatioTrapCard(
                    commonWrongAnswer: "Treating his aim (money) as the only intention.",
                    whyItsWrong: "Woollin lets foresight of virtual certainty be evidence of intent."
                )
                RatioReportErrorLink {}
            }
        }
    }

    private var spotArtSection: some View {
        sectionCard("Engraving spot art") {
            HStack(spacing: 16) {
                ForEach(Array(RatioSpotArt.allCases.enumerated()), id: \.offset) { _, art in
                    art.view
                        .foregroundStyle(Color.ratioInk)
                        .frame(width: 48, height: 48)
                }
            }
        }
    }

    private var glassSection: some View {
        sectionCard("Liquid Glass") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Brief · 18 min")
                    .ratioFont(.h3)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ratioGlassCard()
                RatioGlassDebugToggle()
                    .ratioFont(.small)
            }
        }
    }

    private var iconSection: some View {
        sectionCard("App icon") {
            HStack(spacing: 14) {
                iconButton(nil, label: "Ink")
                iconButton("AppIcon-Parchment", label: "Parchment")
                iconButton("AppIcon-Oxblood", label: "Oxblood")
                iconButton("AppIcon-Chambers", label: "Chambers")
                iconButton("AppIcon-Gold", label: "Gold")
                iconButton("AppIcon-Green", label: "Green")
            }
        }
    }

    private func iconButton(_ name: String?, label: String) -> some View {
        Button {
            UIApplication.shared.setAlternateIconName(name) { error in
                if let error { print("Icon switch failed: \(error)") }
            }
        } label: {
            VStack(spacing: 4) {
                Circle().fill(Color.ratioRule).frame(width: 36, height: 36)
                Text(label).ratioFont(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).ratioFont(.monoLabel).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    DesignSystemCatalogView()
}
#endif
