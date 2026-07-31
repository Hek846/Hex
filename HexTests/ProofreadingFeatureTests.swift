import ComposableArchitecture
import HexCore
import XCTest

@testable import Hex

@MainActor
final class ProofreadingFeatureTests: XCTestCase {
  private let sampleText = "teh quick  brown fox"
  private let spellingSuggestion = ProofreadingSuggestion(
    original: "teh",
    range: ProofreadingTextRange(start: 0, end: 3),
    replacement: "the",
    category: .spelling,
    reason: "Typo"
  )
  private let spacingSuggestion = ProofreadingSuggestion(
    original: "  ",
    range: ProofreadingTextRange(start: 9, end: 11),
    replacement: " ",
    category: .punctuation,
    reason: "Double space"
  )

  private func makeState(
    settings: HexSettings = HexSettings(),
    configure: (inout ProofreadingFeature.State) -> Void = { _ in }
  ) -> ProofreadingFeature.State {
    var state = ProofreadingFeature.State()
    state.$hexSettings.withLock { $0 = settings }
    configure(&state)
    return state
  }

  func testCheckSelectedTextReportsDisabledProviderWithoutNetwork() async {
    let store = TestStore(initialState: makeState()) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.selectedText = { .success("teh quick brown fox") }
    }

    await store.send(.checkSelectedText) {
      $0.phase = .loading
      $0.checkingEndpoint = "http://127.0.0.1:11434"
    }
    await store.receive(\.selectedTextLoaded) {
      $0.sourceText = "teh quick brown fox"
    }
    await store.receive(\.proofreadingFinished) {
      $0.phase = .failed(
        "Local proofreading is turned off. Enable it in Settings after configuring your endpoint."
      )
    }
  }

  func testCheckSelectedTextSurfacesEmptySelection() async {
    let store = TestStore(initialState: makeState()) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.selectedText = { .failure(.emptySelection) }
    }

    await store.send(.checkSelectedText) {
      $0.phase = .loading
      $0.checkingEndpoint = "http://127.0.0.1:11434"
    }
    await store.receive(\.selectedTextLoaded) {
      $0.phase = .failed("Select some text first, then try again.")
    }
  }

  func testProofreadingFinishedPopulatesSuggestions() async {
    let store = TestStore(initialState: makeState()) {
      ProofreadingFeature()
    }
    let result = ProofreadingResult(sourceText: sampleText, suggestions: [spellingSuggestion])

    await store.send(.proofreadingFinished(.success(result))) {
      $0.sourceText = self.sampleText
      $0.suggestions = [self.spellingSuggestion]
      $0.phase = .suggestions
    }
  }

  func testProofreadingFinishedWithNoSuggestionsShowsEmpty() async {
    let store = TestStore(initialState: makeState()) {
      ProofreadingFeature()
    }
    let result = ProofreadingResult(sourceText: "all good", suggestions: [])

    await store.send(.proofreadingFinished(.success(result))) {
      $0.sourceText = "all good"
      $0.phase = .empty
    }
  }

  func testApplySuggestionRewritesAndPastesSelection() async {
    let pasted = PasteCapture()
    let store = TestStore(
      initialState: makeState {
        $0.phase = .suggestions
        $0.sourceText = sampleText
        $0.suggestions = [spellingSuggestion, spacingSuggestion]
      }
    ) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.paste = { text in await pasted.record(text) }
    }

    await store.send(.applySuggestion(spellingSuggestion)) {
      $0.suggestions = [self.spacingSuggestion]
      $0.sourceText = "the quick  brown fox"
      $0.phase = .suggestions
    }
    await store.receive(\.replacementFinished)
    let recorded = await pasted.values()
    XCTAssertEqual(recorded, ["the quick  brown fox"])
  }

  func testApplyingLastSuggestionMovesToAppliedPhase() async {
    let store = TestStore(
      initialState: makeState {
        $0.phase = .suggestions
        $0.sourceText = sampleText
        $0.suggestions = [spellingSuggestion]
      }
    ) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.paste = { _ in }
    }

    await store.send(.applySuggestion(spellingSuggestion)) {
      $0.suggestions = []
      $0.sourceText = "the quick  brown fox"
      $0.phase = .applied
    }
    await store.receive(\.replacementFinished)
  }

  func testApplyAllAppliesEverySuggestionAndPastes() async {
    let pasted = PasteCapture()
    let store = TestStore(
      initialState: makeState {
        $0.phase = .suggestions
        $0.sourceText = sampleText
        $0.suggestions = [spellingSuggestion, spacingSuggestion]
      }
    ) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.paste = { text in await pasted.record(text) }
    }

    await store.send(.applyAll) {
      $0.sourceText = "the quick brown fox"
      $0.suggestions = []
      $0.phase = .applied
    }
    await store.receive(\.replacementFinished)
    let recorded = await pasted.values()
    XCTAssertEqual(recorded, ["the quick brown fox"])
  }

  func testCopyResultCopiesCorrectedTextWhenPasteIsNotPossible() async {
    let copied = PasteCapture()
    let store = TestStore(
      initialState: makeState {
        $0.phase = .applied
        $0.sourceText = "the quick brown fox"
      }
    ) {
      ProofreadingFeature()
    } withDependencies: {
      $0.pasteboard.copy = { text in await copied.record(text) }
    }

    await store.send(.copyResult)
    await store.receive(\.copyFinished) {
      $0.phase = .copied
    }
    let recorded = await copied.values()
    XCTAssertEqual(recorded, ["the quick brown fox"])
  }

  func testDismissResetsState() async {
    let store = TestStore(
      initialState: makeState {
        $0.phase = .applied
        $0.sourceText = "the quick brown fox"
        $0.checkingEndpoint = "http://127.0.0.1:11434"
      }
    ) {
      ProofreadingFeature()
    }

    await store.send(.dismiss) {
      $0.phase = .idle
      $0.sourceText = ""
      $0.suggestions = []
      $0.checkingEndpoint = nil
    }
  }
}

private actor PasteCapture {
  private var recorded: [String] = []
  func record(_ text: String) { recorded.append(text) }
  func values() -> [String] { recorded }
}
