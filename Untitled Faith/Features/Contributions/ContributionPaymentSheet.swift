import SwiftUI

struct ContributionPaymentSheet: View {
    @State private var checkout: any ContributionCheckout
    private let usesBrowserCheckout: Bool

    init(session: AppSession) {
        if !session.isPreview, let api = session.makePaymentAPI() {
            _checkout = State(initialValue: StripeContributionCheckout(api: api))
            usesBrowserCheckout = true
        } else {
            _checkout = State(initialValue: UnconfiguredContributionCheckout())
            usesBrowserCheckout = false
        }
    }

    var body: some View {
        ContributionWizard(checkout: checkout, usesBrowserCheckout: usesBrowserCheckout)
    }
}
