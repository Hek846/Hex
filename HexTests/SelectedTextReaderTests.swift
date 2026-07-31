import ApplicationServices
import XCTest

@testable import Hex

final class SelectedTextReaderTests: XCTestCase {
  func testInterpretReturnsSuccessForNonEmptyString() {
    let result = SelectedTextReader.interpret(copyError: .success, value: "hello world")
    guard case .success(let text) = result else { return XCTFail("Expected success, got \(result)") }
    XCTAssertEqual(text, "hello world")
  }
  func testInterpretReturnsEmptySelectionForEmptyString() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .success, value: ""), .failure(.emptySelection))
  }
  func testInterpretReturnsUnexpectedValueTypeForNonString() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .success, value: 42), .failure(.unexpectedValueType))
  }
  func testInterpretReturnsUnsupportedWhenValueIsNilOnSuccess() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .success, value: nil), .failure(.selectedTextUnsupported))
  }
  func testInterpretMapsAttributeUnsupported() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .attributeUnsupported, value: nil), .failure(.selectedTextUnsupported))
  }
  func testInterpretMapsNoValue() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .noValue, value: nil), .failure(.selectedTextUnsupported))
  }
  func testInterpretMapsApiDisabled() {
    XCTAssertEqual(SelectedTextReader.interpret(copyError: .apiDisabled, value: "ignored"), .failure(.selectedTextUnsupported))
  }
  func testInterpretSelectedTextValuePreservesWhitespaceOnlyAsSuccess() {
    XCTAssertEqual(SelectedTextReader.interpretSelectedTextValue("   "), .success("   "))
  }
  func testSelectedTextReadErrorIsEquatable() {
    XCTAssertEqual(SelectedTextReadError.emptySelection, .emptySelection)
    XCTAssertNotEqual(SelectedTextReadError.emptySelection, .focusedElementNotFound)
  }
}
