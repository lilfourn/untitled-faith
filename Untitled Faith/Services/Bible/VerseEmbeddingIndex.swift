import Accelerate
import Foundation
import NaturalLanguage

/// On-device semantic search over verses using Apple's sentence embeddings. Build once from a
/// `BibleStore`, write the result next to the app's data, and read it back on later launches.
/// Queries never leave the device.
final class VerseEmbeddingIndex: @unchecked Sendable {
    struct Match: Hashable, Sendable {
        let reference: BibleReference
        let score: Float
    }

    private let embedding: NLEmbedding
    let dimension: Int
    private(set) var ids: [Int64] = []
    /// `ids.count × dimension` unit vectors stored as IEEE half floats.
    private var vectors = Data()

    /// `nil` when the system has no sentence embedding for the language.
    init?(language: NLLanguage = .english) {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
        self.embedding = embedding
        dimension = embedding.dimension
    }

    var count: Int { ids.count }

    /// Cache location keyed by translation and embedding revision, so OS model updates trigger a rebuild.
    static func cacheURL(translation: String, language: NLLanguage = .english, directory: URL) -> URL {
        let revision = NLEmbedding.currentSentenceEmbeddingRevision(for: language)
        return directory.appendingPathComponent("verse-index-\(translation)-r\(revision).bin")
    }

    func index(_ verses: [BibleVerse]) {
        var ids: [Int64] = []
        var halves: [UInt16] = []
        ids.reserveCapacity(verses.count)
        halves.reserveCapacity(verses.count * dimension)
        for verse in verses {
            guard let vector = unitVector(for: verse.text) else { continue }
            ids.append(Int64(BibleReference.id(book: verse.reference.book, chapter: verse.reference.chapter, verse: verse.reference.verse ?? 0)))
            halves.append(contentsOf: Self.halves(from: vector))
        }
        self.ids = ids
        vectors = halves.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func write(to url: URL) throws {
        var data = Data()
        data.append(contentsOf: Array("UFVX".utf8))
        for value in [UInt32(1), UInt32(dimension), UInt32(ids.count)] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        ids.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        data.append(vectors)
        try data.write(to: url, options: .atomic)
    }

    func read(from url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        let header = 16
        guard data.count >= header, data.prefix(4) == Data("UFVX".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        let fields: [UInt32] = (0..<3).map { field in
            data.subdata(in: 4 + field * 4..<8 + field * 4).withUnsafeBytes { UInt32(littleEndian: $0.load(as: UInt32.self)) }
        }
        let count = Int(fields[2])
        guard fields[0] == 1, Int(fields[1]) == dimension,
              data.count == header + count * 8 + count * dimension * 2 else { throw CocoaError(.fileReadCorruptFile) }
        ids = data.subdata(in: header..<header + count * 8).withUnsafeBytes { Array($0.bindMemory(to: Int64.self)) }
        vectors = data.subdata(in: header + count * 8..<data.count)
    }

    /// Nearest verses by cosine similarity.
    func search(_ query: String, limit: Int = 10) -> [Match] {
        guard !ids.isEmpty, let queryVector = unitVector(for: query) else { return [] }
        let rows = ids.count
        var scores = [Float](repeating: 0, count: rows)
        let chunk = 2048
        var floats = [Float](repeating: 0, count: chunk * dimension)
        vectors.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            var start = 0
            while start < rows {
                let n = min(chunk, rows - start)
                let elements = n * dimension
                var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: base + start * dimension * 2),
                                           height: 1, width: vImagePixelCount(elements), rowBytes: elements * 2)
                floats.withUnsafeMutableBufferPointer { buffer in
                    var destination = vImage_Buffer(data: buffer.baseAddress, height: 1, width: vImagePixelCount(elements), rowBytes: elements * 4)
                    vImageConvert_Planar16FtoPlanarF(&source, &destination, vImage_Flags(kvImageNoFlags))
                    scores.withUnsafeMutableBufferPointer { output in
                        vDSP_mmul(buffer.baseAddress!, 1, queryVector, 1, output.baseAddress! + start, 1,
                                  vDSP_Length(n), 1, vDSP_Length(dimension))
                    }
                }
                start += n
            }
        }
        let best = scores.indices.sorted { scores[$0] > scores[$1] }.prefix(limit)
        return best.compactMap { row in
            BibleReference.from(id: Int(ids[row])).map { Match(reference: $0, score: scores[row]) }
        }
    }

    private func unitVector(for text: String) -> [Float]? {
        guard let vector = embedding.vector(for: text) else { return nil }
        var floats = vector.map(Float.init)
        var norm: Float = 0
        vDSP_svesq(floats, 1, &norm, vDSP_Length(floats.count))
        guard norm > 0 else { return nil }
        var scale = 1 / norm.squareRoot()
        vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(floats.count))
        return floats
    }

    private static func halves(from floats: [Float]) -> [UInt16] {
        var input = floats
        var output = [UInt16](repeating: 0, count: floats.count)
        input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                var sourceBuffer = vImage_Buffer(data: source.baseAddress, height: 1, width: vImagePixelCount(floats.count), rowBytes: floats.count * 4)
                var destinationBuffer = vImage_Buffer(data: destination.baseAddress, height: 1, width: vImagePixelCount(floats.count), rowBytes: floats.count * 2)
                vImageConvert_PlanarFtoPlanar16F(&sourceBuffer, &destinationBuffer, vImage_Flags(kvImageNoFlags))
            }
        }
        return output
    }
}
