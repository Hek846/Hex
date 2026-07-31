import Dependencies
import DependenciesMacros
import HexCore

enum CommandRewriteProviderError: Error, Equatable, Sendable {
  case unavailable
  case failed(String)
}

/// Provider seam for Command Mode.
///
/// Local models and cloud LLMs implement the same request contract. The live
/// value intentionally stays unavailable until a provider is configured.
@DependencyClient
struct CommandRewriteClient {
  var rewrite: @Sendable (CommandRewriteRequest) async throws -> String
}

extension CommandRewriteClient: DependencyKey {
  static let liveValue = Self(
    rewrite: { _ in throw CommandRewriteProviderError.unavailable }
  )
}

extension DependencyValues {
  var commandRewrite: CommandRewriteClient {
    get { self[CommandRewriteClient.self] }
    set { self[CommandRewriteClient.self] = newValue }
  }
}
