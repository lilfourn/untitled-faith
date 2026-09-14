import Foundation
import OSLog

extension ProxyAnswerService {
    func streamAnswer(for messages: [ChatMessage],
                      onUpdate: @escaping @MainActor (String) -> Void) async throws -> FaithAnswer {
        let request = try await makeRequest(messages, accept: "text/event-stream")
        var parser = AnswerEventParser()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
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
            var lines = AnswerStreamLines()
            var lastUpdate = Date.distantPast
            for try await byte in bytes {
                try Task.checkCancellation()
                guard let line = try lines.consume(byte) else { continue }
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
            throw AnswerStreamFailure(reason: "incomplete_stream")
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? AnswerServiceError.timedOut : AnswerServiceError.unavailable
        } catch {
            if !(error is CancellationError) {
                let reason = (error as? AnswerStreamFailure)?.reason ?? "answer_service"
                let requestID = parser.requestID?.uuidString ?? "unknown"
                Logger(subsystem: "com.lukefournier.UntitledFaith", category: "AnswerStream")
                    .error("Answer failed request=\(requestID, privacy: .public) reason=\(reason, privacy: .public)")
            }
            throw error
        }
    }
}

// The proxy emits one JSON data line per event. Partial answers are never marked complete on EOF.
struct AnswerEventParser {
    enum Event { case text(String), done(FaithAnswer) }
    private(set) var text = ""
    private(set) var requestID: UUID?
    private var receivedBytes = 0
    private var started = false
    private var finished = false

    mutating func consume(_ line: String) throws -> Event? {
        receivedBytes += line.utf8.count
        guard receivedBytes <= 512 * 1024, !finished else { throw AnswerStreamFailure(reason: "event_limit_or_finished") }
        guard line.hasPrefix("data:") else { return nil }
        let data = Data(line.dropFirst(5).utf8)
        guard let event = try? JSONDecoder().decode(Payload.self, from: data) else { throw AnswerStreamFailure(reason: "event_json") }
        switch event.type {
        case "start":
            guard !started else { throw AnswerStreamFailure(reason: "duplicate_start") }
            requestID = event.requestID.flatMap(UUID.init(uuidString:))
            started = true
            return nil
        case "delta":
            guard started, let delta = event.text, text.utf16.count + delta.utf16.count <= 8000 else {
                throw AnswerStreamFailure(reason: "delta_sequence_or_length")
            }
            text += delta
            return .text(text)
        case "done":
            guard started, let answer = event.answer, answer.text == text else { throw AnswerStreamFailure(reason: "completion_mismatch") }
            let result: FaithAnswer
            do { result = try answer.validatedAnswer() }
            catch { throw AnswerStreamFailure(reason: "answer_payload") }
            finished = true
            return .done(result)
        case "error":
            if event.error?.status == 429 { throw AnswerServiceError.rateLimited }
            switch event.error?.code {
            case "invalid_answer_format": throw AnswerStreamFailure(reason: "server_answer_format")
            case "sources_unavailable": throw AnswerServiceError.sourcesUnavailable
            case "rate_limited": throw AnswerServiceError.rateLimited
            case "answer_timeout": throw AnswerServiceError.timedOut
            default: throw AnswerServiceError.unavailable
            }
        default: throw AnswerStreamFailure(reason: "unknown_event")
        }
    }

    private struct Payload: Decodable {
        let type: String
        let requestID: String?
        let text: String?
        let answer: AnswerPayload?
        let error: Failure?
        struct Failure: Decodable {
            let code: String
            let status: Int?
        }
    }
}
