import XCTest
import ApplicationServices
@testable import AyreCore

final class TextComparisonTests: XCTestCase {
    func testSnapshotRedactsStringsButDetectsEqualLengthChanges() {
        let first = EmptyFieldDiagnostic.valueSummary("private A" as CFString)
        let again = EmptyFieldDiagnostic.valueSummary("private A" as CFString)
        let other = EmptyFieldDiagnostic.valueSummary("private B" as CFString)
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, other)
        XCTAssertFalse(first.contains("private A"))
        let nested = EmptyFieldDiagnostic.valueSummary(["secret key": ["private A"]] as CFDictionary)
        XCTAssertFalse(nested.contains("secret key"))
        XCTAssertFalse(nested.contains("private A"))
    }

    func testSnapshotKeepsUsefulScalarValues() {
        var range = CFRange(location: 7, length: 15)
        XCTAssertTrue(EmptyFieldDiagnostic.valueSummary(AXValueCreate(.cfRange, &range)).contains("location=7, length=15"))
        XCTAssertEqual(EmptyFieldDiagnostic.valueSummary(kCFBooleanTrue), "Bool(true)")
    }

    func testReadOnlyDiagnosticDoesNotExposeText() {
        XCTAssertEqual(EmptyFieldDiagnostic.textSummary("Work with Codex"), "empty=false equalsKnownTest=true equalsKnownTestPlusLF=false trailingLF=false")
        XCTAssertEqual(EmptyFieldDiagnostic.textSummary("Work with Codex\n"), "empty=false equalsKnownTest=false equalsKnownTestPlusLF=true trailingLF=true")
        XCTAssertEqual(EmptyFieldDiagnostic.textSummary("private input"), EmptyFieldDiagnostic.textSummary("別の本文"))
        XCTAssertEqual(EmptyFieldDiagnostic.textSummary(""), "empty=true equalsKnownTest=false equalsKnownTestPlusLF=false trailingLF=false")
    }

    func testMetadataMatchIsLiteralAndLimited() {
        XCTAssertTrue(StrictCompare.matchesLabel("Work with Codex\n", label: "Work with Codex"))
        XCTAssertTrue(StrictCompare.matchesLabel("案内😀\r\n", label: "案内😀"))
        XCTAssertFalse(StrictCompare.matchesLabel("Work with Codex additional text", label: "Work with Codex"))
        XCTAssertFalse(StrictCompare.matchesLabel("Work with Codex\n\n", label: "Work with Codex"))
        XCTAssertFalse(StrictCompare.matchesLabel("", label: ""))
        XCTAssertFalse(StrictCompare.matchesLabel("é", label: "e\u{301}"))
    }

    func testOnlyOneTerminalLineEndingMayBeClassified() {
        for (ending, label) in [("\n", "LF"), ("\r", "CR"), ("\r\n", "CRLF")] {
            XCTAssertEqual(StrictCompare.removedTerminalLineEnding(actual: "前😀e\u{301}", expected: "前😀e\u{301}" + ending), label)
        }
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "abc", expected: "abc"))
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "abc", expected: "abc\n\n"))
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "abX", expected: "abc\n"))
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "ab", expected: "abc"))
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "é", expected: "e\u{301}\n"))
        XCTAssertNil(StrictCompare.removedTerminalLineEnding(actual: "a b", expected: "a\nb\n"))
    }

    func testUTF16SelectionReplacementPreservesSurroundingText() {
        let result = StrictCompare.expected(before: "A😀e\u{301}Z", range: NSRange(location: 1, length: 2), inserted: "日本語")
        XCTAssertTrue(StrictCompare.equal(result!, "A日本語e\u{301}Z"))
        for range in [NSRange(location: -1, length: 0), NSRange(location: 0, length: -1), NSRange(location: Int.max, length: Int.max)] {
            XCTAssertNil(StrictCompare.expected(before: "abc", range: range, inserted: "x"))
        }
    }
}
