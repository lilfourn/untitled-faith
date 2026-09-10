import Foundation

/// The 66 books of the Protestant canon in canonical order. `id` matches the bundled database.
struct BibleBook: Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    /// Alternate names and abbreviations accepted when parsing references (lowercase, no periods).
    let aliases: [String]

    static func named(_ text: String) -> BibleBook? {
        lookup[normalize(text)]
    }

    /// Lowercases, drops periods, collapses whitespace, and separates a leading ordinal ("1john" → "1 john").
    static func normalize(_ text: String) -> String {
        var key = text.lowercased().replacingOccurrences(of: ".", with: "")
        key = key.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let first = key.first, first.isNumber, key.dropFirst().first?.isLetter == true {
            key.insert(" ", at: key.index(after: key.startIndex))
        }
        return key
    }

    private static let lookup: [String: BibleBook] = {
        var table: [String: BibleBook] = [:]
        for book in all {
            table[book.name.lowercased()] = book
            for alias in book.aliases { table[alias] = book }
        }
        return table
    }()

    static let all: [BibleBook] = [
        BibleBook(id: 1, name: "Genesis", aliases: ["gen", "ge", "gn"]),
        BibleBook(id: 2, name: "Exodus", aliases: ["exod", "exo", "ex"]),
        BibleBook(id: 3, name: "Leviticus", aliases: ["lev", "le", "lv"]),
        BibleBook(id: 4, name: "Numbers", aliases: ["num", "nu", "nm", "nb"]),
        BibleBook(id: 5, name: "Deuteronomy", aliases: ["deut", "deu", "dt", "de"]),
        BibleBook(id: 6, name: "Joshua", aliases: ["josh", "jos", "jsh"]),
        BibleBook(id: 7, name: "Judges", aliases: ["judg", "jdg", "jdgs", "jg"]),
        BibleBook(id: 8, name: "Ruth", aliases: ["rth", "ru"]),
        BibleBook(id: 9, name: "1 Samuel", aliases: ["1 sam", "1 sa", "1 sm", "i samuel", "i sam", "first samuel"]),
        BibleBook(id: 10, name: "2 Samuel", aliases: ["2 sam", "2 sa", "2 sm", "ii samuel", "ii sam", "second samuel"]),
        BibleBook(id: 11, name: "1 Kings", aliases: ["1 kgs", "1 ki", "1 kin", "i kings", "i kgs", "first kings"]),
        BibleBook(id: 12, name: "2 Kings", aliases: ["2 kgs", "2 ki", "2 kin", "ii kings", "ii kgs", "second kings"]),
        BibleBook(id: 13, name: "1 Chronicles", aliases: ["1 chron", "1 chr", "1 ch", "i chronicles", "i chr", "first chronicles"]),
        BibleBook(id: 14, name: "2 Chronicles", aliases: ["2 chron", "2 chr", "2 ch", "ii chronicles", "ii chr", "second chronicles"]),
        BibleBook(id: 15, name: "Ezra", aliases: ["ezr"]),
        BibleBook(id: 16, name: "Nehemiah", aliases: ["neh", "ne"]),
        BibleBook(id: 17, name: "Esther", aliases: ["esth", "est", "es"]),
        BibleBook(id: 18, name: "Job", aliases: ["jb"]),
        BibleBook(id: 19, name: "Psalm", aliases: ["psalms", "psa", "pss", "psm", "pslm", "ps"]),
        BibleBook(id: 20, name: "Proverbs", aliases: ["prov", "pro", "prv", "pr"]),
        BibleBook(id: 21, name: "Ecclesiastes", aliases: ["eccl", "ecc", "ec", "qoh", "qoheleth"]),
        BibleBook(id: 22, name: "Song of Solomon", aliases: ["song of songs", "song", "sos", "canticles", "cant", "sng"]),
        BibleBook(id: 23, name: "Isaiah", aliases: ["isa"]),
        BibleBook(id: 24, name: "Jeremiah", aliases: ["jer", "je", "jr"]),
        BibleBook(id: 25, name: "Lamentations", aliases: ["lam", "la"]),
        BibleBook(id: 26, name: "Ezekiel", aliases: ["ezek", "eze", "ezk"]),
        BibleBook(id: 27, name: "Daniel", aliases: ["dan", "da", "dn"]),
        BibleBook(id: 28, name: "Hosea", aliases: ["hos", "ho"]),
        BibleBook(id: 29, name: "Joel", aliases: ["jl"]),
        BibleBook(id: 30, name: "Amos", aliases: ["amo"]),
        BibleBook(id: 31, name: "Obadiah", aliases: ["obad", "oba", "ob"]),
        BibleBook(id: 32, name: "Jonah", aliases: ["jon", "jnh"]),
        BibleBook(id: 33, name: "Micah", aliases: ["mic", "mc"]),
        BibleBook(id: 34, name: "Nahum", aliases: ["nah", "na"]),
        BibleBook(id: 35, name: "Habakkuk", aliases: ["hab", "hb"]),
        BibleBook(id: 36, name: "Zephaniah", aliases: ["zeph", "zep", "zp"]),
        BibleBook(id: 37, name: "Haggai", aliases: ["hag", "hg"]),
        BibleBook(id: 38, name: "Zechariah", aliases: ["zech", "zec", "zc"]),
        BibleBook(id: 39, name: "Malachi", aliases: ["mal", "ml"]),
        BibleBook(id: 40, name: "Matthew", aliases: ["matt", "mat", "mt"]),
        BibleBook(id: 41, name: "Mark", aliases: ["mrk", "mk", "mr"]),
        BibleBook(id: 42, name: "Luke", aliases: ["luk", "lk"]),
        BibleBook(id: 43, name: "John", aliases: ["jhn", "joh", "jn"]),
        BibleBook(id: 44, name: "Acts", aliases: ["act", "ac"]),
        BibleBook(id: 45, name: "Romans", aliases: ["rom", "ro", "rm"]),
        BibleBook(id: 46, name: "1 Corinthians", aliases: ["1 cor", "1 co", "i corinthians", "i cor", "first corinthians"]),
        BibleBook(id: 47, name: "2 Corinthians", aliases: ["2 cor", "2 co", "ii corinthians", "ii cor", "second corinthians"]),
        BibleBook(id: 48, name: "Galatians", aliases: ["gal", "ga"]),
        BibleBook(id: 49, name: "Ephesians", aliases: ["eph", "ep"]),
        BibleBook(id: 50, name: "Philippians", aliases: ["phil", "php", "philip", "pp"]),
        BibleBook(id: 51, name: "Colossians", aliases: ["col", "co"]),
        BibleBook(id: 52, name: "1 Thessalonians", aliases: ["1 thess", "1 thes", "1 th", "i thessalonians", "i thess", "first thessalonians"]),
        BibleBook(id: 53, name: "2 Thessalonians", aliases: ["2 thess", "2 thes", "2 th", "ii thessalonians", "ii thess", "second thessalonians"]),
        BibleBook(id: 54, name: "1 Timothy", aliases: ["1 tim", "1 ti", "i timothy", "i tim", "first timothy"]),
        BibleBook(id: 55, name: "2 Timothy", aliases: ["2 tim", "2 ti", "ii timothy", "ii tim", "second timothy"]),
        BibleBook(id: 56, name: "Titus", aliases: ["tit", "ti"]),
        BibleBook(id: 57, name: "Philemon", aliases: ["philem", "phlm", "phm", "pm"]),
        BibleBook(id: 58, name: "Hebrews", aliases: ["heb"]),
        BibleBook(id: 59, name: "James", aliases: ["jas", "jm"]),
        BibleBook(id: 60, name: "1 Peter", aliases: ["1 pet", "1 pe", "1 pt", "i peter", "i pet", "first peter"]),
        BibleBook(id: 61, name: "2 Peter", aliases: ["2 pet", "2 pe", "2 pt", "ii peter", "ii pet", "second peter"]),
        BibleBook(id: 62, name: "1 John", aliases: ["1 jn", "1 jhn", "1 jo", "i john", "i jn", "first john"]),
        BibleBook(id: 63, name: "2 John", aliases: ["2 jn", "2 jhn", "2 jo", "ii john", "ii jn", "second john"]),
        BibleBook(id: 64, name: "3 John", aliases: ["3 jn", "3 jhn", "3 jo", "iii john", "iii jn", "third john"]),
        BibleBook(id: 65, name: "Jude", aliases: ["jud", "jd"]),
        BibleBook(id: 66, name: "Revelation", aliases: ["rev", "revelations", "revelation of john", "apocalypse", "re"])
    ]
}
