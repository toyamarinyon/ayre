import AppKit
import ApplicationServices

public func axErrorName(_ error: AXError) -> String {
    switch error {
    case .success: return "success"
    case .failure: return "failure"
    case .illegalArgument: return "illegalArgument"
    case .invalidUIElement: return "invalidUIElement"
    case .invalidUIElementObserver: return "invalidUIElementObserver"
    case .cannotComplete: return "cannotComplete"
    case .attributeUnsupported: return "attributeUnsupported"
    case .actionUnsupported: return "actionUnsupported"
    case .notificationUnsupported: return "notificationUnsupported"
    case .notImplemented: return "notImplemented"
    case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
    case .notificationNotRegistered: return "notificationNotRegistered"
    case .apiDisabled: return "apiDisabled"
    case .noValue: return "noValue"
    case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: return "notEnoughPrecision"
    @unknown default: return "unknown(\(error.rawValue))"
    }
}

public enum AX {
    public static func copy(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (err, value)
    }

    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        let (err, value) = copy(element, attribute)
        guard err == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    public static func element(_ element: AXUIElement, _ attribute: String) -> (AXError, AXUIElement?) {
        let (err, value) = copy(element, attribute)
        guard err == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (err, nil) }
        return (err, (value as! AXUIElement))
    }

    public static func range(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        let (err, value) = copy(element, attribute)
        guard err == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    public static func int(_ element: AXUIElement, _ attribute: String) -> Int? {
        let (err, value) = copy(element, attribute)
        guard err == .success, let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        return (value as! NSNumber).intValue
    }

    public static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        let (err, value) = copy(element, attribute)
        guard err == .success, let value else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return CFBooleanGetValue((value as! CFBoolean)) }
        if CFGetTypeID(value) == CFNumberGetTypeID() { return (value as! NSNumber).boolValue }
        return nil
    }

    public static func isSettable(_ element: AXUIElement, _ attribute: String) -> (AXError, Bool) {
        var settable = DarwinBoolean(false)
        let err = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return (err, settable.boolValue)
    }

    public static func pid(_ element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    public static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    public static func parameterizedAttributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success, let names else { return [] }
        return (names as? [String]) ?? []
    }

    /// Type and size of a value without its content (field content must not reach the log).
    public static func describeShape(_ value: CFTypeRef?) -> String {
        guard let value else { return "nil" }
        let type = CFGetTypeID(value)
        if type == CFStringGetTypeID() {
            return "String(\(TextStats((value as! CFString) as String)))"
        }
        if type == CFBooleanGetTypeID() { return "Bool(\(CFBooleanGetValue((value as! CFBoolean))))" }
        if type == CFNumberGetTypeID() { return "Number(\((value as! NSNumber).stringValue))" }
        if type == AXUIElementGetTypeID() {
            return "AXUIElement(role=\(string(value as! AXUIElement, kAXRoleAttribute) ?? "?"))"
        }
        if type == AXValueGetTypeID() {
            let v = value as! AXValue
            if AXValueGetType(v) == .cfRange {
                var r = CFRange()
                AXValueGetValue(v, .cfRange, &r)
                return "CFRange(location=\(r.location), length=\(r.length))"
            }
            return "AXValue(type=\(AXValueGetType(v).rawValue))"
        }
        if type == CFArrayGetTypeID() { return "Array(count=\(CFArrayGetCount((value as! CFArray))))" }
        if type == CFAttributedStringGetTypeID() { return "AttributedString(length=\(CFAttributedStringGetLength((value as! CFAttributedString))))" }
        return "CFType(\(CFCopyTypeIDDescription(type) as String))"
    }

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    public static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
