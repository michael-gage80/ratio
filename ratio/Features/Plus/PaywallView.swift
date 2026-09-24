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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    Text("Ratio \(Text("Plus").italic().foregroundStyle(Color.ratioOxblood))").ratioFont(.display)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                            .background(Color.ratioSunk, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                if let reason { Text(reason).ratioFont(.body).foregroundStyle(Color.ratioOxblood) }
                Text("All \(Module.allCases.count) modules, unlimited duels, and your full profile.").ratioFont(.h3)
                comparison
                Text("Accessibility features and extended time are always free.").ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                if student.isPlus {
                    Label("You have Ratio Plus.", systemImage: "checkmark.seal").ratioFont(.h3).foregroundStyle(Color.ratioVerdigris)
                } else if purchases.products.isEmpty {
                    Text(purchases.loadFailed ? "Plans couldn't load. Check your connection and try again." : "Loading plans…")
                        .ratioFont(.small).foregroundStyle(Color.ratioInk2)
                } else {
                    plans
                    RatioButton(working ? "One moment…" : buttonTitle, isEnabled: !working) { Task { await buy() } }
                    Text(terms).ratioFont(.small).foregroundStyle(Color.ratioInk2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                if let message { Text(message).ratioFont(.small).foregroundStyle(Color.ratioOxblood) }
                HStack {
                    Button("Restore purchases") { Task { await restore() } }
                    Spacer()
                    Button("Have a university code?") { enteringCode = true }
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk)
                HStack(spacing: 16) {
                    Link("Terms", destination: RatioLinks.terms)
                    Link("Privacy", destination: RatioLinks.privacy)
                }
                .ratioFont(.monoLabel)
                .foregroundStyle(Color.ratioInk2)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
        .task { if purchases.products.isEmpty { await purchases.loadProducts() } }
        .onChange(of: student.isPlus) { _, isPlus in if isPlus { dismiss() } }
        .sheet(isPresented: $enteringCode) { LicenceCodeSheet().presentationDetents([.medium]) }
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.ratioInk).frame(height: 1)
            row("", free: "Free", plus: "Plus", header: true)
            row("Modules", free: "1 of your choice", plus: "All \(Module.allCases.count)")
            row("Brief and reviews", free: "Your free module", plus: "Every module")
            row("Duels", free: "3 a day", plus: "Unlimited")
            row("Profile", free: "Headline scores", plus: "Topic drill-down and trends")
        }
    }

    private func row(_ label: String, free: String, plus: String, header: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2).frame(width: 92, alignment: .leading)
                Text(free).ratioFont(header ? .monoLabel : .body).foregroundStyle(Color.ratioInk2).frame(maxWidth: .infinity, alignment: .leading)
                Text(plus).ratioFont(header ? .monoLabel : .body).foregroundStyle(header ? Color.ratioOxblood : Color.ratioInk).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            Divider().overlay(Color.ratioRule)
        }
        .accessibilityElement(children: .combine)
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if let annual = purchases.annualProduct {
                plan(annual, title: "Annual", detail: annualDetail(annual))
            }
            if let monthly = purchases.monthlyProduct {
                plan(monthly, title: "Monthly", detail: "Billed monthly")
            }
        }
    }

    private func plan(_ product: Product, title: String, detail: String) -> some View {
        let selected = choice == product.id
        return Button { choice = product.id } label: {
            HStack(spacing: 16) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).ratioFont(.h3)
                    Text(detail).ratioFont(.monoLabel).foregroundStyle(Color.ratioInk2)
                }
                Spacer()
                Text(product.displayPrice).ratioFont(.monoData)
            }
            .padding(18)
            .background(Color.ratioPaper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(selected ? Color.ratioInk : Color.ratioRule, lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("University licence").ratioFont(.h2)
            if let done {
                Label("Ratio Plus is on, through \(done).", systemImage: "checkmark.seal").ratioFont(.h3).foregroundStyle(Color.ratioVerdigris)
                RatioButton("Done", style: .secondary) { dismiss() }
            } else {
                Text("Enter the code from your university. You'll need to be signed in with your university email.").ratioFont(.body)
                TextField("Code", text: $code)
                    .font(.custom("IBMPlexMono-Regular", size: 22, relativeTo: .title3))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Color.ratioSunk, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(24)
        .background(Color.ratioParchment.ignoresSafeArea())
        .foregroundStyle(Color.ratioInk)
    }
}

/// Where the website's legal pages live.
enum RatioLinks {
    static let privacy = URL(string: "https://ratio.app/privacy")!
    static let terms = URL(string: "https://ratio.app/terms")!
}
