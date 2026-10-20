import AppKit
import ApplicationServices

public enum ProbeError: Error, CustomStringConvertible {
    case notTrusted
    case noFocusedApplication(AXError)
    case noFocusedElement(AXError)
    case notEditable(String)
    case targetChanged(String)
    case writeFailed(AXError)

    public var description: String {
        switch self {
        case .notTrusted:
            return "Accessibility権限がありません（システム設定 > プライバシーとセキュリティ > アクセシビリティ で許可）"
        case .noFocusedApplication(let e): return "フォーカス中のアプリを取得できません: AXError=\(axErrorName(e))"
        case .noFocusedElement(let e): return "フォーカス中のUI要素を取得できません: AXError=\(axErrorName(e))"
        case .notEditable(let r): return "編集可能な入力欄ではありません: \(r)"
        case .targetChanged(let r): return "挿入対象が無効または変化しました: \(r)"
        case .writeFailed(let e): return "書き込みに失敗: AXError=\(axErrorName(e))"
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

    public static func systemWideFocusedApplicationPID() -> Result<pid_t, ProbeError> {
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
        ProbeLog.log("AXManualAccessibility=true pid=\(pid) -> \(axErrorName(err))")
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
    public static func captureFocusedTarget(enableElectronAX: Bool, retry: TimeInterval = 1.0) -> Result<FocusTarget, ProbeError> {
        guard AXIsProcessTrusted() else { return .failure(.notTrusted) }
        let pid: pid_t
        switch systemWideFocusedApplicationPID() {
        case .success(let p): pid = p
        case .failure(let e): return .failure(e)
        }
        let info = appInfo(pid: pid)
        ProbeLog.log("focused application: pid=\(pid) bundleID=\(info.bundleID ?? "?") name=\(info.name ?? "?")")
        if enableElectronAX { enableManualAccessibility(pid: pid) }

        let deadline = Date().addingTimeInterval(retry)
        var lastErr = AXError.noValue
        repeat {
            let (swErr, sw) = systemWideFocusedElement()
            let (appErr, appEl) = appFocusedElement(pid: pid)
            if let sw, let appEl {
                ProbeLog.log("systemWide focused == app focused: \(CFEqual(sw, appEl))")
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
        ProbeLog.log("target: \(target.summary)")
        ProbeLog.log("attributes: \(AX.attributeNames(el).joined(separator: ","))")
        ProbeLog.log("parameterized attributes: \(AX.parameterizedAttributeNames(el).joined(separator: ","))")
        for attr in keyAttributes {
            let (readErr, value) = AX.copy(el, attr)
            let (setErr, settable) = AX.isSettable(el, attr)
            ProbeLog.log("  \(attr): read=\(axErrorName(readErr)) shape=\(AX.describeShape(value)) settable=\(settable) (\(axErrorName(setErr)))")
        }
        for attr in labelAttributes {
            if let s = AX.string(el, attr), !s.isEmpty {
                ProbeLog.log("  label \(attr)=\"\(s.prefix(80))\"")
            }
        }
    }

    /// Editable = text role, not secure, and AXSelectedText is actually settable (existence is not enough).
    public static func checkEditable(_ target: FocusTarget) -> Result<Void, ProbeError> {
        let el = target.element
        let (roleErr, roleValue) = AX.copy(el, kAXRoleAttribute)
        guard roleErr == .success, roleValue != nil else {
            return .failure(.targetChanged("role取得失敗 AXError=\(axErrorName(roleErr))"))
        }
        let role = AX.string(el, kAXRoleAttribute) ?? "?"
        if AX.string(el, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String) {
            return .failure(.notEditable("secure text field"))
        }
        guard textRoles.contains(role) else {
            return .failure(.notEditable("role=\(role) はテキスト入力のroleではない"))
        }
        let (err, settable) = AX.isSettable(el, kAXSelectedTextAttribute)
        guard err == .success, settable else {
            return .failure(.notEditable("AXSelectedText settable=\(settable) AXError=\(axErrorName(err))"))
        }
        return .success(())
    }

    /// The target is still valid only if it still exists and is still the focused element of the focused app.
    public static func validateStillFocused(_ target: FocusTarget) -> Result<Void, ProbeError> {
        switch systemWideFocusedApplicationPID() {
        case .failure(let e): return .failure(.targetChanged("フォーカス中アプリ取得失敗: \(e)"))
        case .success(let pid) where pid != target.pid:
            let info = appInfo(pid: pid)
            return .failure(.targetChanged("フォーカス中アプリが変化: pid=\(pid) bundleID=\(info.bundleID ?? "?")"))
        default: break
        }
        let (err, current) = appFocusedElement(pid: target.pid)
        guard let current else { return .failure(.targetChanged("フォーカス要素取得失敗 AXError=\(axErrorName(err))")) }
        guard CFEqual(current, target.element) else {
            return .failure(.targetChanged("フォーカス要素が別の要素に変化 (role=\(AX.string(current, kAXRoleAttribute) ?? "?"))"))
        }
        return checkEditable(target)
    }
}
