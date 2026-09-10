import Foundation

extension ProxyAnswerService {
    func streamAnswer(for messages: [ChatMessage],
                      onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer {
        let request = try await makeRequest(messages, accept: "text/event-stream")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw AnswerServiceError.invalidResponse }
            guard response.statusCode == 200 else {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    data.append(byte)
                    if data.count > 16 * 1024 { break }
                }
                throw Self.failure(status: response.statusCode, data: data)
            }
            guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
                throw AnswerServiceError.invalidResponse
            }
            var parser = AnswerEventParser()
            var lastUpdate = Date.distantPast
            // URLSession's lines sequence handles UTF-8 characters and network chunk boundaries.
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let event = try parser.consume(line) else { continue }
                switch event {
                case .text(let text):
                    if Date().timeIntervalSince(lastUpdate) >= 0.04 {
                        await onUpdate(text)
                        lastUpdate = Date()
                    }
                case .done(let answer):
                    await onUpdate(answer.text)
                    return answer
                }
            }
            throw AnswerServiceError.invalidResponse
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? AnswerServiceError.timedOut : AnswerServiceError.unavailable
        }
    }
}

// The proxy emits one JSON data line per event. Partial answers are never marked complete on EOF.
struct AnswerEventParser {
    enum Event { case text(String), done(FaithAnswer) }
    private(set) var text = ""
    private var receivedBytes = 0
    private var started = false
    private var finished = false

    mutating func consume(_ line: String) throws -> Event? {
        receivedBytes += line.utf8.count
        guard receivedBytes <= 512 * 1024, !finished else { throw AnswerServiceError.invalidResponse }
        guard line.hasPrefix("data:") else { return nil }
        let data = Data(line.dropFirst(5).utf8)
        guard let event = try? JSONDecoder().decode(Payload.self, from: data) else { throw AnswerServiceError.invalidResponse }
        switch event.type {
        case "start":
            guard !started else { throw AnswerServiceError.invalidResponse }
            started = true
            return nil
        case "delta":
            guard started, let delta = event.text, text.utf16.count + delta.utf16.count <= 8000 else {
                throw AnswerServiceError.invalidResponse
            }
            text += delta
            return .text(text)
        case "done":
            guard started, let answer = event.answer, answer.text == text else { throw AnswerServiceError.invalidResponse }
            let result = try answer.validatedAnswer()
            finished = true
            return .done(result)
        case "error":
            if event.error?.status == 429 { throw AnswerServiceError.rateLimited }
            switch event.error?.code {
            case "invalid_answer_format": throw AnswerServiceError.invalidResponse
            case "sources_unavailable": throw AnswerServiceError.sourcesUnavailable
            case "rate_limited": throw AnswerServiceError.rateLimited
            case "answer_timeout": throw AnswerServiceError.timedOut
            default: throw AnswerServiceError.unavailable
            }
        default: throw AnswerServiceError.invalidResponse
        }
    }

    private struct Payload: Decodable {
        let type: String
        let text: String?
        let answer: AnswerPayload?
        let error: Failure?
        struct Failure: Decodable {
            let code: String
            let status: Int?
        }
    }
}
