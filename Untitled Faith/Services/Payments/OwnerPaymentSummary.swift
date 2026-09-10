import Foundation

struct OwnerPaymentSummary: Decodable {
    let currency: String
    let stripe: StripeTotals
    let legacy: LegacyTotals
    let users: UserTotals
    let operations: Operations
    let months: [Month]
    let recentPayments: [Payment]

    struct StripeTotals: Decodable {
        let payments: Int
        let grossMicros: Int64
        let refundedMicros: Int64
        let confirmedFeeMicros: Int64
        let estimatedFeeMicros: Int64
        let awaitingFees: Int
        let disputedMicros: Int64
        let usageFundingMicros: Int64
        let developerShareMicros: Int64
    }
    struct LegacyTotals: Decodable { let developerShareMicros: Int64; let usageFundingMicros: Int64 }
    struct UserTotals: Decodable { let userBalanceMicros: Int64; let userReservedMicros: Int64 }
    struct Operations: Decodable { let pendingEvents: Int; let pendingCheckouts: Int }
    struct Month: Decodable, Identifiable {
        let month: String
        let usageFundingMicros: Int64
        let developerShareMicros: Int64
        var id: String { month }
    }
    struct Payment: Decodable, Identifiable {
        let id: String
        let createdAt: Int64
        let grossMicros: Int64
        let feeMicros: Int64
        let feeConfirmed: Int
        let refundedMicros: Int64
        let disputed: Int
        let usageFundingMicros: Int64
        let developerShareMicros: Int64
    }
}
