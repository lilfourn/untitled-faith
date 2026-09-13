import Foundation

/// Reconciles fetched verse cards with the verified cards already embedded in the answer.
enum AnswerScripture {
    static func adding(_ citations: [ScriptureCitation], to answer: FaithAnswer) -> FaithAnswer {
        FaithAnswer(text: answer.text, scripture: answer.scripture + citations, commentary: answer.commentary,
                    isComplete: answer.isComplete, sources: answer.sources, quotes: answer.quotes)
    }

    static func quotedReferences(in answer: FaithAnswer) -> [BibleReference] {
        (answer.quotes ?? []).flatMap { quote -> [BibleReference] in
            guard answer.sources?.contains(where: { $0.id == quote.sourceID && $0.kind == .scripture }) == true else { return [] }
            return ScriptureReferenceDetector.references(in: quote.attribution)
        }
    }

    static func missingReferences(in answer: FaithAnswer) -> [BibleReference] {
        let covered = quotedReferences(in: answer) + answer.scripture.compactMap { BibleReference.parse($0.reference) }
        return ScriptureReferenceDetector.references(in: answer.text).filter { reference in
            !covered.contains { contains($0, reference) }
        }
    }

    static func supplementalCards(in answer: FaithAnswer) -> [ScriptureCitation] {
        let quoted = quotedReferences(in: answer)
        var seen: Set<String> = []
        return answer.scripture.filter { citation in
            guard let reference = BibleReference.parse(citation.reference) else {
                return seen.insert(citation.reference + ":" + citation.translation).inserted
            }
            guard !quoted.contains(where: { contains($0, reference) }) else { return false }
            return seen.insert("\(reference.idRange):\(citation.translation.uppercased())").inserted
        }
    }

    static func contains(_ passage: BibleReference, _ reference: BibleReference) -> Bool {
        passage.idRange.lowerBound <= reference.idRange.lowerBound && passage.idRange.upperBound >= reference.idRange.upperBound
    }
}
