import Foundation

/// Device cache for fetched passages, capped by verse count to honor Crossway's 500-verse storage limit.
/// Unused entries expire after `maxAge`; recently read text stays available offline.
final class PassageCache: @unchecked Sendable {
    struct Entry: Codable, Equatable {
        let translation: String
        let text: String
        let verses: Int
        var used: Date
    }

    let fileURL: URL
    let verseLimit: Int
    private let maxAge: TimeInterval
    private var entries: [String: Entry]
    private let lock = NSLock()

    init(directory: URL, verseLimit: Int = 500, maxAge: TimeInterval = 30 * 24 * 3600) {
        fileURL = directory.appendingPathComponent("passages.json")
        self.verseLimit = verseLimit
        self.maxAge = maxAge
        let saved = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let cutoff = Date().addingTimeInterval(-maxAge)
        entries = saved.filter { $0.value.used >= cutoff }
    }

    var storedVerses: Int {
        lock.lock()
        defer { lock.unlock() }
        return verseTotal
    }

    private var verseTotal: Int { entries.values.reduce(0) { $0 + $1.verses } }

    /// Only standalone ESV verses are suitable for the home carousel.
    func randomVerse(excluding reference: String) -> ScriptureCitation? {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-maxAge)
        let candidates = entries.filter { key, entry in
            guard key != reference, entry.translation == "ESV", entry.used >= cutoff,
                  let parsed = BibleReference.parse(key) else { return false }
            return parsed.verse != nil && parsed.endVerse == nil && parsed.endChapter == nil
        }
        guard let selected = candidates.randomElement() else { return nil }
        entries[selected.key]?.used = Date()
        return ScriptureCitation(id: UUID(), reference: selected.key,
                                 translation: selected.value.translation, passage: selected.value.text)
    }

    func passage(for reference: BibleReference) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[reference.description], entry.used >= Date().addingTimeInterval(-maxAge) else { return nil }
        entry.used = Date()
        entries[reference.description] = entry
        return entry
    }

    func store(_ text: String, translation: String, for reference: BibleReference) {
        store([reference: text], translation: translation)
    }

    /// Persist a network batch with one atomic write instead of rewriting the file per verse.
    func store(_ passages: [BibleReference: String], translation: String) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        entries = entries.filter { $0.value.used >= now.addingTimeInterval(-maxAge) }
        for (reference, text) in passages where !text.isEmpty {
            let verses = max(1, Self.verseCount(in: text))
            guard verses <= verseLimit else { continue }
            entries[reference.description] = Entry(translation: translation, text: text, verses: verses, used: now)
        }
        while verseTotal > verseLimit, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
            entries.removeValue(forKey: oldest.key)
        }
        save()
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries = [:]
        save()
    }

    /// Multi-verse passages carry superscript verse numbers; single verses carry none.
    static func verseCount(in text: String) -> Int {
        text.split(whereSeparator: { !"⁰¹²³⁴⁵⁶⁷⁸⁹".contains($0) }).count
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            // The cache is an optimization; failures fall back to fetching again.
        }
    }
}
