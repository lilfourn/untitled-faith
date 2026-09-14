import Foundation

// SSE uses CR/LF framing. Unicode separators inside JSON strings are content.
// Bound the raw bytes before buffering or decoding a potentially unterminated line.
struct AnswerStreamLines {
    private var buffer = Data()
    private var receivedBytes = 0
    private var skipLF = false

    mutating func consume(_ byte: UInt8) throws -> String? {
        receivedBytes += 1
        guard receivedBytes <= 512 * 1024 else { throw AnswerStreamFailure(reason: "stream_size") }
        if skipLF {
            skipLF = false
            if byte == 10 { return nil }
        }
        if byte == 10 || byte == 13 {
            skipLF = byte == 13
            guard let line = String(data: buffer, encoding: .utf8) else {
                throw AnswerStreamFailure(reason: "invalid_utf8")
            }
            buffer.removeAll(keepingCapacity: true)
            return line
        }
        buffer.append(byte)
        return nil
    }
}

struct AnswerStreamFailure: LocalizedError {
    let reason: String
    var errorDescription: String? {
        reason == "incomplete_stream"
            ? "The answer connection ended before it finished. Your question is saved; please retry."
            : AnswerServiceError.invalidResponse.errorDescription
    }
}
