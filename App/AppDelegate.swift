import AppKit
import ApplicationServices

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    var window: NSWindow!
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let storeLabel = NSTextField(wrappingLabelWithString: "")
    let hotKeyCheckbox = NSButton(checkboxWithTitle: "Open the picker with ⌃⌥⌘P while Ayre is running", target: nil, action: nil)
    let hotKey = HotKey()
    let picker = PickerController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProbeLog.echoToStderr = false
        ProbeLog.section("App launched")
        ProbeEnvironment.log()
        buildMenu()
        buildWindow()
        refreshStatus()
        hotKeyCheckbox.state = .on
        toggleHotKey()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ayre"
        window.isReleasedWhenClosed = false
        hotKeyCheckbox.target = self
        hotKeyCheckbox.action = #selector(toggleHotKey)

        let permissionButtons = NSStackView(views: [
            NSButton(title: "Check Permission", target: self, action: #selector(refreshStatus)),
            NSButton(title: "Request Permission", target: self, action: #selector(requestPermission)),
            NSButton(title: "Open System Settings", target: self, action: #selector(openSettings)),
            NSButton(title: "Open Log", target: self, action: #selector(openLog)),
        ])
        let storeButtons = NSStackView(views: [
            NSButton(title: "Open Prompt Folder", target: self, action: #selector(openStore)),
            NSButton(title: "Reload Prompts", target: self, action: #selector(refreshStatus)),
        ])
        let help = NSTextField(wrappingLabelWithString: """
        Place the cursor in a text field. Use Spotlight: Ayre Go inserts the latest prompt; Ayre Pick lets you choose. Or press ⌃⌥⌘P, search, select with ↑↓, and press Return. Esc cancels.
        Insertion requires focus to return to the original field. Ayre never sends your message. If the target or field state cannot be verified, nothing is written.
        """)
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [statusLabel, permissionButtons, separator, storeLabel, storeButtons, hotKeyCheckbox, help])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        window.contentView = stack
        [statusLabel, storeLabel, help].forEach { $0.preferredMaxLayoutWidth = 600 }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Show Window", action: #selector(showWindow), keyEquivalent: "0")
        appMenu.addItem(withTitle: "Quit Ayre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil) }

    @objc func refreshStatus() {
        let trusted = AXIsProcessTrusted()
        statusLabel.stringValue = trusted
            ? "Accessibility permission: granted (\(Bundle.main.bundlePath))"
            : "Accessibility permission: not granted. Click Request Permission or allow Ayre in System Settings > Privacy & Security > Accessibility. Changing the code signature may invalidate permission."
        let (prompts, skipped) = picker.store.list()
        storeLabel.stringValue = "Saved prompts: \(prompts.count) files\(skipped > 0 ? " (skipped unreadable files: \(skipped) files)" : "")\nFolder: \(picker.store.directory.path) (<slug>.md, UTF-8, up to \(PromptStore.maxBytes / 1000) KB)"
        ProbeLog.log("AXIsProcessTrusted=\(trusted) prompts=\(prompts.count) skipped=\(skipped)")
    }

    @objc func requestPermission() {
        _ = AX.isTrusted(prompt: true)
        refreshStatus()
    }

    @objc func openSettings() { NSWorkspace.shared.open(AX.accessibilitySettingsURL) }
    @objc func openLog() { NSWorkspace.shared.open(ProbeLog.logURL) }

    @objc func openStore() {
        try? FileManager.default.createDirectory(at: picker.store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(picker.store.directory)
    }

    @objc func toggleHotKey() {
        if hotKeyCheckbox.state == .on {
            let status = hotKey.register { [weak self] in self?.picker.hotKeyPressed() }
            ProbeLog.log("RegisterEventHotKey(⌃⌥⌘P) -> OSStatus \(status)")
            if status != noErr { hotKeyCheckbox.state = .off }
        } else {
            hotKey.unregister()
            ProbeLog.log("hotkey unregistered")
        }
    }
}
