import ComposableArchitecture
import HexCore

/// Provider-agnostic orchestration for Command Mode (#197).
///
/// A future hotkey or UI supplies the instruction and response language. This
/// reducer owns the stable flow: read selection, validate, rewrite, and replace.
@Reducer
struct CommandModeFeature {
  @ObservableState
  struct State: Equatable {
    enum Phase: Equatable {
      case idle
      case readingSelection
      case rewriting
      case replacingSelection
      case succeeded
      case failed(Failure)
    }

    var phase: Phase = .idle
  }

  enum Failure: Equatable {
    case selectionUnavailable
    case emptySelection
    case emptyInstruction
    case providerUnavailable
    case providerFailed
    case emptyOutput
  }

  enum Action: Equatable {
    case rewriteRequested(instruction: String, responseLanguage: CommandLanguage)
    case selectedTextRead(
      Result<String, SelectedTextReadError>,
      instruction: String,
      responseLanguage: CommandLanguage
    )
    case rewriteFinished(Result<String, CommandRewriteProviderError>)
    case replacementFinished
    case reset
  }

  private enum CancelID {
    case rewrite
  }

  @Dependency(\.commandRewrite) var commandRewrite
  @Dependency(\.pasteboard) var pasteboard

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .rewriteRequested(instruction, responseLanguage):
        state.phase = .readingSelection
        return .run { send in
          let result = await pasteboard.selectedText()
          await send(
            .selectedTextRead(
              result,
              instruction: instruction,
              responseLanguage: responseLanguage
            )
          )
        }
        .cancellable(id: CancelID.rewrite, cancelInFlight: true)

      case let .selectedTextRead(.success(selectedText), instruction, responseLanguage):
        switch CommandRewriteValidator.request(
          selectedText: selectedText,
          instruction: instruction,
          responseLanguage: responseLanguage
        ) {
        case let .success(request):
          state.phase = .rewriting
          return .run { send in
            do {
              let output = try await commandRewrite.rewrite(request)
              switch CommandRewriteValidator.output(output) {
              case let .success(output):
                await send(.rewriteFinished(.success(output)))
              case .failure:
                await send(.rewriteFinished(.failure(.failed("emptyOutput"))))
              }
            } catch let error as CommandRewriteProviderError {
              await send(.rewriteFinished(.failure(error)))
            } catch {
              await send(.rewriteFinished(.failure(.failed("unexpected"))))
            }
          }
          .cancellable(id: CancelID.rewrite, cancelInFlight: true)

        case .failure(.emptySelection):
          state.phase = .failed(.emptySelection)
          return .none
        case .failure(.emptyInstruction):
          state.phase = .failed(.emptyInstruction)
          return .none
        case .failure(.emptyOutput):
          state.phase = .failed(.emptyOutput)
          return .none
        }

      case .selectedTextRead(.failure(.emptySelection), _, _):
        state.phase = .failed(.emptySelection)
        return .none

      case .selectedTextRead(.failure, _, _):
        state.phase = .failed(.selectionUnavailable)
        return .none

      case let .rewriteFinished(.success(output)):
        state.phase = .replacingSelection
        return .run { send in
          await pasteboard.paste(output)
          await send(.replacementFinished)
        }
        .cancellable(id: CancelID.rewrite, cancelInFlight: true)

      case .rewriteFinished(.failure(.unavailable)):
        state.phase = .failed(.providerUnavailable)
        return .none

      case let .rewriteFinished(.failure(.failed(reason))):
        state.phase = reason == "emptyOutput" ? .failed(.emptyOutput) : .failed(.providerFailed)
        return .none

      case .replacementFinished:
        state.phase = .succeeded
        return .none

      case .reset:
        state.phase = .idle
        return .cancel(id: CancelID.rewrite)
      }
    }
  }
}
