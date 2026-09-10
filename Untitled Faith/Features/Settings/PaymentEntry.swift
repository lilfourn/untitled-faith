import StoreKit
import SwiftUI

struct PaymentEntry: View {
    let session: AppSession
    let addUsage: () -> Void
    @State private var configuration: PaymentAPI.Configuration?
    @State private var isUSStorefront = false
    @State private var checking = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.isPreview || (isUSStorefront && configuration?.enabled == true) {
                Button("Add usage", systemImage: "plus", action: addUsage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 32)
                    .disabled(session.isDeletingAccount || session.hasPendingDeletion)
            } else if checking {
                ProgressView().accessibilityLabel("Checking purchase availability")
            } else {
                Text("Your free allowance renews each month.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let value = session.accountUsage.value, value.funding.availableMicros > 0 {
                LabeledContent("Usage funding", value: Self.money(value.funding.availableMicros))
                    .font(.subheadline)
            }
            if configuration?.isOwner == true, let api = session.makePaymentAPI() {
                NavigationLink("Payment overview") { OwnerPaymentsView(api: api) }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            checking = true
            configuration = nil
            isUSStorefront = await Storefront.current?.countryCode == "USA"
            if !session.isPreview, let api = session.makePaymentAPI() {
                configuration = try? await api.configuration()
                if configuration?.enabled == true {
                    _ = try? await api.pending()
                    session.refreshUsage(force: true)
                }
            }
            checking = false
        }
    }

    static func money(_ micros: Int64) -> String {
        (Decimal(micros) / 1_000_000).formatted(.currency(code: "USD"))
    }
}
