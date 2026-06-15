import XCTest
@testable import Oat

// MARK: - URLProtocol mock

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func mockSession(_ handler: @escaping (URLRequest) throws -> (URLResponse, Data)) -> URLSession {
    MockURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func httpResponse(status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: status,
        httpVersion: nil,
        headerFields: nil
    )!
}

// MARK: - NoteEngineError

final class NoteEngineErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertTrue(NoteEngineError.missingAPIKey.errorDescription!.contains("API key"))
        XCTAssertTrue(NoteEngineError.invalidResponse.errorDescription!.contains("Unexpected"))
        XCTAssertTrue(NoteEngineError.api(status: 429, message: "rate limit").errorDescription!.contains("429"))
        XCTAssertTrue(NoteEngineError.unavailable.errorDescription!.contains("macOS 26"))
    }
}

// MARK: - NotePrompt

final class NotePromptTests: XCTestCase {
    func testBuildWithTemplate() {
        let template = Template(id: 1, name: "Test", systemPrompt: "CUSTOM", outputSchema: nil)
        let prompt = NotePrompt.build(rawNotes: "notes", transcript: "full transcript", template: template)
        XCTAssertEqual(prompt.system, "CUSTOM")
        XCTAssertTrue(prompt.user.contains("notes"))
        XCTAssertTrue(prompt.user.contains("full transcript"))
    }

    func testBuildWithoutTemplateUsesDefaultPrompt() {
        let prompt = NotePrompt.build(rawNotes: "notes", transcript: "", template: nil)
        XCTAssertFalse(prompt.system.isEmpty)
        XCTAssertTrue(prompt.user.contains("No transcript available"))
    }

    func testBuildWithEmptyNotesShowsPlaceholder() {
        let prompt = NotePrompt.build(rawNotes: "", transcript: "tx", template: nil)
        XCTAssertTrue(prompt.user.contains("(none)"))
    }
}

// MARK: - UnimplementedNoteEngine

final class UnimplementedNoteEngineTests: XCTestCase {
    func testEnhanceEchoesRawNotes() async throws {
        let engine = UnimplementedNoteEngine()
        let result = try await engine.enhance(rawNotes: "my notes", transcript: "tx", template: nil)
        XCTAssertEqual(result, "my notes")
    }
}

// MARK: - ClaudeNoteEngine

final class ClaudeNoteEngineTests: XCTestCase {
    func testQualityModels() {
        XCTAssertEqual(ClaudeNoteEngine.Quality.fast.model, "claude-haiku-4-5")
        XCTAssertEqual(ClaudeNoteEngine.Quality.best.model, "claude-sonnet-4-6")
    }

    func testEmptyAPIKeyThrowsMissingKey() async {
        let engine = ClaudeNoteEngine(apiKey: "")
        do {
            _ = try await engine.enhance(rawNotes: "notes", transcript: "", template: nil)
            XCTFail("Expected missingAPIKey error")
        } catch NoteEngineError.missingAPIKey {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSuccessfulResponseDecodesText() async throws {
        let json = """
        {"content":[{"type":"text","text":"Clean"},{"type":"image"},{"type":"text","text":" notes"}]}
        """
        let session = mockSession { _ in
            (httpResponse(status: 200), json.data(using: .utf8)!)
        }
        var engine = ClaudeNoteEngine(apiKey: "sk-test")
        engine.urlSession = session
        let result = try await engine.enhance(rawNotes: "rough", transcript: "tx", template: nil)
        XCTAssertEqual(result, "Clean notes")
    }

    func testHTTPErrorThrowsAPIError() async {
        let session = mockSession { _ in
            (httpResponse(status: 500), "Internal error".data(using: .utf8)!)
        }
        var engine = ClaudeNoteEngine(apiKey: "sk-test")
        engine.urlSession = session
        do {
            _ = try await engine.enhance(rawNotes: "", transcript: "", template: nil)
            XCTFail("Expected api error")
        } catch NoteEngineError.api(let status, _) {
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async {
        let session = mockSession { request in
            let plain = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (plain, Data())
        }
        var engine = ClaudeNoteEngine(apiKey: "sk-test")
        engine.urlSession = session
        do {
            _ = try await engine.enhance(rawNotes: "", transcript: "", template: nil)
            XCTFail("Expected invalidResponse error")
        } catch NoteEngineError.invalidResponse {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - AppleNoteEngine

final class AppleNoteEngineTests: XCTestCase {
    func testEnhanceDoesNotCrash() async {
        // On macOS < 26 (or without Apple Intelligence) this throws .unavailable.
        // On macOS 26+ it may succeed or throw a Foundation Models error.
        // Either outcome is acceptable — we just verify no unexpected crash.
        let engine = AppleNoteEngine()
        do {
            _ = try await engine.enhance(rawNotes: "notes", transcript: "tx", template: nil)
        } catch NoteEngineError.unavailable {
            // expected on CI (macOS < 26)
        } catch {
            // Foundation Models errors are also acceptable on macOS 26+
        }
    }
}

// MARK: - NoteEngineFactory

final class NoteEngineFactoryTests: XCTestCase {
    func testPrivacyModeReturnsAppleEngine() {
        let engine = NoteEngineFactory.make(privacyMode: true, provider: .cloud)
        XCTAssertTrue(engine is AppleNoteEngine)
    }

    func testLocalProviderReturnsAppleEngine() {
        let engine = NoteEngineFactory.make(privacyMode: false, provider: .local)
        XCTAssertTrue(engine is AppleNoteEngine)
    }

    func testCloudProviderReturnsClaudeEngine() {
        let engine = NoteEngineFactory.make(privacyMode: false, provider: .cloud)
        XCTAssertTrue(engine is ClaudeNoteEngine)
    }
}
