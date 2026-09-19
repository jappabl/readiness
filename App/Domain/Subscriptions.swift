import Foundation
import StoreKit
import os

/// Everything StoreKit, in one place.
///
/// Entitlement is read from `Transaction.currentEntitlements`, which StoreKit verifies
/// cryptographically on device. There is no server behind this and none is required for
/// a single-platform app: Apple signs the transaction, and a forged one fails
/// verification here. A receipt-validation server buys cross-platform entitlement and
/// better fraud handling, and neither is needed before there is a second platform.
@Observable
@MainActor
final class Subscriptions {

    private static let log = Logger(subsystem: "com.coachjett.app", category: "store")

    static let monthlyID = "com.coachjett.app.pro.monthly"
    static let yearlyID = "com.coachjett.app.pro.yearly"
    static let productIDs = [yearlyID, monthlyID]

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    private(set) var isLoading = false
    /// Set when a purchase fails for a reason worth telling the user about. A cancel is
    /// not one of those.
    private(set) var failure: String?

    /// Written once in `init` and read once in `deinit`, which cannot hop to the main
    /// actor. There is no other access, so there is nothing to race with.
    private nonisolated(unsafe) var updates: Task<Void, Never>?

    init() {
        // Started before anything else: a renewal, a refund or a purchase made on
        // another device arrives here rather than through a call we made.
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self.refreshEntitlement()
            }
        }
    }

    deinit { updates?.cancel() }

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Keep the order we asked for, so the yearly plan is always first.
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            Self.log.error("products failed: \(error.localizedDescription)")
        }
        await refreshEntitlement()
    }

    /// True when any transaction in the Pro group is currently entitling the user.
    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                entitled = true
            }
        }
        if entitled != isSubscribed {
            Self.log.notice("entitlement changed to \(entitled)")
        }
        isSubscribed = entitled
    }

    /// Returns true when the user came away subscribed.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        failure = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // An unverified transaction is the one case worth being loud about:
                    // it means the signature did not check out.
                    failure = "That purchase could not be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlement()
                return isSubscribed

            case .pending:
                // Ask to Buy, or a card needing approval. Nothing has gone wrong.
                failure = "Waiting on approval. You'll get Jett as soon as it clears."
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            failure = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            Self.log.error("restore failed: \(error.localizedDescription)")
        }
        await refreshEntitlement()
        if !isSubscribed { failure = "No subscription found on this Apple Account." }
    }

    func clearFailure() { failure = nil }
}

extension Product {
    /// "£59.99 a year", in the store's own currency and wording.
    var periodDescription: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        switch period.unit {
        case .year:  return "\(displayPrice) a year"
        case .month: return "\(displayPrice) a month"
        case .week:  return "\(displayPrice) a week"
        case .day:   return "\(displayPrice) a day"
        @unknown default: return displayPrice
        }
    }

    /// What a year costs broken down per month, so the yearly plan can be compared
    /// against the monthly one without the reader doing arithmetic.
    var monthlyEquivalent: String? {
        guard let period = subscription?.subscriptionPeriod, period.unit == .year else { return nil }
        let perMonth = price / 12
        return perMonth.formatted(.currency(code: priceFormatStyle.currencyCode)
            .precision(.fractionLength(2)))
    }

    /// "1 week free", when there is an introductory offer.
    var introductoryDescription: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial
        else { return nil }
        let count = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day:   unit = count == 1 ? "day" : "days"
        case .week:  unit = count == 1 ? "week" : "weeks"
        case .month: unit = count == 1 ? "month" : "months"
        case .year:  unit = count == 1 ? "year" : "years"
        @unknown default: return nil
        }
        return "\(count) \(unit) free"
    }
}
