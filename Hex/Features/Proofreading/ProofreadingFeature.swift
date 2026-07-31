import ComposableArchitecture
import HexCore

/// Review-first local proofreading. This remains separate from Command Mode:
/// it never changes selected text until the person explicitly applies a fix.
@Reducer
struct ProofreadingFeature {
  @ObservableState
  struct State: Equatable {
    enum Phase: Equatable {
      case idle
      case loading
      case suggestions
      case empty
      case failed(String)
      case applied
      case copied
    }

    var phase: Phase = .idle
    var sourceText = ""
    var suggestions: [ProofreadingSuggestion] = []
    /// The local endpoint a check is sent to, shown while checking so the
    /// user can see exactly where their selected text goes.
    var checkingEndpoint: String?
  }

  enum Action: Equatable {
    case checkSelectedText
    case selectedTextLoaded(Result<String, SelectedTextReadError>)
    case proofreadingFinished(Result<ProofreadingResult, ProofreadingClientError>)
    case applySuggestion(ProofreadingSuggestion)
    case applyAll
    case replacementFinished
    case copyResult
    case copyFinished
    case dismiss
  }

  private enum CancelID { case proofreading }

  @Dependency(\.pasteboard) var pasteboard
  @Shared(.hexSettings) var hexSettings: HexSettings

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .checkSelectedText:
        state.phase = .loading
        state.checkingEndpoint = hexSettings.localProofreadingBaseURL
        return .run { send in
          await send(.selectedTextLoaded(await pasteboard.selectedText()))
        }
        .cancellable(id: CancelID.proofreading, cancelInFlight: true)

      case let .selectedTextLoaded(.failure(error)):
        state.phase = .failed(selectionMessage(for: error))
        return .none

      case let .selectedTextLoaded(.success(text)):
        state.sourceText = text
        let settings = hexSettings
        state.phase = .loading
        return .run { send in
          do {
            let client = ProofreadingClient.openAICompatible(settings: settings)
            let result = try await client.proofread(ProofreadingRequest(text: text))
            await send(.proofreadingFinished(.success(result)))
          } catch let error as ProofreadingClientError {
            await send(.proofreadingFinished(.failure(error)))
          } catch {
            await send(.proofreadingFinished(.failure(.malformedResponse)))
          }
        }
        .cancellable(id: CancelID.proofreading, cancelInFlight: true)

      case let .proofreadingFinished(.success(result)):
        state.sourceText = result.sourceText
        state.suggestions = result.suggestions
        state.phase = result.suggestions.isEmpty ? .empty : .suggestions
        return .none

      case let .proofreadingFinished(.failure(error)):
        state.phase = .failed(providerMessage(for: error))
        return .none

      case let .applySuggestion(suggestion):
        guard let replacement = replacing(state.sourceText, suggestions: [suggestion]) else {
          state.phase = .failed("This suggestion no longer matches the selected text.")
          return .none
        }
        state.suggestions.removeAll { $0 == suggestion }
        state.sourceText = replacement
        state.phase = state.suggestions.isEmpty ? .applied : .suggestions
        return .run { send in
          await pasteboard.paste(replacement)
          await send(.replacementFinished)
        }

      case .applyAll:
        guard let replacement = replacing(state.sourceText, suggestions: state.suggestions) else {
          state.phase = .failed("The suggestions could not be applied safely.")
          return .none
        }
        state.sourceText = replacement
        state.suggestions = []
        state.phase = .applied
        return .run { send in
          await pasteboard.paste(replacement)
          await send(.replacementFinished)
        }

      case .replacementFinished:
        return .none

      case .copyResult:
        let text = state.sourceText
        return .run { send in
          await pasteboard.copy(text)
          await send(.copyFinished)
        }

      case .copyFinished:
        if state.phase == .applied {
          state.phase = .copied
        }
        return .none

      case .dismiss:
        state = .init()
        return .cancel(id: CancelID.proofreading)
      }
    }
  }

  private func selectionMessage(for error: SelectedTextReadError) -> String {
    switch error {
    case .emptySelection:
      "Select some text first, then try again."
    case .focusedElementNotFound, .selectedTextUnsupported, .unexpectedValueType:
      "Hex could not read text from the focused app. Try selecting text in an editable field."
    }
  }

  private func providerMessage(for error: ProofreadingClientError) -> String {
    switch error {
    case .disabled:
      "Local proofreading is turned off. Enable it in Settings after configuring your endpoint."
    case .notConfigured:
      "Choose a local model before checking text."
    case .unavailable:
      "The local proofreading provider is not available."
    case .invalidBaseURL:
      "The local model address is not valid."
    case .httpError:
      "The local model did not accept this request."
    case .invalidSuggestions, .malformedResponse:
      "The local model returned suggestions Hex could not verify safely."
    }
  }

  private func replacing(
    _ text: String,
    suggestions: [ProofreadingSuggestion]
  ) -> String? {
    var output = text
    for suggestion in suggestions.sorted(by: { $0.range.start > $1.range.start }) {
      let utf16 = output.utf16
      guard
        let start16 = utf16.index(utf16.startIndex, offsetBy: suggestion.range.start, limitedBy: utf16.endIndex),
        let end16 = utf16.index(utf16.startIndex, offsetBy: suggestion.range.end, limitedBy: utf16.endIndex),
        let start = String.Index(start16, within: output),
        let end = String.Index(end16, within: output),
        output[start..<end] == suggestion.original
      else { return nil }
      output.replaceSubrange(start..<end, with: suggestion.replacement)
    }
    return output
  }
}
