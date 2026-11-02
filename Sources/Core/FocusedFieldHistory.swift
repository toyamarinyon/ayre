import AppKit
import ApplicationServices

/// Remembers element identity, never field contents. Tracking uses notifications, not polling.
@MainActor
public final class FocusedFieldHistory {
    public static let shared = FocusedFieldHistory()
    public static let invokers: Set<String> = ["com.apple.Spotlight", "com.apple.shortcuts", "com.apple.siri"]
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var last: FocusTarget?

    public func start() {
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in Self.shared.attachToFrontmost() }
            }
            terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { notification in
                let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                Task { @MainActor in
                    if Self.shared.last?.pid == pid { Self.shared.last = nil }
                    if Self.shared.observedPID == pid { Self.shared.detach() }
                }
            }
        }
        attachToFrontmost()
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }

    private func attachToFrontmost() {
        guard AXIsProcessTrusted() else { last = nil; detach(); return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        // Spotlight and Ayre do not replace the original application's remembered field.
        guard pid != getpid(), !Self.invokers.contains(app.bundleIdentifier ?? "") else { return }
        if observedPID != pid {
            detach()
            var created: AXObserver?
            let error = AXObserverCreate(pid, { _, _, _, _ in
                // AX observer sources are explicitly installed on the main run loop.
                MainActor.assumeIsolated { FocusedFieldHistory.shared.captureNotification() }
            }, &created)
            guard error == .success, let created else {
                AyreLog.log("[focus-history] observer pid=\(pid) failed=\(axErrorName(error))")
                return
            }
            observer = created
            observedPID = pid
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            var subscriptions = 0
            for notification in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
                let result = AXObserverAddNotification(created, element, notification as CFString, nil)
                if result == .success { subscriptions += 1 }
                AyreLog.log("[focus-history] subscribe pid=\(pid) \(notification)=\(axErrorName(result))")
            }
            guard subscriptions > 0 else {
                captureNotification()
                detach()
                return
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        captureNotification()
    }

    private func captureNotification() {
        guard let pid = observedPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        guard AXIsProcessTrusted() else { last = nil; detach(); return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        let systemElement = AX.element(system, kAXFocusedUIElementAttribute).1
        let appElement = AX.element(app, kAXFocusedUIElementAttribute).1
        let element = systemElement.flatMap { AX.pid($0) == pid ? $0 : nil } ?? appElement
        guard let element, AX.pid(element) == pid else { return }
        AXUIElementSetMessagingTimeout(element, 0.2)
        if AX.string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String {
            last = nil
            return
        }
        guard let target = Focus.makeTarget(element, source: "AXObserver.lastFocusedField"),
              case .success = Focus.checkEditable(target) else { return }
        if let last, CFEqual(last.element, element) { return }
        last = target
        AyreLog.log("[focus-history] remembered \(target.summary)")
    }

    /// Freeze this reference for an invocation. Never replace the destination during insertion.
    public func snapshot() -> FocusTarget? {
        guard AXIsProcessTrusted(), let last,
              NSRunningApplication(processIdentifier: last.pid)?.isTerminated == false else { return nil }
        guard case .success = Focus.validateTargetExists(last) else { self.last = nil; return nil }
        return last
    }
}
