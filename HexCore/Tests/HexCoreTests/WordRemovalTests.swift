import Testing
@testable import HexCore

struct WordRemovalTests {
	@Test
	func removesFillerWordsAndRepeats() {
		let removals = [
			WordRemoval(pattern: "uh+"),
			WordRemoval(pattern: "um+"),
			WordRemoval(pattern: "er+"),
			WordRemoval(pattern: "hm+")
		]
		let result = WordRemovalApplier.apply("Umm uhhh er hmm", removals: removals)
		#expect(result.isEmpty)
	}

	@Test
	func cleansSpacesAndPunctuation() {
		let removals = [
			WordRemoval(pattern: "uh+"),
			WordRemoval(pattern: "um+")
		]
		let result = WordRemovalApplier.apply("Well, um, that's uh fine", removals: removals)
		#expect(result == "Well, that's fine")
	}

	@Test
	func doesNotRemoveInsideWords() {
		let result = WordRemovalApplier.apply("thumb", removals: [WordRemoval(pattern: "um+")])
		#expect(result == "thumb")
	}

	@Test
	func removesLeadingPunctuation() {
		let result = WordRemovalApplier.apply("um, hello", removals: [WordRemoval(pattern: "um+")])
		#expect(result == "hello")
	}

	@Test
	func removesChineseFillerAtStart() {
		let removals = [WordRemoval(pattern: "嗯+"), WordRemoval(pattern: "呃+")]
		let result = WordRemovalApplier.apply("嗯我想去吃饭", removals: removals)
		#expect(result == "我想去吃饭")
	}

	@Test
	func removesRepeatedChineseFillers() {
		let result = WordRemovalApplier.apply("嗯嗯嗯好的", removals: [WordRemoval(pattern: "嗯+")])
		#expect(result == "好的")
	}

	@Test
	func removesChineseFillerMidSentence() {
		let result = WordRemovalApplier.apply("我觉得呃这个不错", removals: [WordRemoval(pattern: "呃+")])
		#expect(result == "我觉得这个不错")
	}

	@Test
	func preservesChineseTextWithoutFillers() {
		let removals = [WordRemoval(pattern: "嗯+"), WordRemoval(pattern: "呃+")]
		let result = WordRemovalApplier.apply("你好世界", removals: removals)
		#expect(result == "你好世界")
	}

	@Test
	func removesMixedEnglishAndChineseFillers() {
		let removals = HexSettings.defaultWordRemovals
		let result = WordRemovalApplier.apply("Um 嗯 I think 呃 we should go", removals: removals)
		#expect(result == "I think we should go")
	}

	@Test
	func preservesMixedLanguageSemanticContent() {
		let removals = HexSettings.defaultWordRemovals
		let result = WordRemovalApplier.apply("I think 你好 means hello", removals: removals)
		#expect(result == "I think 你好 means hello")
	}

	@Test
	func removesErmFiller() {
		let result = WordRemovalApplier.apply("Erm, well, erm okay", removals: [WordRemoval(pattern: "erm+")])
		#expect(result == "well, okay")
	}

	@Test
	func doesNotRemoveErmInsideWords() {
		let result = WordRemovalApplier.apply("term", removals: [WordRemoval(pattern: "erm+")])
		#expect(result == "term")
	}
}
