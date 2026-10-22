import AppKit
import ApplicationServices
import CryptoKit

/// Read-only, bounded inspection of the focused field, never its surrounding window.
public enum EmptyFieldDiagnostic {
    // Session-only key: compare strings without saving their contents or reusable hashes.
    private static let fingerprintKey = SymmetricKey(size: .bits256)

    public static func valueSummary(_ value: CFTypeRef?, depth: Int = 0) -> String {
        guard let value else { return "nil" }
        let type = CFGetTypeID(value)
        if type == CFStringGetTypeID() {
            let text = (value as! CFString) as String
            let digest = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: fingerprintKey)
                .prefix(12).map { String(format: "%02x", $0) }.joined()
            return "\(AX.describeShape(value)) \(textSummary(text)) sessionFingerprint=\(digest)"
        }
        if type == CFURLGetTypeID() {
            return "URL(redacted) " + valueSummary(CFURLGetString((value as! CFURL)), depth: depth + 1)
        }
        if type == AXValueGetTypeID() {
            let ax = value as! AXValue
            switch AXValueGetType(ax) {
            case .cgPoint:
                var point = CGPoint.zero
                if AXValueGetValue(ax, .cgPoint, &point) { return "Point(\(point.x),\(point.y))" }
            case .cgSize:
                var size = CGSize.zero
                if AXValueGetValue(ax, .cgSize, &size) { return "Size(\(size.width),\(size.height))" }
            case .cgRect:
                var rect = CGRect.zero
                if AXValueGetValue(ax, .cgRect, &rect) { return "Rect(\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height))" }
            default: break
            }
        }
        if type == CFArrayGetTypeID() {
            let array = value as! CFArray
            let count = CFArrayGetCount(array)
            guard depth < 3 else { return "Array(count=\(count), depthLimit)" }
            let entries = (0..<min(count, 16)).map { index -> String in
                let item = unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: CFTypeRef.self)
                return valueSummary(item, depth: depth + 1)
            }
            return "Array(count=\(count), truncated=\(count > 16)) [\(entries.joined(separator: "; "))]"
        }
        if type == CFDictionaryGetTypeID() {
            let dictionary = value as! NSDictionary
            guard depth < 3, dictionary.count <= 16 else { return "Dictionary(count=\(dictionary.count), depthOrSizeLimit)" }
            let entries = dictionary.map { key, item in
                valueSummary(key as CFTypeRef, depth: depth + 1) + " => " + valueSummary(item as CFTypeRef, depth: depth + 1)
            }.sorted()
            return "Dictionary(count=\(dictionary.count), truncated=\(entries.count > 16)) [\(entries.prefix(16).joined(separator: "; "))]"
        }
        return AX.describeShape(value)
    }

    public static func capture(_ target: FocusTarget) -> [String: String]? {
        guard case .success = Focus.validateStillFocused(target) else {
            AyreLog.log("[empty comparison] ABORT: Cannot verify target focus")
            return nil
        }
        let el = target.element
        AXUIElementSetMessagingTimeout(el, 0.5)
        let before = AX.string(el, kAXValueAttribute)
        let selection = AX.range(el, kAXSelectedTextRangeAttribute)
        let deadline = Date().addingTimeInterval(15)
        var result: [String: String] = [:]
        func summarize(_ element: AXUIElement, path: String) {
            AXUIElementSetMessagingTimeout(element, 0.5)
            let names = AX.attributeNames(element).sorted()
            result[path + ".all.attributeNames"] = names.joined(separator: ",")
            result[path + ".all.parameterizedNames"] = AX.parameterizedAttributeNames(element).sorted().joined(separator: ",")
            var actions: CFArray?
            let actionError = AXUIElementCopyActionNames(element, &actions)
            result[path + ".all.actionNames"] = "\(axErrorName(actionError)) \(((actions as? [String]) ?? []).sorted().joined(separator: ","))"
            for attribute in names {
                guard Date() < deadline else {
                    result[path + ".all." + attribute] = "SKIPPED (15-second snapshot budget)"
                    continue
                }
                // AXReplaceRangeWithText has appeared incorrectly in ordinary attribute lists;
                // invoking it as a read is not safe. Record its presence without calling it.
                if attribute == "AXReplaceRangeWithText" {
                    result[path + ".all." + attribute] = "SKIPPED (potential mutation)"
                    continue
                }
                let (error, raw) = AX.copy(element, attribute)
                let (setError, settable) = AX.isSettable(element, attribute)
                result[path + ".all." + attribute] = "read=\(axErrorName(error)) settable=\(settable)(\(axErrorName(setError))) \(valueSummary(raw))"
            }
            for attribute in [kAXRoleAttribute as String, kAXSubroleAttribute as String] {
                let (error, value) = AX.copy(element, attribute)
                // Roles are system identifiers; never print free-form descriptions or labels.
                let role = AX.string(element, attribute)
                result[path + "." + attribute] = "\(axErrorName(error)) \(role?.hasPrefix("AX") == true ? role! : AX.describeShape(value))"
            }
            for attribute in [kAXValueAttribute as String, "AXPlaceholderValue", kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
                let (error, raw) = AX.copy(element, attribute)
                var summary = "\(axErrorName(error)) \(AX.describeShape(raw))"
                if let value = AX.string(element, attribute) {
                    summary += " " + textSummary(value)
                }
                result[path + "." + attribute] = summary
            }
            result[path + ".AXNumberOfCharacters"] = AX.int(element, kAXNumberOfCharactersAttribute).map(String.init) ?? "unreadable"
            if let range = AX.range(element, kAXSelectedTextRangeAttribute) {
                result[path + ".selection"] = "{\(range.location),\(range.length)}"
            }
        }
        summarize(el, path: "root")
        let names = AX.parameterizedAttributeNames(el)
        result["root.supportsStringForRange"] = String(names.contains(kAXStringForRangeParameterizedAttribute as String))
        if names.contains(kAXStringForRangeParameterizedAttribute as String),
           let count = AX.int(el, kAXNumberOfCharactersAttribute), count >= 0, count <= 4096 {
            var range = CFRange(location: 0, length: count)
            if let parameter = AXValueCreate(.cfRange, &range) {
                var raw: CFTypeRef?
                let error = AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute as CFString, parameter, &raw)
                var summary = "\(axErrorName(error)) \(AX.describeShape(raw))"
                if let raw, CFGetTypeID(raw) == CFStringGetTypeID() {
                    let value = (raw as! CFString) as String
                    summary += " " + textSummary(value)
                    summary += " matchesAXValue=\(before.map { StrictCompare.equal(value, $0) } ?? false)"
                }
                result["root.stringForFullRange"] = summary
            }
        } else {
            result["root.stringForFullRange"] = "SKIPPED (unsupported/unreadable/over4096)"
        }

        var visited: [AXUIElement] = []
        func walk(_ element: AXUIElement, path: String, depth: Int) {
            guard Date() < deadline, visited.count < 12, depth <= 3,
                  !visited.contains(where: { CFEqual($0, element) }) else {
                result[path + ".truncated"] = "true"
                return
            }
            visited.append(element)
            if path != "root" { summarize(element, path: path) }
            var count: CFIndex = 0
            let error = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
            result[path + ".children"] = "\(axErrorName(error)) \(count)"
            guard error == .success, count > 0, depth < 3, visited.count < 12 else { return }
            var children: CFArray?
            let read = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, min(count, 12 - visited.count), &children)
            guard read == .success, let children else { return }
            for (index, child) in (children as [AnyObject]).enumerated() {
                guard CFGetTypeID(child) == AXUIElementGetTypeID() else { continue }
                walk(child as! AXUIElement, path: path + ".child\(index)", depth: depth + 1)
            }
        }
        walk(el, path: "root", depth: 0)
        guard case .success = Focus.validateStillFocused(target),
              let before, let after = AX.string(el, kAXValueAttribute), StrictCompare.equal(before, after),
              let selection, let afterSelection = AX.range(el, kAXSelectedTextRangeAttribute),
              selection.location == afterSelection.location, selection.length == afterSelection.length else {
            AyreLog.log("[empty comparison] ABORT: Text, selection, or focus changed or became unreadable during diagnostics")
            return nil
        }
        for key in result.keys.sorted() { AyreLog.log("[empty comparison] \(key): \(result[key]!)") }
        save(result, target: target)
        AyreLog.log("[empty comparison] read-only snapshot complete (text and selection unchanged)")
        return result
    }

    private static func save(_ values: [String: String], target: FocusTarget) {
        let folder = AyreLog.logURL.deletingLastPathComponent().appendingPathComponent("snapshots", isDirectory: true)
        let url = folder.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        let document: [String: Any] = ["capturedAt": ISO8601DateFormatter().string(from: Date()),
            "pid": target.pid, "bundleID": target.bundleID ?? "unknown", "attributes": values,
            "note": "Strings are redacted; fingerprints compare only within this app process. The snapshot is not atomic."]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
            AyreLog.log("[empty comparison] snapshot saved: \(url.path)")
        } catch {
            AyreLog.log("[empty comparison] snapshot save failed: \(error.localizedDescription)")
        }
    }

    public static func textSummary(_ value: String) -> String {
        "empty=\(value.isEmpty) equalsKnownTest=\(StrictCompare.equal(value, "Work with Codex")) equalsKnownTestPlusLF=\(StrictCompare.equal(value, "Work with Codex\n")) trailingLF=\(value.hasSuffix("\n"))"
    }
}
