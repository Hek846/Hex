import ComposableArchitecture
import HexCore
import SwiftUI

struct ProofreadingPanelView: View {
  let store: StoreOf<ProofreadingFeature>

  var body: some View {
    WithViewStore(store, observe: { $0 }) { viewStore in
      ProofreadingOverlayView(
        selectedText: viewStore.sourceText,
        phase: overlayPhase(for: viewStore.state),
        onDismiss: { viewStore.send(.dismiss) },
        onApplySuggestion: { row in
          guard let suggestion = viewStore.suggestions.first(where: {
            $0.original == row.original && $0.replacement == row.replacement && $0.reason == row.reason
          }) else { return }
          viewStore.send(.applySuggestion(suggestion))
        },
        onApplyAll: { viewStore.send(.applyAll) },
        onCopy: { viewStore.send(.copyResult) }
      )
      .onAppear { viewStore.send(.checkSelectedText) }
    }
  }

  private func overlayPhase(for state: ProofreadingFeature.State) -> ProofreadingOverlayView.Phase {
    switch state.phase {
    case .idle: .ready
    case .loading: .loading(endpoint: state.checkingEndpoint)
    case .suggestions: .suggestions(state.suggestions.map(overlaySuggestion))
    case .empty: .empty
    case .applied: .applied
    case .copied: .copiedToClipboard
    case let .failed(message): .failed(message: message)
    }
  }

  private func overlaySuggestion(_ suggestion: ProofreadingSuggestion) -> ProofreadingOverlayView.Suggestion {
    .init(
      original: suggestion.original,
      replacement: suggestion.replacement,
      category: overlayCategory(suggestion.category),
      reason: suggestion.reason
    )
  }

  private func overlayCategory(_ category: ProofreadingCategory) -> ProofreadingOverlayView.Category {
    switch category {
    case .grammar: .grammar
    case .spelling: .spelling
    case .punctuation: .punctuation
    case .clarity: .clarity
    case .wording: .wording
    }
  }
}
