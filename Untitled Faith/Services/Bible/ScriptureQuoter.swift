import Foundation

/// Turns references into citation cards: cached or freshly fetched licensed text first, then the bundled
/// translation when the service is unavailable. Results keep the order of the references.
final class ScriptureQuoter: @unchecked Sendable {
    private let service: (any PassageFetching)?
    private let cache: PassageCache?
    private let fallback: BibleStore?
    private let requests = PassageRequests()
    let homePool = HomeVersePool()

    var hasPassageCache: Bool { cache != nil }

    func cachedHomeVerse(excluding reference: String) -> ScriptureCitation? {
        cache?.randomVerse(excluding: reference)
    }

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
        if let service, !licensed.isEmpty {
            let fetched = await requests.citations(for: licensed, service: service, cache: cache)
            results.merge(fetched) { _, new in new }
        }
        for reference in references where results[reference] == nil {
            results[reference] = fallback?.citation(reference)
        }
        var seen: Set<BibleReference> = []
        return references.compactMap { seen.insert($0).inserted ? results[$0] : nil }
    }
}

/// Registers each reference before suspending, so overlapping batches share their network work.
private actor PassageRequests {
    private var pending: [BibleReference: Task<[BibleReference: ScriptureCitation], Never>] = [:]

    func citations(for references: [BibleReference], service: any PassageFetching,
                   cache: PassageCache?) async -> [BibleReference: ScriptureCitation] {
        var results: [BibleReference: ScriptureCitation] = [:]
        var missing: [BibleReference] = []
        for reference in references {
            if let entry = cache?.passage(for: reference) {
                results[reference] = ScriptureCitation(id: UUID(), reference: reference.description,
                                                      translation: entry.translation, passage: entry.text)
            } else if pending[reference] == nil {
                missing.append(reference)
            }
        }
        if !missing.isEmpty {
            let batch = missing
            let task = Task { () -> [BibleReference: ScriptureCitation] in
                guard let quoted = try? await service.passages(for: batch) else { return [:] }
                let passages = quoted.passages.filter { batch.contains($0.key) && !$0.value.isEmpty }
                cache?.store(passages, translation: quoted.translation)
                var fetched: [BibleReference: ScriptureCitation] = [:]
                for (reference, text) in passages {
                    fetched[reference] = ScriptureCitation(id: UUID(), reference: reference.description,
                                                          translation: quoted.translation, passage: text)
                }
                return fetched
            }
            for reference in batch { pending[reference] = task }
        }
        // Capture all tasks before the first await; another caller may finish and remove them.
        let waiting = references.compactMap { reference in pending[reference].map { (reference, $0) } }
        for (reference, task) in waiting {
            results[reference] = await task.value[reference]
        }
        // Only the caller that registered a batch removes it.
        for reference in missing { pending[reference] = nil }
        return results
    }
}
