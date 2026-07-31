import SwiftUI

/// Presentation-only UI for the local-first proofreading flow.
///
/// This deliberately has no provider dependency yet: the core proofreading
/// client will supply the suggestions, while this view owns how people review
/// and apply them. It can therefore be built and reviewed independently.
struct ProofreadingOverlayView: View {
  enum Phase: Equatable {
    case ready
    case loading(endpoint: String?)
    case suggestions([Suggestion])
    case empty
    case failed(message: String)
    case applied
    case copiedToClipboard
  }

  struct Suggestion: Identifiable, Equatable {
    let id: UUID
    let original: String
    let replacement: String
    let category: Category
    let reason: String

    init(
      id: UUID = UUID(),
      original: String,
      replacement: String,
      category: Category,
      reason: String
    ) {
      self.id = id
      self.original = original
      self.replacement = replacement
      self.category = category
      self.reason = reason
    }
  }

  enum Category: String, Equatable {
    case grammar = "Grammar"
    case spelling = "Spelling"
    case punctuation = "Punctuation"
    case clarity = "Clarity"
    case wording = "Wording"

    var symbol: String {
      switch self {
      case .grammar: "text.badge.checkmark"
      case .spelling: "character.book.closed"
      case .punctuation: "text.quote"
      case .clarity: "lightbulb"
      case .wording: "text.line.first.and.arrowtriangle.forward"
      }
    }
  }

  let selectedText: String
  let phase: Phase
  let onDismiss: () -> Void
  let onApplySuggestion: (Suggestion) -> Void
  let onApplyAll: () -> Void
  let onCopy: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      Divider()
      content
    }
    .padding(16)
    .frame(width: 360)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Proofreading suggestions")
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark.text.clipboard")
        .foregroundStyle(.tint)
        .font(.title3)

      VStack(alignment: .leading, spacing: 2) {
        Text("Check selection")
          .font(.headline)
        Text(headerSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button(action: onDismiss) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Close proofreading")
    }
  }

  @ViewBuilder
  private var content: some View {
    switch phase {
    case .ready:
      actionPrompt
    case let .loading(endpoint):
      loadingState(endpoint: endpoint)
    case let .suggestions(suggestions):
      suggestionList(suggestions)
    case .empty:
      emptyState
    case let .failed(message):
      failureState(message)
    case .applied:
      appliedState
    case .copiedToClipboard:
      clipboardState
    }
  }

  private var actionPrompt: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Review grammar, spelling, punctuation, and clear wording before any change is made.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Button("Check text") { }
        .buttonStyle(.borderedProminent)
        .disabled(true)
        .accessibilityHint("This becomes available when the local proofreading provider is connected.")
    }
  }

  private func loadingState(endpoint: String?) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("Checking your selected text…")
          .font(.subheadline)
      }
      if let endpoint, !endpoint.isEmpty {
        Text("Sent only to your local endpoint at \(endpoint).")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      } else {
        Text("Sent only to your local endpoint.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func suggestionList(_ suggestions: [Suggestion]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          ForEach(suggestions) { suggestion in
            SuggestionRow(suggestion: suggestion) {
              onApplySuggestion(suggestion)
            }
          }
        }
      }
      .frame(maxHeight: 276)

      Divider()

      HStack {
        Text("Nothing changes until you apply it.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Apply all") {
          onApplyAll()
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "checkmark.circle")
        .font(.title2)
        .foregroundStyle(.green)
      Text("No clear changes found")
        .font(.headline)
      Text("The selected text looks good as written.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 14)
  }

  private func failureState(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Couldn’t check this selection", systemImage: "exclamationmark.triangle")
        .foregroundStyle(.orange)
        .font(.headline)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("Close", action: onDismiss)
        .buttonStyle(.bordered)
    }
  }

  private var appliedState: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Changes applied", systemImage: "checkmark.circle")
        .font(.headline)
        .foregroundStyle(.green)
      Text("If the other app did not accept the replacement, copy the corrected text instead.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack {
        Button("Copy corrected text", action: onCopy)
          .buttonStyle(.bordered)
        Spacer()
        Button("Close", action: onDismiss)
          .buttonStyle(.bordered)
      }
    }
  }

  private var clipboardState: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Corrected text copied", systemImage: "doc.on.clipboard")
        .font(.headline)
      Text("Paste the corrected text where you need it.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack {
        Button("Copy again", action: onCopy)
          .buttonStyle(.bordered)
        Spacer()
        Button("Close", action: onDismiss)
          .buttonStyle(.bordered)
      }
    }
  }

  private var headerSubtitle: String {
    let compact = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !compact.isEmpty else { return "Selected text" }
    return compact.replacingOccurrences(of: "\n", with: " ")
  }
}

private struct SuggestionRow: View {
  let suggestion: ProofreadingOverlayView.Suggestion
  let onApply: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(suggestion.category.rawValue, systemImage: suggestion.category.symbol)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 6) {
        Text(suggestion.original)
          .strikethrough()
          .foregroundStyle(.secondary)
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Text(suggestion.replacement)
          .fontWeight(.semibold)
      }
      .font(.subheadline)

      Text(suggestion.reason)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("Apply", action: onApply)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

#Preview("Suggestions") {
  ProofreadingOverlayView(
    selectedText: "I has went to the store yesterday.",
    phase: .suggestions([
      .init(
        original: "has went",
        replacement: "went",
        category: .grammar,
        reason: "Use the simple past tense with a specific past time."
      ),
      .init(
        original: "I",
        replacement: "I",
        category: .wording,
        reason: "Example only"
      ),
    ]),
    onDismiss: {},
    onApplySuggestion: { _ in },
    onApplyAll: {},
    onCopy: {}
  )
  .padding()
}
