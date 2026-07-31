import Dependencies
import DependenciesMacros
import Foundation
import HexCore
enum ProofreadingClientError: Error, Equatable, Sendable {
  case unavailable
  case disabled
  case notConfigured
  case invalidBaseURL(String)
  case httpError(Int)
  case invalidSuggestions(ProofreadingValidationError)
  case malformedResponse
}
/// Settings for an OpenAI-compatible proofreading endpoint, such as Ollama
/// running on the local Jetson.
///
/// No API key is required to talk to a local Ollama endpoint. `apiKey` is an
/// optional, additive field so token auth can be layered on later (for a
/// tunnelled or hosted endpoint) without breaking callers.
struct ProofreadingProviderConfiguration: Equatable, Sendable {
  var baseURL: String
  var model: String
  var requestTimeout: TimeInterval
  var apiKey: String?
  init(
    baseURL: String,
    model: String,
    requestTimeout: TimeInterval = 30,
    apiKey: String? = nil
  ) {
    self.baseURL = baseURL
    self.model = model
    self.requestTimeout = requestTimeout
    self.apiKey = apiKey
  }
  var isConfigured: Bool {
    !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
/// OpenAI-compatible proofreading provider (`POST {baseURL}/v1/chat/completions`,
/// which Ollama exposes).
///
/// HTTP construction (`makeRequest`) and response parsing (`parseSuggestions`)
/// are pure functions so they can be tested offline. Only `proofread` touches
/// the network, and only when a feature explicitly asks for suggestions —
/// nothing here runs at app startup.
enum OpenAIProofreadingProvider {
  static let systemPrompt = """
    You are a proofreading assistant. The text may be Chinese, English, or a \
    mix of both. Flag grammar, spelling, punctuation, clarity, and wording \
    problems only; do not rewrite for tone or style.
    Respond with a single JSON object and nothing else:
    {"suggestions": [{"original": String, "start": Int, "end": Int, \
    "replacement": String, "category": String, "reason": String}]}
    "original" must be the exact substring of the user text, and "start"/"end" \
    its UTF-16 offsets within that text. "category" is one of: grammar, \
    spelling, punctuation, clarity, wording. "reason" is a short, \
    human-readable explanation. Return {"suggestions": []} if the text is fine.
    """
  static func makeRequest(
    configuration: ProofreadingProviderConfiguration,
    request: ProofreadingRequest
  ) throws -> URLRequest {
    guard configuration.isConfigured else {
      throw ProofreadingClientError.notConfigured
    }
    let normalizedBase = configuration.baseURL
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .droppingTrailingSlash()
    guard let url = URL(string: normalizedBase + "/v1/chat/completions") else {
      throw ProofreadingClientError.invalidBaseURL(configuration.baseURL)
    }
    var urlRequest = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let apiKey = configuration.apiKey, !apiKey.isEmpty {
      urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    let body = ChatCompletionRequest(
      model: configuration.model,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: request.text)
      ]
    )
    do {
      urlRequest.httpBody = try JSONEncoder().encode(body)
    } catch {
      throw ProofreadingClientError.malformedResponse
    }
    return urlRequest
  }
  /// Parses an OpenAI chat-completion body into domain suggestions.
  /// Throws `ProofreadingClientError.malformedResponse` on any deviation from
  /// the expected shape; range/original validation happens separately in
  /// `ProofreadingValidator`.
  static func parseSuggestions(
    from data: Data,
    sourceText: String
  ) throws -> [ProofreadingSuggestion] {
    let completion: ChatCompletionResponse
    do {
      completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    } catch {
      throw ProofreadingClientError.malformedResponse
    }
    guard let content = completion.choices.first?.message.content,
      let jsonData = extractJSONObject(from: content)
    else {
      throw ProofreadingClientError.malformedResponse
    }
    let payload: SuggestionsPayload
    do {
      payload = try JSONDecoder().decode(SuggestionsPayload.self, from: jsonData)
    } catch {
      throw ProofreadingClientError.malformedResponse
    }
    return try payload.suggestions.map { dto in
      guard let category = ProofreadingCategory(rawValue: dto.category.lowercased()) else {
        throw ProofreadingClientError.malformedResponse
      }
      return ProofreadingSuggestion(
        original: dto.original,
        range: ProofreadingTextRange(start: dto.start, end: dto.end),
        replacement: dto.replacement,
        category: category,
        reason: dto.reason
      )
    }
  }
  static func proofread(
    _ request: ProofreadingRequest,
    configuration: ProofreadingProviderConfiguration,
    session: URLSession = .shared
  ) async throws -> ProofreadingResult {
    switch ProofreadingValidator.request(text: request.text) {
    case .failure(let error):
      throw ProofreadingClientError.invalidSuggestions(error)
    case .success:
      break
    }
    let urlRequest = try makeRequest(configuration: configuration, request: request)
    let (data, response) = try await session.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw ProofreadingClientError.malformedResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw ProofreadingClientError.httpError(httpResponse.statusCode)
    }
    let suggestions = try parseSuggestions(from: data, sourceText: request.text)
    switch ProofreadingValidator.result(sourceText: request.text, suggestions: suggestions) {
    case .success(let result):
      return result
    case .failure(let error):
      throw ProofreadingClientError.invalidSuggestions(error)
    }
  }
  /// Extracts the first JSON object from model output, tolerating a Markdown
  /// code fence or surrounding prose.
  static func extractJSONObject(from content: String) -> Data? {
    var text = content[...]
    if let fenceStart = text.range(of: "```") {
      text = text[fenceStart.upperBound...]
      if let newline = text.firstIndex(of: "\n") {
        text = text[newline...]
      }
      if let fenceEnd = text.range(of: "```") {
        text = text[..<fenceEnd.lowerBound]
      }
    }
    guard let open = text.firstIndex(of: "{"),
      let close = text.lastIndex(of: "}"),
      open <= close
    else {
      return nil
    }
    return String(text[open...close]).data(using: .utf8)
  }
}
// MARK: - Wire DTOs
private struct ChatCompletionRequest: Encodable {
  struct Message: Encodable {
    var role: String
    var content: String
  }
  var model: String
  var messages: [Message]
  var temperature: Double = 0
}
private struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      var content: String
    }
    var message: Message
  }
  var choices: [Choice]
}
private struct SuggestionsPayload: Decodable {
  struct Suggestion: Decodable {
    var original: String
    var start: Int
    var end: Int
    var replacement: String
    var category: String
    var reason: String
  }
  var suggestions: [Suggestion]
}
private extension String {
  func droppingTrailingSlash() -> String {
    var value = self
    while value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
/// Provider seam for local-first proofreading.
///
/// Kept separate from `CommandRewriteClient`: proofreading returns reviewable
/// suggestions and never rewrites text. `liveValue` stays unavailable until a
/// feature opts in and the user has configured the local endpoint, so no user
/// text touches the network during app startup.
@DependencyClient
struct ProofreadingClient {
  var proofread: @Sendable (ProofreadingRequest) async throws -> ProofreadingResult
}
extension ProofreadingClient: DependencyKey {
  static let liveValue = Self(
    proofread: { _ in throw ProofreadingClientError.unavailable }
  )
  /// Live implementation backed by the configured OpenAI-compatible endpoint
  /// (the Jetson running Ollama). Wire this in from a proofreading feature
  /// once the user enables local proofreading; it is not used at startup.
  static func openAICompatible(
    settings: HexSettings,
    session: URLSession = .shared
  ) -> Self {
    Self(
      proofread: { request in
        guard settings.localProofreadingEnabled else {
          throw ProofreadingClientError.disabled
        }
        let configuration = ProofreadingProviderConfiguration(
          baseURL: settings.localProofreadingBaseURL,
          model: settings.localProofreadingModel,
          requestTimeout: settings.localProofreadingRequestTimeout
        )
        return try await OpenAIProofreadingProvider.proofread(
          request,
          configuration: configuration,
          session: session
        )
      }
    )
  }
}
extension DependencyValues {
  var proofreading: ProofreadingClient {
    get { self[ProofreadingClient.self] }
    set { self[ProofreadingClient.self] = newValue }
  }
}
