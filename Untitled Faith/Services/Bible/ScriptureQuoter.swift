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

    func citations(for references: [BibleReference]) async -> [ScriptureCitation] {
        var results: [BibleReference: ScriptureCitation] = [:]
        var missing: [BibleReference] = []
        for reference in references where results[reference] == nil {
            if let entry = cache?.passage(for: reference) {
                results[reference] = ScriptureCitation(id: UUID(), reference: reference.description, translation: entry.translation, passage: entry.text)
            } else {
                missing.append(reference)
            }
        }
        if let service, !missing.isEmpty, let quoted = try? await service.passages(for: missing) {
            for (reference, text) in quoted.passages where missing.contains(reference) {
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
