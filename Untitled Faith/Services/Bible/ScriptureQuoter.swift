import Foundation

/// Turns references into citation cards: cached or freshly fetched licensed text first, then the bundled
/// translation when the service is unavailable. Results keep the order of the references.
final class ScriptureQuoter: @unchecked Sendable {
    private let service: (any PassageFetching)?
    private let cache: PassageCache?
    private let fallback: BibleStore?

    init(service: (any PassageFetching)?, cache: PassageCache?, fallback: BibleStore?) {
        self.service = service
        self.cache = cache
        self.fallback = fallback
    }

    /// Supplies cards for the first render and saved answer without waiting on a network request.
    func availableCitations(for references: [BibleReference]) -> [ScriptureCitation] {
        var seen: Set<BibleReference> = []
        return references.compactMap { reference in
            guard seen.insert(reference).inserted else { return nil }
            if let entry = cache?.passage(for: reference) {
                return ScriptureCitation(id: UUID(), reference: reference.description, translation: entry.translation, passage: entry.text)
            }
            return fallback?.citation(reference)
        }
    }

    func citations(for references: [BibleReference]) async -> [ScriptureCitation] {
        var results: [BibleReference: ScriptureCitation] = [:]
        var missing: [BibleReference] = []
        var requested: Set<BibleReference> = []
        for reference in references where requested.insert(reference).inserted {
            if let entry = cache?.passage(for: reference) {
                results[reference] = ScriptureCitation(id: UUID(), reference: reference.description, translation: entry.translation, passage: entry.text)
            } else {
                missing.append(reference)
            }
        }
        // Keep the licensed request within the backend's eight-passage bound. Any remaining
        // references still get a card from the bundled translation instead of being dropped.
        let licensed = Array(missing.prefix(8))
        if let service, !licensed.isEmpty, let quoted = try? await service.passages(for: licensed) {
            for (reference, text) in quoted.passages where licensed.contains(reference) {
                cache?.store(text, translation: quoted.translation, for: reference)
                results[reference] = ScriptureCitation(id: UUID(), reference: reference.description, translation: quoted.translation, passage: text)
            }
        }
        for reference in references where results[reference] == nil {
            results[reference] = fallback?.citation(reference)
        }
        var seen: Set<BibleReference> = []
        return references.compactMap { seen.insert($0).inserted ? results[$0] : nil }
    }
}
