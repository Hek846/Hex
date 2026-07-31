import Foundation

public struct WordRemoval: Codable, Equatable, Identifiable, Sendable {
	public var id: UUID
	public var isEnabled: Bool
	public var pattern: String

	public init(
		id: UUID = UUID(),
		isEnabled: Bool = true,
		pattern: String
	) {
		self.id = id
		self.isEnabled = isEnabled
		self.pattern = pattern
	}
}

public enum WordRemovalApplier {
	public static func apply(_ text: String, removals: [WordRemoval]) -> String {
		guard !text.isEmpty, !removals.isEmpty else { return text }
		var output = text
		var didChange = false

		for removal in removals where removal.isEnabled {
			let trimmed = removal.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { continue }
			// \w matches CJK scalars in ICU regex, so word-boundary guards would
			// prevent CJK fillers from matching adjacent characters (Chinese text
			// has no inter-word spaces). Skip boundaries for CJK patterns.
			let pattern = containsCJK(trimmed)
				? "(?:\(trimmed))"
				: "(?<!\\w)(?:\(trimmed))(?!\\w)"
			guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
				continue
			}
			let range = NSRange(output.startIndex..., in: output)
			let updated = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "")
			if updated != output {
				didChange = true
				output = updated
			}
		}

		guard didChange else { return text }
		return cleanup(output)
	}

	private static func cleanup(_ text: String) -> String {
		var output = text
		output = output.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
		output = output.replacingOccurrences(of: "[ \t]+([,\\.!?;:])", with: "$1", options: .regularExpression)
		output = output.replacingOccurrences(of: "([,\\.!?;:])[ \t]*\\1+", with: "$1", options: .regularExpression)
		output = output.replacingOccurrences(of: "(?m)^[ \t]*[,\\.!?;:]+[ \t]*", with: "", options: .regularExpression)
		output = output.replacingOccurrences(of: "[ \t]+\\n", with: "\n", options: .regularExpression)
		output = output.replacingOccurrences(of: "\\n[ \t]+", with: "\n", options: .regularExpression)
		return output.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private static func containsCJK(_ text: String) -> Bool {
		text.unicodeScalars.contains { scalar in
			(0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
		}
	}
}
