import Foundation
import Testing
@testable import HexCore
struct ProofreadingValidatorTests {
	private func suggestion(
		original: String = "teh",
		start: Int = 0,
		end: Int = 3,
		replacement: String = "the",
		category: ProofreadingCategory = .spelling,
		reason: String = "Spelling mistake"
	) -> ProofreadingSuggestion {
		ProofreadingSuggestion(
			original: original,
			range: ProofreadingTextRange(start: start, end: end),
			replacement: replacement,
			category: category,
			reason: reason
		)
	}
	@Test
	func requestRejectsEmptyText() {
		#expect(ProofreadingValidator.request(text: "") == .failure(.emptyText))
		#expect(ProofreadingValidator.request(text: "  \n\t ") == .failure(.emptyText))
	}
	@Test
	func requestAcceptsNonEmptyText() {
		let outcome = ProofreadingValidator.request(text: "你好 world")
		guard case .success(let request) = outcome else {
			Issue.record("Expected success, got \(outcome)")
			return
		}
		#expect(request.text == "你好 world")
	}
	@Test
	func resultAcceptsValidSuggestions() {
		let text = "teh quick  brown fox"
		let suggestions = [
			suggestion(original: "teh", start: 0, end: 3),
			suggestion(original: "  ", start: 9, end: 11, replacement: " ", reason: "Double space")
		]
		let outcome = ProofreadingValidator.result(sourceText: text, suggestions: suggestions)
		guard case .success(let result) = outcome else {
			Issue.record("Expected success, got \(outcome)")
			return
		}
		#expect(result.sourceText == text)
		#expect(result.suggestions == suggestions)
	}
	@Test
	func resultAcceptsEmptySuggestionList() {
		let outcome = ProofreadingValidator.result(sourceText: "all good", suggestions: [])
		#expect(outcome == .success(ProofreadingResult(sourceText: "all good", suggestions: [])))
	}
	@Test
	func resultRejectsEmptySourceText() {
		#expect(ProofreadingValidator.result(sourceText: "  ", suggestions: []) == .failure(.emptyText))
	}
	@Test
	func resultRejectsEmptyOriginal() {
		let outcome = ProofreadingValidator.result(
			sourceText: "hello",
			suggestions: [suggestion(original: "", start: 0, end: 0)]
		)
		#expect(outcome == .failure(.emptyOriginal))
	}
	@Test
	func resultRejectsEmptyReason() {
		let outcome = ProofreadingValidator.result(
			sourceText: "teh",
			suggestions: [suggestion(reason: "   ")]
		)
		#expect(outcome == .failure(.emptyReason))
	}
	@Test
	func resultRejectsOutOfBoundsRange() {
		let text = "hello"
		#expect(
			ProofreadingValidator.result(
				sourceText: text,
				suggestions: [suggestion(original: "hello", start: 0, end: 100)]
			) == .failure(.invalidRange)
		)
		#expect(
			ProofreadingValidator.result(
				sourceText: text,
				suggestions: [suggestion(original: "h", start: -1, end: 1)]
			) == .failure(.invalidRange)
		)
		#expect(
			ProofreadingValidator.result(
				sourceText: text,
				suggestions: [suggestion(original: "h", start: 2, end: 2)]
			) == .failure(.invalidRange)
		)
	}
	@Test
	func resultRejectsMismatchedOriginal() {
		let outcome = ProofreadingValidator.result(
			sourceText: "hello world",
			suggestions: [suggestion(original: "wrld", start: 6, end: 10)]
		)
		#expect(outcome == .failure(.originalMismatch))
	}
	@Test
	func resultRejectsOverlappingSuggestions() {
		let text = "abcdef"
		let suggestions = [
			suggestion(original: "abc", start: 0, end: 3),
			suggestion(original: "cd", start: 2, end: 4)
		]
		#expect(ProofreadingValidator.result(sourceText: text, suggestions: suggestions) == .failure(.overlappingSuggestions))
	}
	@Test
	func resultAcceptsAdjacentSuggestions() {
		let text = "abcdef"
		let suggestions = [
			suggestion(original: "abc", start: 0, end: 3),
			suggestion(original: "def", start: 3, end: 6)
		]
		let outcome = ProofreadingValidator.result(sourceText: text, suggestions: suggestions)
		guard case .success = outcome else {
			Issue.record("Expected success, got \(outcome)")
			return
		}
	}
	@Test
	func resultDetectsOverlapRegardlessOfOrder() {
		let text = "abcdef"
		let suggestions = [
			suggestion(original: "cd", start: 2, end: 4),
			suggestion(original: "abc", start: 0, end: 3)
		]
		#expect(ProofreadingValidator.result(sourceText: text, suggestions: suggestions) == .failure(.overlappingSuggestions))
	}
	@Test
	func resultHandlesMixedChineseEnglishUTF16Ranges() {
		let text = "我喜欢 programing 语言"
		// "programing" starts at UTF-16 offset 4 and is 10 units long.
		let outcome = ProofreadingValidator.result(
			sourceText: text,
			suggestions: [
				suggestion(original: "programing", start: 4, end: 14, replacement: "programming", reason: "Missing letter")
			]
		)
		guard case .success = outcome else {
			Issue.record("Expected success, got \(outcome)")
			return
		}
	}
	@Test
	func resultHandlesEmojiUTF16Offsets() {
		// The emoji occupies two UTF-16 units, so "teh" starts at offset 6.
		let text = "ok 💧 teh"
		let outcome = ProofreadingValidator.result(
			sourceText: text,
			suggestions: [suggestion(original: "teh", start: 6, end: 9)]
		)
		guard case .success = outcome else {
			Issue.record("Expected success, got \(outcome)")
			return
		}
	}
}
struct LocalProofreadingSettingsTests {
	@Test
	func defaultsKeepProofreadingOffAndUnconfigured() {
		let settings = HexSettings()
		#expect(settings.localProofreadingEnabled == false)
		#expect(settings.localProofreadingBaseURL == "http://127.0.0.1:11434")
		#expect(settings.localProofreadingModel.isEmpty)
		#expect(settings.localProofreadingRequestTimeout == 30)
	}
	@Test
	func legacyPayloadWithoutProofreadingKeysDecodesToSafeDefaults() throws {
		let data = Data("{}".utf8)
		let decoded = try JSONDecoder().decode(HexSettings.self, from: data)
		#expect(decoded.localProofreadingEnabled == false)
		#expect(decoded.localProofreadingModel.isEmpty)
		#expect(decoded.localProofreadingBaseURL == "http://127.0.0.1:11434")
		#expect(decoded.localProofreadingRequestTimeout == 30)
	}
	@Test
	func proofreadingSettingsRoundTrip() throws {
		var settings = HexSettings()
		settings.localProofreadingEnabled = true
		settings.localProofreadingBaseURL = "http://192.168.1.50:11434"
		settings.localProofreadingModel = "test-model-7b"
		settings.localProofreadingRequestTimeout = 45
		let data = try JSONEncoder().encode(settings)
		let decoded = try JSONDecoder().decode(HexSettings.self, from: data)
		#expect(decoded == settings)
	}
}
