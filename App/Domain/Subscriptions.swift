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

    private static let log = Logger(subsystem: "com.coachjett.ios", category: "store")

    static let monthlyID = "com.coachjett.ios.pro.monthly"
    static let yearlyID = "com.coachjett.ios.pro.yearly"
    /// The founding hundred's yearly price, offered instead of the standard one and only
    /// to them. In the same subscription group as the other two, which is the thing App
    /// Store Connect will not let anybody change afterwards.
    static let founderYearlyID = "com.coachjett.ios.pro.yearly.founding"
    static let productIDs = [yearlyID, monthlyID, founderYearlyID]

    private(set) var products: [Product] = []
    private(set) var isSubscribed = false
    /// A free trial that is still on course to become a charge, if there is one.
    ///
    /// Read by the app root and handed to `Notifications`, which is the only thing that
    /// owns the notification centre. Nil covers every reason there is nothing to warn
    /// about: not subscribed, past the trial, or renewal already turned off.
    private(set) var trialCharge: TrialCharge?
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
    /// Nil for anybody outside the first hundred, even though the product always exists.
    /// It used to be simply "the founding product if loaded", and the paywall took its
    /// default selection and its savings badge from it, so everybody got the founder
    /// price selected. Everything that asks for it now gets the member's answer.
    var founderYearly: Product? {
        offeredYearlyID == Self.founderYearlyID ? products.first { $0.id == Self.founderYearlyID } : nil
    }

    /// Which yearly plan this member is sold, decided in one place.
    private var offeredYearlyID: String {
        FoundingMember.yearlyProductID(member: AppAttest.member,
                                       standard: Self.yearlyID, founding: Self.founderYearlyID)
    }

    /// What this person can actually buy.
    ///
    /// The founding hundred are offered their yearly price instead of the standard one,
    /// never beside it: two yearly rows differing only in price is a puzzle rather than
    /// an offer. Everybody else never sees that it exists, because a discount somebody
    /// cannot take is an advert for having arrived too late.
    var offered: [Product] {
        products.filter { product in
            switch product.id {
            case Self.founderYearlyID, Self.yearlyID: return product.id == offeredYearlyID
            default: return true
            }
        }
    }

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

    /// A free trial that has not been cancelled, and when it turns into money.
    struct TrialCharge: Equatable {
        let ends: Date
        /// "$8.99 a month", as the store itself renders it.
        let priceLine: String
    }

    /// True when any transaction in the Pro group is currently entitling the user.
    func refreshEntitlement() async {
        var entitled = false
        var trial: TrialCharge?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                entitled = true
                if let found = await trialCharge(for: transaction) { trial = found }
            }
        }
        trialCharge = trial
        if entitled != isSubscribed {
            Self.log.notice("entitlement changed to \(entitled)")
        }
        isSubscribed = entitled
        // The server is told by Apple, not by us, so the signed form travels with every
        // request and has to be refreshed whenever this is.
        await Entitlement.refresh()
    }

    /// Is this transaction a free trial that is still going to be charged for?
    ///
    /// Three ways to be nil, and all three mean the same thing to the caller: there is
    /// nothing worth warning anybody about. Not a trial, no product to read a price
    /// off, or renewal already turned off by somebody who has made their decision.
    private func trialCharge(for transaction: Transaction) async -> TrialCharge? {
        guard Self.isFreeTrial(transaction), let ends = transaction.expirationDate else { return nil }
        guard let product = products.first(where: { $0.id == transaction.productID }) else {
            // Products load after the first entitlement refresh on a cold start. That
            // refresh runs again once they are in, so this is a wait, not a miss.
            return nil
        }
        let statuses = (try? await product.subscription?.status) ?? []
        for status in statuses {
            guard case .verified(let renewal) = status.renewalInfo else { continue }
            if renewal.currentProductID == transaction.productID, !renewal.willAutoRenew {
                return nil
            }
        }
        return TrialCharge(ends: ends, priceLine: product.periodDescription)
    }

    /// `Transaction.offer` is the current spelling and needs iOS 17.2. This app runs on
    /// 17.0, so the deprecated property is the fallback rather than the floor.
    private static func isFreeTrial(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.paymentMode == .freeTrial
        }
        return transaction.offerType == .introductory
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
