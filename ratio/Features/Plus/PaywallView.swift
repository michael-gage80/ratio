import StoreKit
import SwiftUI

/// screens/16-paywall-sheet.png — what Plus adds, the two plans, and the way in. Opened
/// from a locked lesson or module, the daily duel limit, the topic drill-down, or
/// Settings. Never nags: it only appears when the student reaches for something.
struct PaywallView: View {
    /// Why it opened, shown above the comparison ("Contract is part of Ratio Plus.").
    var reason: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(Purchases.self) private var purchases
    @Environment(StudentStore.self) private var student
    @State private var choice = Purchases.annual
    @State private var working = false
    @State private var message: String?
    @State private var enteringCode = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RatioSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ratio \(Text("Plus").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body)
                            .frame(width: 44, height: 44)
                            .background(Color.ratioSunk, in: Circle())
                    }
                    .buttonStyle(.ratioPress)
                    .accessibilityLabel("Close")
                }
                VStack(alignment: .leading, spacing: RatioSpace.xs) {
                    if let reason { Text(reason).ratioFont(.body).foregroundStyle(Color.ratioOxblood) }
                    Text("All \(student.programme.modules.count) \(student.programme.title) modules, unlimited duels, and your full profile.").ratioFont(.h3)
                }
                VStack(alignment: .leading, spacing: RatioSpace.s) {
                    comparison
                    Text("Accessibility features and extra duel time are always free.").ratioFont(.small).foregroundStyle(Color.ratioInk2)
                }
                if student.isPlus {
                    Label("You have Ratio Plus.", systemImage: "checkmark.seal").ratioFont(.h3)
                } else if purchases.products.isEmpty {
                    if purchases.loadFailed {
                        RatioErrorState(message: "Plans couldn't load. Check your connection and try again.") { Task { await purchases.loadProducts() } }
                    } else {
                        plans.ratioSkeleton()
                    }
                } else {
                    VStack(spacing: RatioSpace.s) {
                        plans
                        RatioButton(working ? "One moment…" : buttonTitle, isEnabled: !working) { Task { await buy() } }
                        Text(terms).ratioFont(.small).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    }
                }
                if let message { Text(message).ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
                VStack(spacing: RatioSpace.xs) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            restoreButton
                            Spacer()
                            codeButton
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            restoreButton
                            codeButton
                        }
                    }
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk)
                    HStack(spacing: RatioSpace.m) {
                        Link("Terms", destination: RatioLinks.terms).frame(minHeight: 44)
                        Link("Privacy", destination: RatioLinks.privacy).frame(minHeight: 44)
                    }
                    .ratioFont(.monoLabel)
                    .foregroundStyle(Color.ratioInk2)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(RatioSpace.m)
        }
        .ratioPage()
        .task { if purchases.products.isEmpty { await purchases.loadProducts() } }
        .onChange(of: student.isPlus) { _, isPlus in if isPlus { dismiss() } }
        .sheet(isPresented: $enteringCode) { LicenceCodeSheet().presentationDetents([.medium]) }
    }

    private var restoreButton: some View {
        Button("Restore purchases") { Task { await restore() } }.frame(minHeight: 44)
    }

    private var codeButton: some View {
        Button("Have a university code?") { enteringCode = true }.frame(minHeight: 44)
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            row("", free: "Free", plus: "Plus", header: true)
            row("Modules", free: "1 of your choice", plus: "All \(student.programme.modules.count)")
            row("Brief and reviews", free: "Your free module", plus: "Every module")
            row("Duels", free: "3 a day", plus: "Unlimited")
            row("Profile", free: "Headline scores", plus: "Topic drill-down and trends")
        }
    }

    @ViewBuilder
    private func row(_ label: String, free: String, plus: String, header: Bool = false) -> some View {
        if typeSize.isAccessibilitySize {
            // Stacked: the feature, then free and Plus spelt out. No header row needed.
            if !header {
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                    Text("Free: \(free)").ratioFont(.body).foregroundStyle(Color.ratioInk2)
                    Text("Plus: \(plus)").ratioFont(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, RatioSpace.s)
                .accessibilityElement(children: .combine)
                Divider().overlay(Color.ratioRule)
            }
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: RatioSpace.s) {
                    Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(width: 96, alignment: .leading)
                    Text(free).ratioFont(header ? .monoLabel : .body).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity, alignment: .leading)
                    Text(plus).ratioFont(header ? .monoLabel : .body).foregroundStyle(header ? Color.ratioOxblood : Color.ratioInk).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, RatioSpace.s)
                Divider().overlay(Color.ratioRule)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var plans: some View {
        VStack(spacing: RatioSpace.s) {
            if let annual = purchases.annualProduct {
                plan(annual.id, title: "Annual", detail: annualDetail(annual), price: annual.displayPrice)
            }
            if let monthly = purchases.monthlyProduct {
                plan(monthly.id, title: "Monthly", detail: "Billed monthly", price: monthly.displayPrice)
            }
            if purchases.products.isEmpty {
                // Placeholders while the App Store answers.
                plan(Purchases.annual, title: "Annual", detail: "A month · free trial", price: "£00.00")
                plan(Purchases.monthly, title: "Monthly", detail: "Billed monthly", price: "£0.00")
            }
        }
    }

    private func plan(_ id: String, title: String, detail: String, price: String) -> some View {
        let selected = choice == id
        return Button { choice = id } label: {
            HStack(spacing: RatioSpace.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.title3)
                VStack(alignment: .leading, spacing: RatioSpace.xxs) {
                    Text(title).ratioFont(.h3)
                    Text(detail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                Spacer(minLength: RatioSpace.xs)
                Text(price).ratioFont(.monoData)
            }
            .padding(RatioSpace.s)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous).strokeBorder(selected ? Color.ratioInk : Color.ratioRule, lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.ratioPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func annualDetail(_ product: Product) -> String {
        let monthly = (product.price / 12).formatted(product.priceFormatStyle)
        return trialDays(product).map { "\(monthly) a month · \($0)-day free trial" } ?? "\(monthly) a month"
    }

    private func trialDays(_ product: Product) -> Int? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        default: return nil
        }
    }

    private var selected: Product? { purchases.products.first { $0.id == choice } }

    private var buttonTitle: String {
        guard let selected else { return "Continue" }
        return trialDays(selected).map { "Start \($0)-day free trial" } ?? "Subscribe for \(selected.displayPrice)"
    }

    private var terms: String {
        guard let selected else { return "" }
        let period = selected.id == Purchases.annual ? "year" : "month"
        let lead = trialDays(selected) != nil ? "Then " : ""
        return "\(lead)\(selected.displayPrice) a \(period). Cancel any time in Settings."
    }

    private func buy() async {
        guard let selected else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            switch try await purchases.purchase(selected, uid: student.uid) {
            case .purchased: message = nil // The profile listener turns Plus on and dismisses.
            case .pending: message = "Your purchase is waiting for approval. Plus turns on as soon as it's approved."
            case .cancelled: break
            }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "The purchase didn't go through."
        }
    }

    private func restore() async {
        working = true
        defer { working = false }
        do {
            message = try await purchases.restore() ? nil : "No Ratio Plus purchase was found for this Apple ID."
        } catch {
            message = "Restore didn't go through. Check your connection and try again."
        }
    }
}

/// University licence codes (PRD: "a university code plus a university email check").
struct LicenceCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var message: String?
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RatioSpace.s) {
            Text("University licence").ratioFont(.h2)
            if let done {
                Label("Ratio Plus is on, through \(done).", systemImage: "checkmark.seal").ratioFont(.h3)
                RatioButton("Done", style: .secondary) { dismiss() }
            } else {
                Text("Enter the code from your university. You'll need to be signed in with your university email.").ratioFont(.body)
                TextField("Code", text: $code)
                    .font(.custom("IBMPlexMono-Regular", size: 22, relativeTo: .title3))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(RatioSpace.s)
                    .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: RatioRadius.panel, style: .continuous))
                if let message { Text(message).ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
                RatioButton(working ? "Checking…" : "Redeem", isEnabled: code.count >= 4 && !working) {
                    Task {
                        working = true
                        defer { working = false }
                        do { done = try await PlanService.redeemLicence(code) } catch { message = (error as NSError).localizedDescription }
                    }
                }
            }
            Spacer()
        }
        .padding(RatioSpace.m)
        .ratioPage()
    }
}

/// Where the website's legal pages live.
enum RatioLinks {
    static let privacy = URL(string: "https://ratio.app/privacy")!
    static let terms = URL(string: "https://ratio.app/terms")!
}
