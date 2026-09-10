import Foundation

@MainActor
struct PaymentAPI {
    let baseURL: URL
    let accessToken: () async throws -> String
    var isCurrentSession: () -> Bool = { true }
    var session: URLSession = ProxyAnswerService.makeSession()

    struct Configuration: Decodable {
        let enabled: Bool
        let isOwner: Bool
        let mode: String
    }
    struct Checkout: Decodable {
        let intentID: String
        let checkoutURL: URL
        let estimatedFeeCents: Int
    }
    struct CheckoutStatus: Decodable {
        let id: String
        let status: String
        let usageMicros: Int64?
        let developerMicros: Int64?
    }
    private struct Pending: Decodable { let checkouts: [CheckoutStatus] }
    private struct Selection: Encodable {
        let amountCents: Int
        let developerShareBasisPoints: Int
        let storefront: String
    }
    private struct Failure: Decodable {
        let error: Detail
        struct Detail: Decodable { let code: String }
    }

    func configuration() async throws -> Configuration {
        try await request("v1/payments/configuration")
    }

    func checkout(_ selection: ContributionSelection, storefront: String, key: String) async throws -> Checkout {
        let body = try JSONEncoder().encode(Selection(amountCents: selection.amountCents,
            developerShareBasisPoints: selection.developerShareBasisPoints, storefront: storefront))
        let response: Checkout = try await request("v1/payments/checkout", body: body, key: key)
        guard Self.isCheckoutURL(response.checkoutURL) else { throw PaymentError.unavailable }
        return response
    }

    func pending() async throws -> [CheckoutStatus] {
        let response: Pending = try await request("v1/payments/pending")
        return response.checkouts
    }

    func ownerSummary() async throws -> OwnerPaymentSummary {
        try await request("v1/owner/payments")
    }

    static func isCheckoutURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "checkout.stripe.com" && url.user == nil && url.password == nil && url.port == nil
    }

    private func request<T: Decodable>(_ path: String, body: Data? = nil, key: String? = nil) async throws -> T {
        guard AuthenticationAPI.isSecureBaseURL(baseURL) else { throw PaymentError.unavailable }
        let token = try await accessToken()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 45
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard isCurrentSession() else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, data.count <= 128 * 1024 else { throw PaymentError.unavailable }
        if http.statusCode == 401 { throw AnswerServiceError.signInRequired }
        if http.statusCode == 403 { throw PaymentError.unavailable }
        if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
            if failure.error.code == "checkout_finished" { throw PaymentError.checkoutFinished }
            if failure.error.code == "payments_not_configured" { throw PaymentError.notConfigured }
            throw PaymentError.unavailable
        }
        guard http.statusCode == 200 else { throw PaymentError.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum PaymentError: LocalizedError {
    case unavailable, notConfigured, regionUnavailable, checkoutFinished
    var errorDescription: String? {
        switch self {
        case .unavailable: return "We couldn’t confirm the checkout status. Please try again. Your balance updates only after payment is confirmed."
        case .notConfigured: return "Purchases aren’t available yet. Please try again later."
        case .regionUnavailable: return "Purchases aren’t available in your App Store region."
        case .checkoutFinished: return "This checkout has ended. Check your balance before starting another purchase."
        }
    }
}
