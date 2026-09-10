import Foundation

/// Select across the complete Bible, then resolve the exact ESV wording through the shared quoter.
enum HomeVerses {
    static func random(excluding lastReference: String, quoter: ScriptureQuoter) async -> ScriptureCitation? {
        guard let store = BibleStore.bundled,
              let verse = try? store.randomVerse(excluding: BibleReference.parse(lastReference)) else { return nil }
        let citations = await quoter.citations(for: [verse.reference])
        // The chat's quoter may fall back to BSB; the home carousel must stay ESV-only.
        return citations.first { $0.translation == "ESV" }
    }
}
