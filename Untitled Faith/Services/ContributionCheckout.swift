import Foundation

@MainActor
protocol ContributionCheckout {
    func begin(_ selection: ContributionSelection) async throws
}

struct UnconfiguredContributionCheckout: ContributionCheckout {
    func begin(_ selection: ContributionSelection) async throws {
        // A payment adapter must verify the receipt and split on the server before adding usage.
        throw ContributionCheckoutError.unavailable
    }
}

enum ContributionCheckoutError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Contributions aren’t available just yet. You haven’t been charged." }
}
