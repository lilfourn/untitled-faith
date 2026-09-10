import Foundation

struct ContributionSelection: Codable, Equatable, Sendable {
    let amountCents: Int
    let developerShareBasisPoints: Int

    var developerCents: Int { (amountCents * developerShareBasisPoints + 5_000) / 10_000 }
    var usageBeforeFeesCents: Int { amountCents - developerCents }

    static func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD"))
    }
}

struct ContributionDraft {
    static let minimumCents = 100
    static let maximumCents = 100_000
    private(set) var entry = "0"
    var developerShareBasisPoints = 0

    var amountCents: Int { Self.cents(in: entry) }
    var canContinue: Bool { (Self.minimumCents...Self.maximumCents).contains(amountCents) }
    var amountFormatted: String { ContributionSelection.money(amountCents) }
    var selection: ContributionSelection {
        ContributionSelection(amountCents: amountCents, developerShareBasisPoints: min(300, max(0, developerShareBasisPoints)))
    }

    @discardableResult
    mutating func insert(_ key: String) -> Bool {
        guard key == "." || (key.count == 1 && "0123456789".contains(key)) else { return false }
        var next = entry
        if key == "." {
            guard !entry.contains(".") else { return false }
            next += key
        } else {
            if let decimal = entry.firstIndex(of: "."), entry.distance(from: decimal, to: entry.endIndex) > 2 { return false }
            next = entry == "0" ? key : entry + key
        }
        guard next.count <= 7, Self.cents(in: next) <= Self.maximumCents, next != entry else { return false }
        entry = next
        return true
    }

    mutating func deleteLastDigit() {
        guard entry != "0" else { return }
        entry.removeLast()
        if entry.isEmpty { entry = "0" }
    }

    private static func cents(in value: String) -> Int {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let whole = Int(parts[0]) ?? 0
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        return whole * 100 + (Int((fraction + "00").prefix(2)) ?? 0)
    }
}
