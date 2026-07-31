import Foundation
import HexCore
import XCTest
@testable import Hex
final class ProofreadingClientTests: XCTestCase {
  private let sampleText = "teh quick brown fox"
  private func makeConfiguration(
    baseURL: String = "http://192.168.1.50:11434",
    model: String = "test-model",
    timeout: TimeInterval = 12,
    apiKey: String? = nil
  ) -> ProofreadingProviderConfiguration {
    ProofreadingProviderConfiguration(
      baseURL: baseURL,
      model: model,
      requestTimeout: timeout,
      apiKey: apiKey
    )
  }
  // MARK: - HTTP construction
  func testMakeRequestBuildsChatCompletionsEndpoint() throws {
    let request = try OpenAIProofreadingProvider.makeRequest(
      configuration: makeConfiguration(),
      request: ProofreadingRequest(text: sampleText)
    )
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.50:11434/v1/chat/completions")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    XCTAssertEqual(request.timeoutInterval, 12)
  }
  func testMakeRequestToleratesTrailingSlashInBaseURL() throws {
    let request = try OpenAIProofreadingProvider.makeRequest(
      configuration: makeConfiguration(baseURL: "http://jetson.local:11434/"),
      request: ProofreadingRequest(text: sampleText)
    )
    XCTAssertEqual(request.url?.absoluteString, "http://jetson.local:11434/v1/chat/completions")
  }
  func testMakeRequestOmitsAuthorizationHeaderByDefault() throws {
    let request = try OpenAIProofreadingProvider.makeRequest(
      configuration: makeConfiguration(),
      request: ProofreadingRequest(text: sampleText)
    )
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
  }
  func testMakeRequestAddsBearerTokenWhenAPIKeyProvided() throws {
    let request = try OpenAIProofreadingProvider.makeRequest(
      configuration: makeConfiguration(apiKey: "secret-token"),
      request: ProofreadingRequest(text: sampleText)
    )
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
  }
  func testMakeRequestEmbedsModelAndTextInBody() throws {
    let request = try OpenAIProofreadingProvider.makeRequest(
      configuration: makeConfiguration(),
      request: ProofreadingRequest(text: sampleText)
    )
    let body = try XCTUnwrap(request.httpBody)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(object["model"] as? String, "test-model")
    let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages.first?["role"] as? String, "system")
    XCTAssertEqual(messages.last?["role"] as? String, "user")
    XCTAssertEqual(messages.last?["content"] as? String, sampleText)
  }
  func testMakeRequestRejectsUnconfiguredModel() {
    XCTAssertThrowsError(
      try OpenAIProofreadingProvider.makeRequest(
        configuration: makeConfiguration(model: ""),
        request: ProofreadingRequest(text: sampleText)
      )
    ) { error in
      XCTAssertEqual(error as? ProofreadingClientError, .notConfigured)
    }
  }
  func testMakeRequestRejectsInvalidBaseURL() {
    XCTAssertThrowsError(
      try OpenAIProofreadingProvider.makeRequest(
        configuration: makeConfiguration(baseURL: "ht tp://bad url"),
        request: ProofreadingRequest(text: sampleText)
      )
    ) { error in
      XCTAssertEqual(error as? ProofreadingClientError, .invalidBaseURL("ht tp://bad url"))
    }
  }
  // MARK: - Response parsing
  private func chatCompletionData(content: String) -> Data {
    let object: [String: Any] = [
      "choices": [
        ["message": ["role": "assistant", "content": content]]
      ]
    ]
    return try! JSONSerialization.data(withJSONObject: object)
  }
  private let suggestionJSON = #"{"suggestions":[{"original":"teh","start":0,"end":3,"replacement":"the","category":"spelling","reason":"Typo"}]}"#
  func testParseSuggestionsDecodesBareJSON() throws {
    let suggestions = try OpenAIProofreadingProvider.parseSuggestions(
      from: chatCompletionData(content: suggestionJSON),
      sourceText: sampleText
    )
    XCTAssertEqual(
      suggestions,
      [
        ProofreadingSuggestion(
          original: "teh",
          range: ProofreadingTextRange(start: 0, end: 3),
          replacement: "the",
          category: .spelling,
          reason: "Typo"
        )
      ]
    )
  }
  func testParseSuggestionsDecodesFencedJSON() throws {
    let fenced = "```json\n\(suggestionJSON)\n```"
    let suggestions = try OpenAIProofreadingProvider.parseSuggestions(
      from: chatCompletionData(content: fenced),
      sourceText: sampleText
    )
    XCTAssertEqual(suggestions.count, 1)
    XCTAssertEqual(suggestions.first?.replacement, "the")
  }
  func testParseSuggestionsDecodesEmptyList() throws {
    let suggestions = try OpenAIProofreadingProvider.parseSuggestions(
      from: chatCompletionData(content: #"{"suggestions":[]}"#),
      sourceText: sampleText
    )
    XCTAssertEqual(suggestions, [])
  }
  func testParseSuggestionsRejectsNonJSONContent() {
    XCTAssertThrowsError(
      try OpenAIProofreadingProvider.parseSuggestions(
        from: chatCompletionData(content: "I cannot help with that."),
        sourceText: sampleText
      )
    ) { error in
      XCTAssertEqual(error as? ProofreadingClientError, .malformedResponse)
    }
  }
  func testParseSuggestionsRejectsUnknownCategory() {
    let content = #"{"suggestions":[{"original":"teh","start":0,"end":3,"replacement":"the","category":"tone","reason":"?"}]}"#
    XCTAssertThrowsError(
      try OpenAIProofreadingProvider.parseSuggestions(
        from: chatCompletionData(content: content),
        sourceText: sampleText
      )
    ) { error in
      XCTAssertEqual(error as? ProofreadingClientError, .malformedResponse)
    }
  }
  func testParseSuggestionsRejectsNonChatCompletionBody() {
    XCTAssertThrowsError(
      try OpenAIProofreadingProvider.parseSuggestions(
        from: Data(#"{"unexpected":true}"#.utf8),
        sourceText: sampleText
      )
    ) { error in
      XCTAssertEqual(error as? ProofreadingClientError, .malformedResponse)
    }
  }
  // MARK: - End to end with a stubbed, offline URLSession
  private func makeStubbedSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> URLSession {
    MockURLProtocol.requestHandler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
  }
  private func okResponse(for request: URLRequest) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
  }
  func testProofreadReturnsValidatedResultFromStubbedSession() async throws {
    let session = makeStubbedSession { request in
      (self.okResponse(for: request), self.chatCompletionData(content: self.suggestionJSON))
    }
    let result = try await OpenAIProofreadingProvider.proofread(
      ProofreadingRequest(text: sampleText),
      configuration: makeConfiguration(),
      session: session
    )
    XCTAssertEqual(result.sourceText, sampleText)
    XCTAssertEqual(result.suggestions.count, 1)
    XCTAssertEqual(result.suggestions.first?.category, .spelling)
  }
  func testProofreadRejectsOverlappingModelSuggestions() async throws {
    let content = #"{"suggestions":[{"original":"teh","start":0,"end":3,"replacement":"the","category":"spelling","reason":"Typo"},{"original":"eh ","start":1,"end":4,"replacement":"e ","category":"grammar","reason":"Overlap"}]}"#
    let session = makeStubbedSession { request in
      (self.okResponse(for: request), self.chatCompletionData(content: content))
    }
    do {
      _ = try await OpenAIProofreadingProvider.proofread(
        ProofreadingRequest(text: sampleText),
        configuration: makeConfiguration(),
        session: session
      )
      XCTFail("Expected overlapping suggestions to be rejected")
    } catch {
      XCTAssertEqual(error as? ProofreadingClientError, .invalidSuggestions(.overlappingSuggestions))
    }
  }
  func testProofreadRejectsHTTPErrorStatus() async throws {
    let session = makeStubbedSession { request in
      (
        HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
        Data()
      )
    }
    do {
      _ = try await OpenAIProofreadingProvider.proofread(
        ProofreadingRequest(text: sampleText),
        configuration: makeConfiguration(),
        session: session
      )
      XCTFail("Expected httpError")
    } catch {
      XCTAssertEqual(error as? ProofreadingClientError, .httpError(500))
    }
  }
  func testProofreadRejectsEmptyTextBeforeAnyNetworkCall() async {
    let session = makeStubbedSession { _ in
      XCTFail("No request should be made for empty text")
      throw URLError(.unknown)
    }
    do {
      _ = try await OpenAIProofreadingProvider.proofread(
        ProofreadingRequest(text: "   "),
        configuration: makeConfiguration(),
        session: session
      )
      XCTFail("Expected empty text to be rejected")
    } catch {
      XCTAssertEqual(error as? ProofreadingClientError, .invalidSuggestions(.emptyText))
    }
  }
  // MARK: - Dependency seam
  func testLiveValueIsUnavailableUntilConfigured() async {
    let client = ProofreadingClient.liveValue
    do {
      _ = try await client.proofread(ProofreadingRequest(text: sampleText))
      XCTFail("Expected unavailable")
    } catch {
      XCTAssertEqual(error as? ProofreadingClientError, .unavailable)
    }
  }
  func testClientFromSettingsThrowsDisabledWhenProofreadingOff() async {
    let client = ProofreadingClient.openAICompatible(settings: HexSettings())
    do {
      _ = try await client.proofread(ProofreadingRequest(text: sampleText))
      XCTFail("Expected disabled")
    } catch {
      XCTAssertEqual(error as? ProofreadingClientError, .disabled)
    }
  }
}
private final class MockURLProtocol: URLProtocol {
  // XCTest runs a class's tests serially; guarded like `HexSettingsSchema.fields`.
  nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let handler = Self.requestHandler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
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
