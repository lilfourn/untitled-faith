import Foundation

/// Device cache for fetched passages, capped by verse count to honor Crossway's 500-verse storage limit.
/// Entries expire after `maxAge` so refreshed text reaches the app.
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

    var storedVerses: Int { entries.values.reduce(0) { $0 + $1.verses } }

    func passage(for reference: BibleReference) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[reference.description] else { return nil }
        entry.used = Date()
        entries[reference.description] = entry
        return entry
    }

    func store(_ text: String, translation: String, for reference: BibleReference) {
        lock.lock()
        defer { lock.unlock() }
        let verses = max(1, Self.verseCount(in: text))
        guard verses <= verseLimit else { return }
        entries[reference.description] = Entry(translation: translation, text: text, verses: verses, used: Date())
        while storedVerses > verseLimit, let oldest = entries.min(by: { $0.value.used < $1.value.used }) {
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
