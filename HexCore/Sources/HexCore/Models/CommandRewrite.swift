import Foundation

/// Languages supported by the first Command Mode iteration.
///
/// Providers may use this as a response-language hint. The request remains
/// provider-agnostic so local and cloud implementations share the same contract.
public enum CommandLanguage: String, Codable, CaseIterable, Equatable, Sendable {
	case english
	case chinese
}

/// A provider-neutral request to rewrite selected text from a user instruction.
public struct CommandRewriteRequest: Codable, Equatable, Sendable {
	public var selectedText: String
	public var instruction: String
	public var responseLanguage: CommandLanguage

	public init(
		selectedText: String,
		instruction: String,
		responseLanguage: CommandLanguage
	) {
		self.selectedText = selectedText
		self.instruction = instruction
		self.responseLanguage = responseLanguage
	}
}

public enum CommandRewriteValidationError: Error, Equatable, Sendable {
	case emptySelection
	case emptyInstruction
	case emptyOutput
}

/// Boundary validation shared by every future rewrite provider.
public enum CommandRewriteValidator {
	public static func request(
		selectedText: String,
		instruction: String,
		responseLanguage: CommandLanguage
	) -> Result<CommandRewriteRequest, CommandRewriteValidationError> {
		guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return .failure(.emptySelection)
		}

		let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !instruction.isEmpty else {
			return .failure(.emptyInstruction)
		}

		return .success(
			CommandRewriteRequest(
				selectedText: selectedText,
				instruction: instruction,
				responseLanguage: responseLanguage
			)
		)
	}

	/// Rejects unusable provider output while preserving intentional whitespace.
	public static func output(_ text: String) -> Result<String, CommandRewriteValidationError> {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			return .failure(.emptyOutput)
		}
		return .success(text)
	}
}
