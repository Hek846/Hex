import Foundation
/// Kinds of issues a proofreading pass can flag in user-selected text.
///
/// Provider-agnostic: the local Jetson provider and any future cloud
/// providers map their own taxonomies onto these shared categories.
public enum ProofreadingCategory: String, Codable, CaseIterable, Equatable, Sendable {
	case grammar
	case spelling
	case punctuation
	case clarity
	case wording
}
/// A half-open range of UTF-16 offsets into the proofread source text.
///
/// UTF-16 matches the offsets used by AppKit and the Accessibility APIs Hex
/// already uses to read selected text, so a suggestion can be mapped back
/// onto the original selection without re-encoding.
public struct ProofreadingTextRange: Codable, Equatable, Sendable {
	public var start: Int
	public var end: Int
	public init(start: Int, end: Int) {
		self.start = start
		self.end = end
	}
}
/// A single, human-reviewable proofreading suggestion.
///
/// Suggestions are always presented to the user before any source mutation;
/// nothing in this type implies the replacement has been applied.
public struct ProofreadingSuggestion: Codable, Equatable, Sendable {
	/// Exact substring of the source text the suggestion refers to.
	public var original: String
	/// Location of `original` inside the source text, in UTF-16 offsets.
	public var range: ProofreadingTextRange
	/// Proposed replacement for `original`. May be empty to suggest a deletion.
	public var replacement: String
	public var category: ProofreadingCategory
	/// Human-readable explanation shown alongside the suggestion.
	public var reason: String
	public init(
		original: String,
		range: ProofreadingTextRange,
		replacement: String,
		category: ProofreadingCategory,
		reason: String
	) {
		self.original = original
		self.range = range
		self.replacement = replacement
		self.category = category
		self.reason = reason
	}
}
/// A provider-neutral request to proofread selected text.
///
/// Deliberately separate from `CommandRewriteRequest`: proofreading returns
/// reviewable suggestions and never rewrites or mutates the source text.
public struct ProofreadingRequest: Codable, Equatable, Sendable {
	public var text: String
	public init(text: String) {
		self.text = text
	}
}
/// The validated outcome of a proofreading pass.
public struct ProofreadingResult: Codable, Equatable, Sendable {
	/// The exact text the suggestions were computed against.
	public var sourceText: String
	public var suggestions: [ProofreadingSuggestion]
	public init(sourceText: String, suggestions: [ProofreadingSuggestion]) {
		self.sourceText = sourceText
		self.suggestions = suggestions
	}
}
public enum ProofreadingValidationError: Error, Equatable, Sendable {
	case emptyText
	case emptyOriginal
	case invalidRange
	case originalMismatch
	case emptyReason
	case overlappingSuggestions
	case malformedModelOutput
}
/// Boundary validation shared by every proofreading provider.
///
/// Providers call `request(text:)` before sending anything and
/// `result(sourceText:suggestions:)` before returning parsed model output, so
/// malformed or overlapping suggestions can never reach the UI.
public enum ProofreadingValidator {
	public static func request(
		text: String
	) -> Result<ProofreadingRequest, ProofreadingValidationError> {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return .failure(.emptyText)
		}
		return .success(ProofreadingRequest(text: text))
	}
	public static func result(
		sourceText: String,
		suggestions: [ProofreadingSuggestion]
	) -> Result<ProofreadingResult, ProofreadingValidationError> {
		guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return .failure(.emptyText)
		}
		for suggestion in suggestions {
			if suggestion.original.isEmpty {
				return .failure(.emptyOriginal)
			}
			if suggestion.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				return .failure(.emptyReason)
			}
			guard
				suggestion.range.start >= 0,
				suggestion.range.end > suggestion.range.start,
				suggestion.range.end <= sourceText.utf16.count
			else {
				return .failure(.invalidRange)
			}
			guard substring(in: sourceText, utf16Range: suggestion.range) == suggestion.original else {
				return .failure(.originalMismatch)
			}
		}
		let sorted = suggestions.sorted {
			($0.range.start, $0.range.end) < ($1.range.start, $1.range.end)
		}
		for pair in zip(sorted, sorted.dropFirst()) {
			if pair.1.range.start < pair.0.range.end {
				return .failure(.overlappingSuggestions)
			}
		}
		return .success(ProofreadingResult(sourceText: sourceText, suggestions: suggestions))
	}
	private static func substring(in text: String, utf16Range range: ProofreadingTextRange) -> String? {
		let utf16 = text.utf16
		guard
			let start16 = utf16.index(utf16.startIndex, offsetBy: range.start, limitedBy: utf16.endIndex),
			let end16 = utf16.index(utf16.startIndex, offsetBy: range.end, limitedBy: utf16.endIndex),
			let start = String.Index(start16, within: text),
			let end = String.Index(end16, within: text)
		else {
			return nil
		}
		return String(text[start..<end])
	}
}
