import Foundation
import SQLite3

struct BibleTranslation: Hashable, Sendable {
    let id: String
    let name: String
    let license: String
    let notice: String
}

struct BibleVerse: Hashable, Sendable {
    let reference: BibleReference
    let text: String
}

enum BibleStoreError: LocalizedError {
    case cannotOpen(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let message): "The Bible database could not be opened: \(message)"
        case .query(let message): "The Bible database query failed: \(message)"
        }
    }
}

/// Read-only access to the bundled Bible built by `scripts/bible/build.py`. Exact quoting by reference and
/// FTS5 keyword or phrase search run entirely on the device.
final class BibleStore: @unchecked Sendable {
    let translation: BibleTranslation
    private let connection: OpaquePointer
    private let lock = NSLock()

    static let bundled: BibleStore? = {
        guard let url = Bundle.main.url(forResource: "Bible", withExtension: "sqlite") else { return nil }
        return try? BibleStore(url: url)
    }()

    init(url: URL) throws {
        var connection: OpaquePointer?
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        guard sqlite3_open_v2("file:\(encoded)?immutable=1", &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(connection)
            throw BibleStoreError.cannotOpen(message)
        }
        self.connection = connection
        let rows = try Self.rows(connection, "SELECT id, name, license, notice FROM translation LIMIT 1", bind: { _ in }) { statement in
            BibleTranslation(id: Self.text(statement, 0), name: Self.text(statement, 1),
                             license: Self.text(statement, 2), notice: Self.text(statement, 3))
        }
        guard let translation = rows.first else {
            sqlite3_close(connection)
            throw BibleStoreError.cannotOpen("missing translation metadata")
        }
        self.translation = translation
    }

    deinit { sqlite3_close(connection) }

    func verses(in reference: BibleReference) throws -> [BibleVerse] {
        let range = reference.idRange
        return try query("SELECT id, text FROM verses WHERE id BETWEEN ? AND ? ORDER BY id", bind: { statement in
            sqlite3_bind_int64(statement, 1, Int64(range.lowerBound))
            sqlite3_bind_int64(statement, 2, Int64(range.upperBound))
        })
    }

    /// Every verse in the complete Bible is eligible, except the last one shown.
    func randomVerse(excluding reference: BibleReference?) throws -> BibleVerse? {
        try query("SELECT id, text FROM verses WHERE id != ? ORDER BY RANDOM() LIMIT 1", bind: { statement in
            sqlite3_bind_int64(statement, 1, Int64(reference?.idRange.lowerBound ?? -1))
        }).first
    }

    /// Verbatim text; ranges carry superscript verse numbers. `nil` when no verse exists.
    func passage(_ reference: BibleReference) throws -> String? {
        let verses = try verses(in: reference)
        guard let first = verses.first else { return nil }
        if verses.count == 1 { return first.text }
        return verses.map { "\(Self.superscript($0.reference.verse ?? 0)) \($0.text)" }.joined(separator: " ")
    }

    func citation(_ reference: BibleReference) -> ScriptureCitation? {
        guard let passage = try? passage(reference) else { return nil }
        return ScriptureCitation(id: UUID(), reference: reference.description, translation: translation.id, passage: passage)
    }

    /// Verses containing every word, best matches first.
    func search(words: String, limit: Int = 20) throws -> [BibleVerse] {
        let tokens = words.split { !$0.isLetter && !$0.isNumber }.map { "\"\($0)\"" }
        guard !tokens.isEmpty else { return [] }
        return try fullText(tokens.joined(separator: " "), limit: limit)
    }

    /// Verses containing the exact phrase, best matches first.
    func search(phrase: String, limit: Int = 20) throws -> [BibleVerse] {
        let cleaned = phrase.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        return try fullText("\"\(cleaned)\"", limit: limit)
    }

    /// Every verse in canonical order, for building indexes.
    func allVerses() throws -> [BibleVerse] {
        try query("SELECT id, text FROM verses ORDER BY id", bind: { _ in })
    }

    private func fullText(_ match: String, limit: Int) throws -> [BibleVerse] {
        try query("""
            SELECT v.id, v.text FROM verses_fts f JOIN verses v ON v.id = f.rowid
            WHERE verses_fts MATCH ? ORDER BY bm25(verses_fts) LIMIT ?
            """, bind: { statement in
            sqlite3_bind_text(statement, 1, match, -1, Self.transient)
            sqlite3_bind_int(statement, 2, Int32(limit))
        })
    }

    private func query(_ sql: String, bind: (OpaquePointer) -> Void) throws -> [BibleVerse] {
        lock.lock()
        defer { lock.unlock() }
        return try Self.rows(connection, sql, bind: bind) { statement in
            BibleReference.from(id: Int(sqlite3_column_int64(statement, 0))).map { BibleVerse(reference: $0, text: Self.text(statement, 1)) }
        }.compactMap { $0 }
    }

    private static func rows<Row>(_ connection: OpaquePointer, _ sql: String, bind: (OpaquePointer) -> Void,
                                  read: (OpaquePointer) -> Row) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw BibleStoreError.query(String(cString: sqlite3_errmsg(connection)))
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        var rows: [Row] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: rows.append(read(statement))
            case SQLITE_DONE: return rows
            default: throw BibleStoreError.query(String(cString: sqlite3_errmsg(connection)))
            }
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func superscript(_ number: Int) -> String {
        let digits = Array("⁰¹²³⁴⁵⁶⁷⁸⁹")
        return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
