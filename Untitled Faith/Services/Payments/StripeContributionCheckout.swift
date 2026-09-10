import StoreKit
import UIKit

@MainActor
final class StripeContributionCheckout: ContributionCheckout {
    private let api: PaymentAPI
    private var lastSelection: ContributionSelection?
    private var requestKey = UUID().uuidString

    init(api: PaymentAPI) { self.api = api }

    func begin(_ selection: ContributionSelection) async throws {
        guard await Storefront.current?.countryCode == "USA" else { throw PaymentError.regionUnavailable }
        if lastSelection != selection { requestKey = UUID().uuidString; lastSelection = selection }
        let checkout: PaymentAPI.Checkout
        do { checkout = try await api.checkout(selection, storefront: "USA", key: requestKey) }
        catch PaymentError.checkoutFinished {
            requestKey = UUID().uuidString
            throw PaymentError.checkoutFinished
        }
        try Task.checkCancellation()
        // Digital usage checkout leaves the app; card details never pass through the app or Worker.
        guard await UIApplication.shared.open(checkout.checkoutURL) else { throw PaymentError.unavailable }
    }
}
