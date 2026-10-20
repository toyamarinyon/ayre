import AppKit
import ApplicationServices

/// Empirical rule for the Codex editor observed in this probe. Never infer emptiness
/// from matching text alone. Unknown layouts are rejected instead of rewritten.
public enum CodexFieldState {
    public enum Decision: String { case empty, content, unknown }

    struct Node {
        var role: String
        var value: String
        var valueSettable: Bool
        var selectionSettable: Bool
        var editableAncestorIsRoot: Bool
        var children: [Node]
    }

    static func ancestorState(listed: Bool, error: AXError, matchesRoot: Bool) -> Bool? {
        if !listed { return false }
        if error == .success, matchesRoot { return true }
        if error == .noValue || error == .attributeUnsupported { return false }
        return nil
    }

    static func evaluate(value: String, title: String?, description: String?, range: CFRange, children: [Node]) -> Decision {
        func isEditable(_ node: Node) -> Bool {
            node.valueSettable && node.selectionSettable && node.editableAncestorIsRoot
        }
        func leaves(_ nodes: [Node]) -> [Node] {
            nodes.flatMap { $0.children.isEmpty ? [$0] : leaves($0.children) }
        }
        func supported(_ node: Node) -> Bool {
            if node.role == kAXStaticTextRole as String { return node.children.isEmpty }
            return node.role == kAXGroupRole as String && node.value.isEmpty && node.children.allSatisfy(supported)
        }
        guard children.allSatisfy(supported) else { return .unknown }
        let textLeaves = leaves(children).filter { !$0.value.isEmpty }
        if value.isEmpty, range.location == 0, range.length == 0, textLeaves.isEmpty {
            return .empty
        }
        // Real text, including the exact same text as the hint and an added LF,
        // must remain content if every text leaf belongs to the editable root.
        if !textLeaves.isEmpty, textLeaves.allSatisfy({ $0.role == kAXStaticTextRole as String && isEditable($0) }) {
            return .content
        }
        // Observed hint: editable paragraph -> noneditable wrapper -> noneditable text.
        guard range.location == 0, range.length == 0, children.count == 1 else { return .unknown }
        let paragraph = children[0]
        guard paragraph.role == kAXGroupRole as String, isEditable(paragraph), paragraph.children.count == 1 else { return .unknown }
        let wrapper = paragraph.children[0]
        guard wrapper.role == kAXGroupRole as String,
              !wrapper.valueSettable, !wrapper.selectionSettable, !wrapper.editableAncestorIsRoot,
              wrapper.children.count == 1 else { return .unknown }
        let hint = wrapper.children[0]
        guard hint.role == kAXStaticTextRole as String, !hint.value.isEmpty,
              !hint.valueSettable, !hint.selectionSettable, !hint.editableAncestorIsRoot,
              let title, let description,
              StrictCompare.equal(hint.value, title), StrictCompare.equal(hint.value, description),
              StrictCompare.equal(value, hint.value + "\n") else { return .unknown }
        return .empty
    }

    public static func inspect(_ target: FocusTarget) -> Decision {
        guard target.bundleID == InsertionStrategy.codexBundleID else { return .unknown }
        let root = target.element
        AXUIElementSetMessagingTimeout(root, 0.2)
        let deadline = Date().addingTimeInterval(5)
        var remaining = 64
        func childrenOf(_ element: AXUIElement) -> [AXUIElement]? {
            var count: CFIndex = 0
            let error = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
            guard error == .success, count >= 0, count <= remaining else {
                ProbeLog.log("Codex state read: children count error=\(axErrorName(error)) count=\(count) remaining=\(remaining)")
                return nil
            }
            if count == 0 { return [] }
            var array: CFArray?
            let readError = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, count, &array)
            guard readError == .success, let elements = array as? [AXUIElement], elements.count == count else {
                ProbeLog.log("Codex state read: children array error=\(axErrorName(readError)) shape=\(AX.describeShape(array))")
                return nil
            }
            return elements
        }
        var visited: [AXUIElement] = [root]
        func read(_ element: AXUIElement, depth: Int) -> Node? {
            guard remaining > 0, depth <= 6, Date() < deadline,
                  AX.pid(element) == target.pid,
                  !visited.contains(where: { CFEqual($0, element) }) else {
                ProbeLog.log("Codex state read: node rejected depth=\(depth) remaining=\(remaining) pid=\(AX.pid(element).map(String.init) ?? "unreadable")")
                return nil
            }
            remaining -= 1
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.2)
            guard let role = AX.string(element, kAXRoleAttribute),
                  role == kAXGroupRole as String || role == kAXStaticTextRole as String,
                  let value = AX.string(element, kAXValueAttribute) else {
                ProbeLog.log("Codex state read: role/value unreadable or unsupported depth=\(depth)")
                return nil
            }
            let (valueError, valueSettable) = AX.isSettable(element, kAXValueAttribute)
            let (selectionError, selectionSettable) = AX.isSettable(element, kAXSelectedTextAttribute)
            guard valueError == .success, selectionError == .success else {
                ProbeLog.log("Codex state read: settable errors value=\(axErrorName(valueError)) selection=\(axErrorName(selectionError)) depth=\(depth)")
                return nil
            }
            var rawNames: CFArray?
            let namesError = AXUIElementCopyAttributeNames(element, &rawNames)
            guard namesError == .success, let names = rawNames as? [String] else {
                ProbeLog.log("Codex state read: attribute list error=\(axErrorName(namesError)) depth=\(depth)")
                return nil
            }
            let listed = names.contains("AXEditableAncestor")
            let (ancestorError, ancestor) = listed ? AX.element(element, "AXEditableAncestor") : (.attributeUnsupported, nil)
            guard let isRoot = ancestorState(listed: listed, error: ancestorError,
                matchesRoot: ancestor.map { CFEqual($0, root) } ?? false) else {
                ProbeLog.log("Codex state read: ancestor error=\(axErrorName(ancestorError)) matchesRoot=false depth=\(depth)")
                return nil
            }
            ProbeLog.log("Codex state node: depth=\(depth) role=\(role) valueUTF16=\(value.utf16.count) valueSettable=\(valueSettable) selectionSettable=\(selectionSettable) ancestorListed=\(listed) ancestorIsRoot=\(isRoot)")
            guard let elements = childrenOf(element) else { return nil }
            var nodes: [Node] = []
            for child in elements {
                guard let node = read(child, depth: depth + 1) else { return nil }
                nodes.append(node)
            }
            return Node(role: role, value: value, valueSettable: valueSettable,
                        selectionSettable: selectionSettable, editableAncestorIsRoot: isRoot, children: nodes)
        }
        guard let value = AX.string(root, kAXValueAttribute),
              AX.int(root, kAXNumberOfCharactersAttribute) == value.utf16.count,
              let range = AX.range(root, kAXSelectedTextRangeAttribute),
              let elements = childrenOf(root) else {
            ProbeLog.log("Codex state read: root value/count/range/children unavailable")
            return .unknown
        }
        let title = AX.string(root, kAXTitleAttribute)
        let description = AX.string(root, kAXDescriptionAttribute)
        var nodes: [Node] = []
        for element in elements {
            guard let node = read(element, depth: 1) else { return .unknown }
            nodes.append(node)
        }
        guard Date() < deadline, case .success = Focus.validateStillFocused(target),
              let current = AX.string(root, kAXValueAttribute), StrictCompare.equal(current, value),
              let currentRange = AX.range(root, kAXSelectedTextRangeAttribute),
              currentRange.location == range.location, currentRange.length == range.length else {
            ProbeLog.log("Codex state read: end-of-capture state/focus changed or deadline exceeded")
            return .unknown
        }
        return evaluate(value: value, title: title, description: description, range: range, children: nodes)
    }
}
