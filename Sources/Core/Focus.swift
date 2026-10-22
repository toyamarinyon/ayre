import AppKit
import ApplicationServices

public enum AyreError: Error, CustomStringConvertible {
    case notTrusted
    case noFocusedApplication(AXError)
    case noFocusedElement(AXError)
    case notEditable(String)
    case targetChanged(String)
    case writeFailed(AXError)

    public var description: String {
        switch self {
        case .notTrusted:
            return "Accessibility permission is required (System Settings > Privacy & Security > Accessibility)."
        case .noFocusedApplication(let e): return "Cannot get the focused application: AXError=\(axErrorName(e))"
        case .noFocusedElement(let e): return "Cannot get the focused UI element: AXError=\(axErrorName(e))"
        case .notEditable(let r): return "Not an editable text field: \(r)"
        case .targetChanged(let r): return "Insertion target is invalid or has changed: \(r)"
        case .writeFailed(let e): return "Write failed: AXError=\(axErrorName(e))"
        }
    }
}

public struct FocusTarget {
    public let element: AXUIElement
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String?
    public let role: String?
    public let subrole: String?
    public let source: String

    public var summary: String {
        "source=\(source) pid=\(pid) bundleID=\(bundleID ?? "?") app=\(appName ?? "?") role=\(role ?? "?") subrole=\(subrole ?? "-")"
    }
}

public enum Focus {
    /// Lightweight observation for background monitoring; no enabling requests or content reads.
    public static func monitorSnapshot() -> String {
        guard AXIsProcessTrusted() else { return "trusted=false" }
        guard let front = NSWorkspace.shared.frontmostApplication else { return "trusted=true frontmost=nil" }
        let pid = front.processIdentifier
        let bundle = front.bundleURL.flatMap { Bundle(url: $0) }
        let system = AXUIElementCreateSystemWide()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(system, 0.1)
        AXUIElementSetMessagingTimeout(app, 0.1)
        func describe(_ owner: AXUIElement, _ attr: String) -> String {
            let (error, element) = AX.element(owner, attr)
            guard let element else { return axErrorName(error) }
            AXUIElementSetMessagingTimeout(element, 0.1)
            return "\(axErrorName(error)):pid=\(AX.pid(element) ?? -1):role=\(AX.string(element, kAXRoleAttribute) ?? "?")"
        }
        return "trusted=true frontmost=\(front.bundleIdentifier ?? "?") pid=\(pid) path=\(front.bundleURL?.path ?? "?") version=\(bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build=\(bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") systemApp=\(describe(system, kAXFocusedApplicationAttribute)) systemElement=\(describe(system, kAXFocusedUIElementAttribute)) appElement=\(describe(app, kAXFocusedUIElementAttribute)) window=\(describe(app, kAXFocusedWindowAttribute))"
    }

    /// Bounded, read-only tree inventory. Never inspect values, labels, titles, or selections.
    @MainActor
    public static func logWindowTreeDiagnostic(pid: pid_t, id: String) {
        let prefix = "[focus-tree \(id)]"
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, pid != getpid() else {
            AyreLog.log("\(prefix) skipped: original app is no longer frontmost")
            return
        }
        let running = NSRunningApplication(processIdentifier: pid)
        let bundle = running?.bundleURL.flatMap { Bundle(url: $0) }
        AyreLog.log("\(prefix) pid=\(pid) bundle=\(running?.bundleIdentifier ?? "?") version=\(bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") build=\(bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")")
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        let (error, window) = AX.element(app, kAXFocusedWindowAttribute)
        guard let window else {
            AyreLog.log("\(prefix) no focused window: \(axErrorName(error))")
            return
        }
        let start = Date()
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited: [AXUIElement] = []
        var index = 0
        var textCount = 0
        var truncated = false
        while index < queue.count, index < 150, Date().timeIntervalSince(start) < 1.5 {
            let (element, depth) = queue[index]
            index += 1
            guard !visited.contains(where: { CFEqual($0, element) }) else { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.05)
            let role = AX.string(element, kAXRoleAttribute) ?? "?"
            let focused = AX.bool(element, kAXFocusedAttribute).map(String.init) ?? "?"
            let secure = AX.string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String
            let isText = textRoles.contains(role)
            if isText { textCount += 1 }
            var detail = ""
            if isText && !secure {
                let (setError, settable) = AX.isSettable(element, kAXSelectedTextAttribute)
                detail = " selectedTextSettable=\(settable) error=\(axErrorName(setError))"
            }
            AyreLog.log("\(prefix) node=\(index) depth=\(depth) role=\(role) focused=\(focused) secure=\(secure)\(detail)")
            if secure { continue }
            var count: CFIndex = 0
            let countError = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &count)
            guard countError == .success else {
                AyreLog.log("\(prefix) node=\(index) children error=\(axErrorName(countError))")
                continue
            }
            guard count > 0 else { continue }
            guard depth < 16, queue.count < 150 else { truncated = true; continue }
            let take = min(count, 150 - queue.count)
            var raw: CFArray?
            let childError = AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, take, &raw)
            if childError == .success, let children = raw as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            } else {
                AyreLog.log("\(prefix) node=\(index) children read error=\(axErrorName(childError))")
            }
            if take < count { truncated = true }
        }
        AyreLog.log("\(prefix) finished nodes=\(visited.count) textRoles=\(textCount) truncated=\(truncated || index < queue.count) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(start)))s")
    }

    /// Read-only snapshot: never read field contents, labels, or window titles.
    @MainActor
    public static func logDiagnostic(id: String, originalPID: pid_t?) {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        let front = NSWorkspace.shared.frontmostApplication
        let prefix = "[focus-diagnostic \(id)]"
        AyreLog.log("\(prefix) trusted=\(AXIsProcessTrusted()) frontmost=\(front?.bundleIdentifier ?? "?") pid=\(front?.processIdentifier ?? -1)")
        func read(_ owner: AXUIElement, _ attribute: String, source: String) -> AXUIElement? {
            let (error, element) = AX.element(owner, attribute)
            let pid = element.flatMap { AX.pid($0) }
            let role = element.flatMap { AX.string($0, kAXRoleAttribute) } ?? "-"
            AyreLog.log("\(prefix) \(source).\(attribute) error=\(axErrorName(error)) pid=\(pid.map(String.init) ?? "-") role=\(role)")
            return element
        }
        let focusedApp = read(system, kAXFocusedApplicationAttribute, source: "system")
        _ = read(system, kAXFocusedUIElementAttribute, source: "system")
        let pids = Set([originalPID, front?.processIdentifier, focusedApp.flatMap { AX.pid($0) }].compactMap { $0 })
        for pid in pids.sorted() where pid != getpid() {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.3)
            AyreLog.log("\(prefix) app pid=\(pid) bundle=\(appInfo(pid: pid).bundleID ?? "?")")
            _ = read(app, kAXFocusedUIElementAttribute, source: "app(\(pid))")
            if let window = read(app, kAXFocusedWindowAttribute, source: "app(\(pid))") {
                _ = read(window, kAXFocusedUIElementAttribute, source: "window(\(pid))")
            }
        }
    }

    public static let textRoles: Set<String> = [
        kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String,
    ]

    /// Attributes whose existence/settability we report. Values are logged by shape only.
    public static let keyAttributes: [String] = [
        kAXValueAttribute as String,
        kAXSelectedTextAttribute as String,
        kAXSelectedTextRangeAttribute as String,
        kAXNumberOfCharactersAttribute as String,
        kAXInsertionPointLineNumberAttribute as String,
        kAXFocusedAttribute as String,
        "AXEditableAncestor",
        "AXSelectedTextMarkerRange",
    ]

    /// UI labels (not user input) that help identify which field is focused.
    public static let labelAttributes: [String] = [
        "AXPlaceholderValue",
        kAXDescriptionAttribute as String,
        kAXTitleAttribute as String,
        "AXIdentifier",
        "AXDOMIdentifier",
        kAXRoleDescriptionAttribute as String,
    ]

    public static func appInfo(pid: pid_t) -> (bundleID: String?, name: String?) {
        let app = NSRunningApplication(processIdentifier: pid)
        return (app?.bundleIdentifier, app?.localizedName)
    }

    public static func systemWideFocusedApplicationPID() -> Result<pid_t, AyreError> {
        let (err, app) = AX.element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)
        guard let app, let pid = AX.pid(app) else { return .failure(.noFocusedApplication(err)) }
        return .success(pid)
    }

    public static func systemWideFocusedElement() -> (AXError, AXUIElement?) {
        AX.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    }

    public static func appFocusedElement(pid: pid_t) -> (AXError, AXUIElement?) {
        AX.element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute)
    }

    /// Electron/Chromium only build their AX tree when an assistive client asks.
    /// https://www.electronjs.org/docs/latest/tutorial/accessibility
    @discardableResult
    public static func enableManualAccessibility(pid: pid_t) -> AXError {
        let app = AXUIElementCreateApplication(pid)
        let err = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AyreLog.log("AXManualAccessibility=true pid=\(pid) -> \(axErrorName(err))")
        return err
    }

    public static func makeTarget(_ element: AXUIElement, source: String) -> FocusTarget? {
        guard let pid = AX.pid(element) else { return nil }
        let info = appInfo(pid: pid)
        return FocusTarget(
            element: element, pid: pid, bundleID: info.bundleID, appName: info.name,
            role: AX.string(element, kAXRoleAttribute), subrole: AX.string(element, kAXSubroleAttribute),
            source: source
        )
    }

    /// Captures the element that currently has keyboard focus, according to the AX system-wide element.
    /// Falls back to the focused app's own focused element (AXFocusedUIElement on the app) and records which one was used.
    public static func captureFocusedTarget(enableElectronAX: Bool, retry: TimeInterval = 1.0) -> Result<FocusTarget, AyreError> {
        guard AXIsProcessTrusted() else { return .failure(.notTrusted) }
        let pid: pid_t
        switch systemWideFocusedApplicationPID() {
        case .success(let p): pid = p
        case .failure(let e): return .failure(e)
        }
        let info = appInfo(pid: pid)
        AyreLog.log("focused application: pid=\(pid) bundleID=\(info.bundleID ?? "?") name=\(info.name ?? "?")")
        if enableElectronAX { enableManualAccessibility(pid: pid) }

        let deadline = Date().addingTimeInterval(retry)
        var lastErr = AXError.noValue
        repeat {
            let (swErr, sw) = systemWideFocusedElement()
            let (appErr, appEl) = appFocusedElement(pid: pid)
            if let sw, let appEl {
                AyreLog.log("systemWide focused == app focused: \(CFEqual(sw, appEl))")
            }
            if let sw, AX.pid(sw) == pid, let t = makeTarget(sw, source: "systemWide.AXFocusedUIElement") { return .success(t) }
            if let appEl, let t = makeTarget(appEl, source: "app.AXFocusedUIElement") { return .success(t) }
            lastErr = appErr != .success ? appErr : swErr
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return .failure(.noFocusedElement(lastErr))
    }

    public static func logReport(_ target: FocusTarget) {
        let el = target.element
        AyreLog.log("target: \(target.summary)")
        AyreLog.log("attributes: \(AX.attributeNames(el).joined(separator: ","))")
        AyreLog.log("parameterized attributes: \(AX.parameterizedAttributeNames(el).joined(separator: ","))")
        for attr in keyAttributes {
            let (readErr, value) = AX.copy(el, attr)
            let (setErr, settable) = AX.isSettable(el, attr)
            AyreLog.log("  \(attr): read=\(axErrorName(readErr)) shape=\(AX.describeShape(value)) settable=\(settable) (\(axErrorName(setErr)))")
        }
        for attr in labelAttributes {
            if let s = AX.string(el, attr), !s.isEmpty {
                AyreLog.log("  label \(attr)=\"\(s.prefix(80))\"")
            }
        }
    }

    /// Editable = text role, not secure, and AXSelectedText is actually settable (existence is not enough).
    public static func checkEditable(_ target: FocusTarget) -> Result<Void, AyreError> {
        let el = target.element
        let (roleErr, roleValue) = AX.copy(el, kAXRoleAttribute)
        guard roleErr == .success, roleValue != nil else {
            return .failure(.targetChanged("Cannot read role: AXError=\(axErrorName(roleErr))"))
        }
        let role = AX.string(el, kAXRoleAttribute) ?? "?"
        if AX.string(el, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String) {
            return .failure(.notEditable("secure text field"))
        }
        guard textRoles.contains(role) else {
            return .failure(.notEditable("role=\(role) is not a text input role"))
        }
        let (err, settable) = AX.isSettable(el, kAXSelectedTextAttribute)
        guard err == .success, settable else {
            return .failure(.notEditable("AXSelectedText settable=\(settable) AXError=\(axErrorName(err))"))
        }
        return .success(())
    }

    /// The target is still valid only if it still exists and is still the focused element of the focused app.
    public static func validateStillFocused(_ target: FocusTarget) -> Result<Void, AyreError> {
        switch systemWideFocusedApplicationPID() {
        case .failure(let e): return .failure(.targetChanged("Cannot get the focused app: \(e)"))
        case .success(let pid) where pid != target.pid:
            let info = appInfo(pid: pid)
            return .failure(.targetChanged("Focused app changed: pid=\(pid) bundleID=\(info.bundleID ?? "?")"))
        default: break
        }
        let (err, current) = appFocusedElement(pid: target.pid)
        guard let current else { return .failure(.targetChanged("Cannot get the focused element: AXError=\(axErrorName(err))")) }
        guard CFEqual(current, target.element) else {
            return .failure(.targetChanged("Focused element changed (role=\(AX.string(current, kAXRoleAttribute) ?? "?"))"))
        }
        return checkEditable(target)
    }
}
