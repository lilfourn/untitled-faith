import Foundation

/// Select across the complete Bible, then resolve the exact ESV wording through the shared quoter.
enum HomeVerses {
    static func random(excluding lastReference: String, quoter: ScriptureQuoter) async -> ScriptureCitation? {
        if quoter.hasPassageCache {
            return await quoter.homePool.draw(excluding: lastReference, quoter: quoter)
        }
        guard let store = BibleStore.bundled,
              let verse = try? store.randomVerse(excluding: BibleReference.parse(lastReference)) else { return nil }
        let citations = await quoter.citations(for: [verse.reference])
        // The chat's quoter may fall back to BSB; the home carousel must stay ESV-only.
        return citations.first { $0.translation == "ESV" }
    }
}

/// Reuses the device's verse pool immediately and adds variety at most once every five minutes.
/// Failed refills back off too, while existing ESV verses remain readable offline.
actor HomeVersePool {
    private var refill: Task<Void, Never>?
    private var nextRefill = Date.distantPast

    func draw(excluding lastReference: String, quoter: ScriptureQuoter) async -> ScriptureCitation? {
        let cached = quoter.cachedHomeVerse(excluding: lastReference)
        if refill == nil && Date() >= nextRefill {
            nextRefill = Date().addingTimeInterval(5 * 60)
            refill = Task {
                guard let store = BibleStore.bundled else { return }
                var references: [BibleReference] = []
                var seen: Set<BibleReference> = []
                // Bound selection work even if the database ever returns too few distinct verses.
                for _ in 0..<32 where references.count < 8 {
                    guard let verse = try? store.randomVerse(excluding: BibleReference.parse(lastReference)),
                          seen.insert(verse.reference).inserted else { continue }
                    references.append(verse.reference)
                }
                _ = await quoter.citations(for: references)
            }
            let current = refill
            Task {
                await current?.value
                self.finishedRefill()
            }
        }
        if let cached { return cached }
        await refill?.value
        return quoter.cachedHomeVerse(excluding: lastReference)
    }

    private func finishedRefill() { refill = nil }
}
