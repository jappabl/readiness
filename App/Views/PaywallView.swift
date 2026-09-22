import SwiftUI
import StoreKit

/// What Pro is, and what it costs, without a countdown timer or a fake discount.
///
/// The offer is honest about where the line sits: everything the app measures is free,
/// and the coach is what you pay for, because the coach is the part with a cost every
/// time it is used. Saying that plainly converts worse than urgency tricks and is the
/// only version worth shipping.
struct PaywallView: View {
    var onDone: () -> Void

    @Environment(Subscriptions.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selected: String = Subscriptions.yearlyID
    @State private var redeeming = false

    /// The yearly row this person is actually offered, which is the founding one when
    /// they are one of the hundred.
    private var defaultSelection: String {
        store.founderYearly?.id ?? Subscriptions.yearlyID
    }
    @State private var working = false

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                closeRow
                // No scroll view. The demo is the only thing that changes size, so it
                // takes the slack; everything else holds still.
                heading
                    .padding(.horizontal, Tokens.screenMargin)
                // Top-aligned, because a conversation starts at the top and grows
                // down. Centred in the slack it read as a graphic floating in space,
                // which is the opposite of the thing it is meant to be showing.
                PaywallDemo()
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer
            }
        }
        .task {
            if store.products.isEmpty { await store.load() }
            // A founder's default is their own yearly row, not the standard one they are
            // never shown: selecting a product that is not on screen leaves the button
            // buying something invisible.
            selected = defaultSelection
        }
        // Apple's own sheet, not ours. Redemption is an App Store transaction and the
        // only correct interface for it is the one people already recognise.
        .offerCodeRedemption(isPresented: $redeeming) { result in
            if case .success = result { Task { await store.refreshEntitlement() } }
        }
        .onChange(of: store.isSubscribed) { _, subscribed in
            if subscribed { Haptics.committed(); onDone() }
        }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button { Haptics.light(); onDone() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var heading: some View {
        HStack(spacing: 11) {
            JettFace(size: 34)
            Text("Coach Jett")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading plans…")
                    .font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Unlimited answers on every plan, on your own numbers.")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(store.offered, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selected == product.id
        let isFounder = product.id == Subscriptions.founderYearlyID
        let isYearly = product.id == Subscriptions.yearlyID || isFounder
        return Button {
            Haptics.decided()
            selected = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Tokens.accent : Tokens.hairline)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(isFounder ? "Founding yearly" : (isYearly ? "Yearly" : "Monthly"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                        if let saving = yearlySaving, isYearly {
                            Label(saving, systemImage: "tag.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Tokens.accent)
                        }
                    }
                    Text(subtitle(for: product))
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Tokens.accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func subtitle(for product: Product) -> String {
        var parts: [String] = [product.periodDescription]
        if let monthly = product.monthlyEquivalent { parts.append("\(monthly) a month") }
        if let intro = product.introductoryDescription { parts.append(intro) }
        return parts.joined(separator: " · ")
    }

    /// Worked out from the real prices, never hardcoded: a "save 40%" badge that does
    /// not match what is charged is a lie with a number on it.
    private var yearlySaving: String? {
        guard let yearly = store.founderYearly ?? store.yearly,
              let monthly = store.monthly else { return nil }
        let fullYear = monthly.price * 12
        guard fullYear > 0, yearly.price < fullYear else { return nil }
        let share = (fullYear - yearly.price) / fullYear
        let percent = Int((NSDecimalNumber(decimal: share).doubleValue * 100).rounded())
        return percent >= 5 ? "SAVE \(percent)%" : nil
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // Prices sit here rather than in the scroll view. Pinned, they cannot be
            // pushed around by a demo that changes height every few seconds, and they
            // are on screen without scrolling, which is what somebody weighing two
            // plans actually wants.
            plans

            if let failure = store.failure {
                Text(failure)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.negative)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(label: working ? "…" : callToAction,
                          enabled: !working && !store.products.isEmpty) {
                buy()
            }

            // Redeem sits in the row that already exists, beside Restore, because that
            // is the row for the things a few people need and nobody else should have
            // to look at. Most codes never touch this screen at all: a one-tap
            // redemption link hands the whole job to the App Store and returns, so the
            // app needs no surface for it. This is here for the person holding a code
            // they were sent as text.
            HStack(spacing: 18) {
                Button("Restore") { Task { working = true; await store.restore(); working = false } }
                Button("Redeem") { redeeming = true }
                Button("Terms") { open(Backend.termsURL) }
                Button("Privacy") { open(Backend.privacyURL) }
            }
            .font(.system(size: 12))
            .foregroundStyle(Tokens.textTertiary)

            Text("Cancel any time in Settings. "
                 + "A free trial converts to a paid subscription unless cancelled before it ends.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.bottom, 12)
    }

    private var callToAction: String {
        let product = store.products.first { $0.id == selected }
        return product?.introductoryDescription == nil ? "Subscribe" : "Start free trial"
    }

    private func buy() {
        guard let product = store.products.first(where: { $0.id == selected }) else { return }
        working = true
        Task {
            await store.purchase(product)
            working = false
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { openURL(url) }
    }
}
