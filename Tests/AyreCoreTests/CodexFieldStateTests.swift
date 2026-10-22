import XCTest
import ApplicationServices
@testable import AyreCore

final class CodexFieldStateTests: XCTestCase {
    func testNativeAXElementArrayBridge() {
        let element = AXUIElementCreateApplication(getpid())
        let raw: CFArray = [element] as CFArray
        let bridged = raw as? [AXUIElement]
        XCTAssertEqual(bridged?.count, 1)
        XCTAssertTrue(bridged.map { CFEqual($0[0], element) } ?? false)
    }

    func testOmittedAncestorIsDifferentFromFailedReadOfAdvertisedAncestor() {
        XCTAssertEqual(CodexFieldState.ancestorState(listed: false, error: .attributeUnsupported, matchesRoot: false), false)
        XCTAssertEqual(CodexFieldState.ancestorState(listed: true, error: .success, matchesRoot: true), true)
        XCTAssertEqual(CodexFieldState.ancestorState(listed: true, error: .noValue, matchesRoot: false), false)
        XCTAssertNil(CodexFieldState.ancestorState(listed: true, error: .failure, matchesRoot: false))
        XCTAssertNil(CodexFieldState.ancestorState(listed: true, error: .cannotComplete, matchesRoot: false))
        XCTAssertNil(CodexFieldState.ancestorState(listed: true, error: .success, matchesRoot: false))
    }

    typealias Node = CodexFieldState.Node
    func group(_ children: [Node], editable: Bool = true) -> Node {
        Node(role: "AXGroup", value: "", valueSettable: editable, selectionSettable: editable,
             editableAncestorIsRoot: editable, children: children)
    }
    func text(_ value: String, editable: Bool) -> Node {
        Node(role: "AXStaticText", value: value, valueSettable: editable, selectionSettable: editable,
             editableAncestorIsRoot: editable, children: [])
    }
    func evaluate(_ value: String, _ children: [Node], label: String = "Work with Codex", range: CFRange = CFRange(location: 0, length: 0)) -> CodexFieldState.Decision {
        CodexFieldState.evaluate(value: value, title: label, description: label, range: range, children: children)
    }

    func testObservedCyclePreservesRealInputEvenWhenValueMatchesHint() {
        let hint = [group([group([text("Work with Codex", editable: false)], editable: false)])]
        XCTAssertEqual(evaluate("Work with Codex\n", hint), .empty)
        XCTAssertEqual(evaluate("Work with Codex", [group([text("Work with Codex", editable: true)])]), .content)
        XCTAssertEqual(evaluate("Work with Codex\n", [group([text("Work with Codex", editable: true)]), group([])]), .content)
        XCTAssertEqual(evaluate("Work with Codex\n", hint), .empty)
    }

    func testDifferentHintWordingUsesStructureAndLiveLabels() {
        let label = "質問を入力😀"
        let hint = [group([group([text(label, editable: false)], editable: false)])]
        XCTAssertEqual(evaluate(label + "\n", hint, label: label), .empty)
        XCTAssertEqual(evaluate(label + "\n", hint, label: "別のラベル"), .unknown)
    }

    func testUnknownAndMixedStructuresNeverCountAsEmpty() {
        XCTAssertEqual(evaluate("Work with Codex\n", [text("Work with Codex", editable: false)]), .unknown)
        XCTAssertEqual(evaluate("Work with Codex\n", []), .unknown)
        XCTAssertEqual(evaluate("本文\n案内", [group([text("本文", editable: true), text("案内", editable: false)])]), .unknown)
        let hint = [group([group([text("Work with Codex", editable: false)], editable: false)])]
        XCTAssertEqual(evaluate("Work with Codex\n", hint, range: CFRange(location: 0, length: 16)), .unknown)
    }

    func testAllEditingSignalsAreRequiredForContent() {
        var leaf = text("Work with Codex", editable: true)
        leaf.editableAncestorIsRoot = false
        XCTAssertEqual(evaluate("Work with Codex", [group([leaf])]), .unknown)
        leaf.editableAncestorIsRoot = true
        leaf.selectionSettable = false
        XCTAssertEqual(evaluate("Work with Codex", [group([leaf])]), .unknown)
    }
}
