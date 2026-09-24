import CryptoKit
import FirebaseFunctions
import Foundation
import StoreKit

/// Ratio Plus through StoreKit 2 (PRD: "Purchases go through StoreKit 2 and are verified
/// by the server"). The app never grants Plus itself: every transaction goes to the
/// verifyPurchase Function, which writes users/{uid}.subscription — and the student's
/// profile listener picks that up.
@Observable
final class Purchases {
    static let monthly = "com.mg.ratio.plus.monthly"
    static let annual = "com.mg.ratio.plus.annual"

    private(set) var products: [Product] = []
    private(set) var loadFailed = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    var annualProduct: Product? { products.first { $0.id == Self.annual } }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthly } }

    /// Starts listening for renewals, refunds and purchases made elsewhere (Ask to Buy,
    /// another device) for as long as the app runs.
    func start() {
        guard updates == nil else { return }
        updates = Task.detached(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if await Self.verifyOnServer(result.jwsRepresentation) { await transaction.finish() }
            }
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.annual, Self.monthly]).sorted { $0.price > $1.price }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    enum Outcome { case purchased, pending, cancelled }

    /// Buys the product for this student; the account token ties it to their Ratio account.
    func purchase(_ product: Product, uid: String) async throws -> Outcome {
        let result = try await product.purchase(options: [.appAccountToken(Self.accountToken(for: uid))])
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            guard await Self.verifyOnServer(verification.jwsRepresentation) else { throw PurchaseError.serverRejected }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore purchases: re-syncs with the App Store and re-verifies what's current.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        var restored = false
        for await result in Transaction.currentEntitlements {
            if case .verified = result, await Self.verifyOnServer(result.jwsRepresentation) { restored = true }
        }
        return restored
    }

    enum PurchaseError: LocalizedError {
        case unverified, serverRejected

        var errorDescription: String? {
            switch self {
            case .unverified: "The App Store couldn't confirm that purchase."
            case .serverRejected: "Your purchase went through but we couldn't confirm it yet. Try Restore purchases in a moment."
            }
        }
    }

    private static func verifyOnServer(_ jws: String) async -> Bool {
        let function = Functions.functions(region: "europe-west2").httpsCallable("verifyPurchase")
        return (try? await function.call(["signedTransaction": jws])) != nil
    }

    /// A stable UUID for the student, so purchases carry which account they're for.
    static func accountToken(for uid: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("ratio:\(uid)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // Version 5-style
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

enum PlanService {
    private static var functions: Functions { Functions.functions(region: "europe-west2") }

    static func redeemLicence(_ code: String) async throws -> String {
        let result = try await functions.httpsCallable("redeemLicence").call(["code": code])
        return ((result.data as? [String: Any])?["universityName"] as? String) ?? "your university"
    }

    static func chooseFreeModule(_ module: Module) async throws {
        _ = try await functions.httpsCallable("chooseFreeModule").call(["moduleId": module.rawValue])
    }

    /// Whether an error from a duel Function is the free tier's daily limit.
    static func isFreeLimit(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain, FunctionsErrorCode(rawValue: error.code) == .resourceExhausted else { return false }
        return (error.userInfo[FunctionsErrorDetailsKey] as? [String: Any])?["reason"] as? String == "free-limit"
    }
}
