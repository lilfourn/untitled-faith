import Foundation

/// Display-only deduplication. Keep all original sources for quote IDs and verified link destinations.
enum AnswerSourceList {
    static func unique(_ sources: [AnswerSource], quotes: [AnswerQuote] = []) -> [AnswerSource] {
        var seen: Set<String> = []
        return sources.filter { seen.insert(key(for: $0, quotes: quotes)).inserted }
    }

    private static func key(for source: AnswerSource, quotes: [AnswerQuote]) -> String {
        if source.kind == .scripture, let passage = scriptureIdentity(source) {
            let references = Set(quotes.filter { $0.sourceID == source.id }
                .flatMap { ScriptureReferenceDetector.references(in: $0.attribution) })
            // A verse can be quoted from a whole-chapter URL as well as a verse-specific URL.
            let reference = references.count == 1 && references.first.map({ AnswerScripture.contains(passage.reference, $0) }) == true
                ? references.first! : passage.reference
            return "scripture:\(reference.idRange):\(passage.translation)"
        }
        var url = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
        let host = url?.host?.lowercased().replacingOccurrences(of: "www.", with: "", options: .anchored)
        url?.host = host
        url?.fragment = nil
        if let path = url?.path, path.hasSuffix("/") { url?.path = String(path.dropLast()) }
        let query = url?.queryItems?.sorted { ($0.name, $0.value ?? "") < ($1.name, $1.value ?? "") }
        url?.queryItems = query
        return "\(source.kind.rawValue):\(url?.string ?? source.url.absoluteString)"
    }

    private static func scriptureIdentity(_ source: AnswerSource) -> (reference: BibleReference, translation: String)? {
        let url = URLComponents(url: source.url, resolvingAgainstBaseURL: false)
        let host = url?.host?.lowercased().replacingOccurrences(of: "www.", with: "", options: .anchored)
        let path = (url?.path ?? "").replacingOccurrences(of: "+", with: " ")
        var reference: BibleReference?
        var translation: String?
        switch host {
        case "esv.org":
            let references = ScriptureReferenceDetector.references(in: path)
            guard references.count <= 1 else { return nil }
            reference = references.first
            translation = "ESV"
        case "biblegateway.com":
            let query = url?.queryItems?.first(where: { $0.name == "search" })?.value
            if let query { reference = BibleReference.parse(query.replacingOccurrences(of: "+", with: " ")) }
            translation = url?.queryItems?.first(where: { $0.name == "version" })?.value?.uppercased()
        case "bible.com":
            let components = path.split(separator: "/").map(String.init)
            if let bible = components.firstIndex(of: "bible"), components.count > bible + 2 {
                translation = ["59": "ESV", "3034": "BSB"][components[bible + 1]]
                let passage = components[bible + 2].split(separator: ".").map(String.init)
                if passage.count >= 2, let book = BibleBook.named(passage[0]) {
                    let location = passage.dropFirst().prefix(while: { $0.first?.isNumber == true }).joined(separator: ":")
                    reference = BibleReference.parse(book.name + " " + location)
                }
            }
        default: break
        }
        if reference == nil {
            let references = ScriptureReferenceDetector.references(in: source.title)
            if references.count == 1 { reference = references[0] }
        }
        if translation == nil,
           let range = source.title.range(of: #"\b(?:ESV|BSB|KJV|NKJV|NIV|NASB|NLT|CSB|NRSV|RSV)\b"#, options: [.regularExpression, .caseInsensitive]) {
            translation = String(source.title[range]).uppercased()
        }
        guard let reference, let translation else { return nil }
        return (reference, translation)
    }
}
