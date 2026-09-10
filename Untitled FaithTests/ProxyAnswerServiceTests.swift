import XCTest
@testable import Untitled_Faith

@MainActor
final class ProxyAnswerServiceTests: XCTestCase {
    private func service(consent: Bool = true, token: String = "test-session", status: Int = 200,
                         body: String = #"{"answer":{"text":"Test answer","scripture":[],"commentary":[]},"requestID":"test"}"#,
                         inspect: @escaping (URLRequest) -> Void = { _ in }) -> ProxyAnswerService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { request in
            inspect(request)
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        return ProxyAnswerService(endpoint: URL(string: "https://proxy.example/v1/answers")!,
                                  accessToken: { token }, hasConsent: { consent }, session: URLSession(configuration: config))
    }

    func testSendsOnlyConversationAndConsentToProxy() async throws {
        let client = service { request in
            XCTAssertEqual(request.url?.host, "proxy.example")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-session")
            XCTAssertNotNil(UUID(uuidString: request.value(forHTTPHeaderField: "Idempotency-Key") ?? ""))
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let data: Data
            if let body = request.httpBody {
                data = body
            } else {
                let stream = request.httpBodyStream!
                stream.open()
                defer { stream.close() }
                var result = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    result.append(contentsOf: buffer.prefix(count))
                }
                data = result
            }
            let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(Set(json.keys), ["messages", "consentVersion"])
            XCTAssertEqual(json["consentVersion"] as? String, ProxyAnswerService.consentVersion)
        }
        let result = try await client.answer(for: [.question(id: UUID(), text: "Hello")])
        XCTAssertEqual(result.text, "Test answer")
        XCTAssertTrue(result.scripture.isEmpty)
    }

    func testNoConsentOrSessionPreventsNetworking() async {
        for client in [service(consent: false), service(token: "")] {
            StubURLProtocol.handler = { _ in
                XCTFail("Request must not be sent")
                throw URLError(.badServerResponse)
            }
            do {
                _ = try await client.answer(for: [.question(id: UUID(), text: "Hello")])
                XCTFail("Expected an error")
            } catch {
                XCTAssertTrue(error is AnswerServiceError)
            }
        }
    }

    func testRejectsInsecureEndpointBeforeSending() async {
        let client = ProxyAnswerService(endpoint: URL(string: "http://proxy.example/v1/answers")!,
                                        accessToken: { XCTFail("Must reject URL before reading token"); return "" },
                                        hasConsent: { true })
        do {
            _ = try await client.answer(for: [.question(id: UUID(), text: "Hello")])
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error.localizedDescription, AnswerServiceError.invalidConfiguration.localizedDescription)
        }
    }

    func testMapsErrorsWithoutDisplayingServerDetails() async {
        for (status, expected) in [(401, AnswerServiceError.signInRequired), (402, .fundingRequired), (409, .requestConflict), (429, .rateLimited), (502, .unavailable), (504, .timedOut)] {
            do {
                _ = try await service(status: status, body: "private upstream metadata")
                    .answer(for: [.question(id: UUID(), text: "Hello")])
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
            }
        }
    }

    func testPreservesAllowanceFailureReasonsForJSONAndStreaming() async {
        for (code, expected) in [("daily_free_limit", AnswerServiceError.dailyFreeLimit),
                                 ("monthly_free_limit", .monthlyFreeLimit), ("free_pool_exhausted", .freePoolUnavailable)] {
            for stream in [false, true] {
                let client = service(status: 402, body: "{\"error\":{\"code\":\"\(code)\"}}")
                do {
                    let messages: [ChatMessage] = [.question(id: UUID(), text: "Question")]
                    if stream { _ = try await client.streamAnswer(for: messages) { _ in } }
                    else { _ = try await client.answer(for: messages) }
                    XCTFail("Expected allowance error")
                } catch {
                    XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
                }
            }
        }
    }

    func testRejectsMalformedAndUnverifiedAnswers() async {
        for body in [#"{"answer":{"text":"","scripture":[],"commentary":[]}}"#,
                     #"{"answer":{"text":"Answer","scripture":["unverified citation"],"commentary":[]}}"#,
                     "invalid JSON"] {
            do {
                _ = try await service(body: body).answer(for: [.question(id: UUID(), text: "Hello")])
                XCTFail("Expected an error")
            } catch {
                XCTAssertEqual(error.localizedDescription, AnswerServiceError.invalidResponse.localizedDescription)
            }
        }
    }

    func testPreservesWholeHistoryAndLatestQuestion() throws {
        var history: [ChatMessage] = []
        for index in 0..<20 {
            history.append(.question(id: UUID(), text: "Question \(index)"))
            history.append(.answer(id: UUID(), answer: FaithAnswer(text: String(repeating: "a", count: 4000), scripture: [], commentary: [])))
        }
        history.append(.question(id: UUID(), text: "Latest question"))
        let context = try ProxyAnswerService.context(from: history)
        XCTAssertEqual(context.first?.role, "user")
        XCTAssertEqual(context.last?.content, "Latest question")
        XCTAssertEqual(context.count, 41)
        XCTAssertEqual(context.first?.content, "Question 0")
        XCTAssertEqual(context[1].content, String(repeating: "a", count: 4000))
        XCTAssertEqual(history.count, 41)
    }

    func testOversizedQuestionKeepsDraft() async {
        let store = ChatStore(service: UnconfiguredAnswerService())
        store.draft = String(repeating: "a", count: 8001)
        await store.send()
        XCTAssertEqual(store.draft.count, 8001)
        XCTAssertTrue(store.conversation.messages.isEmpty)
        XCTAssertFalse(store.isSending)
        XCTAssertEqual(store.errorMessage, AnswerServiceError.questionTooLong.localizedDescription)
    }

    func testLoadsUsagePercentageThroughAuthenticatedAccountEndpoint() async throws {
        let body = #"{"month":"2026-09","resetsAt":"2026-10-01T00:00:00Z","remainingPercent":90,"currency":"USD","appAccountToken":"550e8400-e29b-41d4-a716-446655440000","free":{"dailyLimit":5,"monthlyLimit":30,"usedToday":3,"usedThisMonth":3,"remainingToday":2,"remainingThisMonth":27},"funding":{"balanceMicros":0,"reservedMicros":0,"availableMicros":0},"usage":{"totalRequests":3,"pendingRequests":0,"promptTokens":100,"completionTokens":200,"costMicros":2000}}"#
        let client = service(body: body) { request in
            XCTAssertEqual(request.url?.path, "/v1/me/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-session")
        }
        let result = try await AccountUsageService(baseURL: URL(string: "https://proxy.example")!, session: client.session)
            .load(accessToken: "account-session")
        XCTAssertEqual(result.remainingPercent, 90)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
