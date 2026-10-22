import XCTest
@testable import AyreCore

final class InsertionStrategyTests: XCTestCase {
    func testOnlyCodexGetsTheCodexAdaptation() {
        XCTAssertEqual(InsertionStrategy.method(forBundleID: "com.openai.codex"), .codexValue)
        XCTAssertEqual(InsertionStrategy.method(forBundleID: "com.apple.TextEdit"), .selectedText)
        XCTAssertEqual(InsertionStrategy.method(forBundleID: nil), .selectedText)
    }

    func testCLIMethodNames() {
        XCTAssertEqual(InsertionStrategy.parse("auto"), .some(nil))
        XCTAssertEqual(InsertionStrategy.parse("selected-text"), .some(.selectedText))
        XCTAssertEqual(InsertionStrategy.parse("value"), .some(.value))
        XCTAssertEqual(InsertionStrategy.parse("codex-value"), .some(.codexValue))
        XCTAssertNil(InsertionStrategy.parse("clipboard"))
    }
}
