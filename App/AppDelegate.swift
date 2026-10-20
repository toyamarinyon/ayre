import AppKit
import ApplicationServices
import CoreServices

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var window: NSWindow!
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let storeLabel = NSTextField(wrappingLabelWithString: "")
    private let loginStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let copyFeedbackLabel = NSTextField(labelWithString: "")
    private let installCommandsLabel = NSTextField(wrappingLabelWithString: """
    /plugin marketplace add toyamarinyon/ayre
    /plugin install ayre@ayre
    """)
    private let commandGroup = NSStackView()
    private let hotKeyCheckbox = NSButton(checkboxWithTitle: "Open the picker with ⌃⌥⌘P while Ayre is running", target: nil, action: nil)
    private let loginItemCheckbox = NSButton(checkboxWithTitle: "Start Ayre at login", target: nil, action: nil)
    private let hotKey = HotKey()
    private let picker = PickerController()
    private let loginItemController = LoginItemController()
    private var statusItem: NSStatusItem?
    private var defaultLaunch: Bool?
    private var startupPresentation = StartupWindowPresentation()
    private var hasCenteredWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        recordDefaultLaunch(AppLifecycle.isDefaultLaunch(notification))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProbeLog.echoToStderr = false
        ProbeLog.section("App launched")
        ProbeEnvironment.log()
        if defaultLaunch == nil {
            recordDefaultLaunch(AppLifecycle.isDefaultLaunch(notification))
        }
        ProbeLog.log("NSApplicationLaunchIsDefaultLaunchKey=\(defaultLaunch.map(String.init) ?? "unknown")")
        buildMenu()
        buildWindow()
        refreshStatus()
        refreshLoginItemStatus()
        hotKeyCheckbox.state = .on
        toggleHotKey()
        if startupPresentation.markWindowReady() {
            showWindow()
        }
    }

    private func recordDefaultLaunch(_ value: Bool?) {
        if let value { defaultLaunch = value }
        if startupPresentation.recordDefaultLaunch(value) {
            showWindow()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let openEvent = NSAppleEventManager.shared().currentAppleEvent
        let kind = AppLifecycle.initialOpenApplicationKind(from: openEvent)
        let shouldPresent = startupPresentation.recordOpenApplicationEvent(kind)
        let eventSummary = openEvent.map { "\($0.eventClass)/\($0.eventID)" } ?? "unknown"
        ProbeLog.log("Initial open event=\(eventSummary), kind=\(kind), defaultLaunch=\(defaultLaunch.map(String.init) ?? "unknown"), present=\(shouldPresent)")
        if shouldPresent {
            showWindow()
        }
        // Ayre has no untitled documents. Returning false keeps AppKit from opening one.
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Ayre Settings…", action: #selector(showWindow), keyEquivalent: "")
        menu.items.first?.target = self
        return menu
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshStatus()
        refreshLoginItemStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildWindow() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let width = max(320, min(680, visibleFrame.width - 40))
        let height = max(280, min(620, visibleFrame.height - 40))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Ayre Settings"
        window.minSize = NSSize(width: min(560, width), height: min(420, height))
        window.isReleasedWhenClosed = false
        window.delegate = self

        hotKeyCheckbox.target = self
        hotKeyCheckbox.action = #selector(toggleHotKey)
        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem(_:))

        let title = NSTextField(labelWithString: "Ayre")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Reusable prompts for the focused text field. Ayre never sends your message.")
        subtitle.textColor = .secondaryLabelColor

        let permissionHeading = sectionHeading("Accessibility permission")
        let permissionButtons = horizontalStack([
            makeButton("Request Permission", action: #selector(requestPermission)),
            makeButton("Open Accessibility Settings…", action: #selector(openAccessibilitySettings)),
            makeButton("Check Again", action: #selector(refreshStatus)),
        ])
        let logButton = makeButton("Open Diagnostic Log", action: #selector(openLog))

        installCommandsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        installCommandsLabel.textColor = .labelColor
        installCommandsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let copyButton = makeButton("Copy Install Commands", action: #selector(copyInstallCommands))
        commandGroup.orientation = .vertical
        commandGroup.alignment = .leading
        commandGroup.spacing = 6
        commandGroup.addArrangedSubview(NSTextField(labelWithString: "Claude Code plugin setup"))
        commandGroup.addArrangedSubview(installCommandsLabel)
        commandGroup.addArrangedSubview(horizontalStack([copyButton, copyFeedbackLabel]))

        let loginHeading = sectionHeading("Start at login")
        let loginSettingsButton = makeButton("Open Login Items Settings…", action: #selector(openLoginItemsSettings))
        let loginGroup = NSStackView(views: [loginItemCheckbox, loginStatusLabel, loginSettingsButton])
        loginGroup.orientation = .vertical
        loginGroup.alignment = .leading
        loginGroup.spacing = 6

        let promptsHeading = sectionHeading("Saved prompts")
        let storeButtons = horizontalStack([
            makeButton("Open Prompt Folder", action: #selector(openStore)),
            makeButton("Reload Prompts", action: #selector(refreshStatus)),
        ])

        let hotkeyHeading = sectionHeading("Picker shortcut")
        let help = NSTextField(wrappingLabelWithString: """
        Place the cursor in a text field. Use Spotlight: Ayre Go inserts the latest prompt; Ayre Pick lets you choose. Or press ⌃⌥⌘P, search, select with ↑↓, and press Return. Esc cancels.
        Insertion requires focus to return to the original field. If the target or field state cannot be verified, nothing is written.
        """)
        help.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            title, subtitle, sectionSeparator(), permissionHeading, statusLabel, permissionButtons, logButton,
            commandGroup, sectionSeparator(), loginHeading, loginGroup,
            sectionSeparator(), promptsHeading, storeLabel, storeButtons,
            sectionSeparator(), hotkeyHeading, hotKeyCheckbox, help,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        [subtitle, statusLabel, storeLabel, loginStatusLabel, help, installCommandsLabel].forEach {
            $0.preferredMaxLayoutWidth = 640
        }
        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        window.contentView = scrollView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    private func sectionHeading(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    private func sectionSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func horizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func updatePermissionStatusItem(isTrusted: Bool) {
        guard !isTrusted else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Ayre")
        item.button?.toolTip = "Ayre — Accessibility permission required"
        let menu = NSMenu()
        let status = NSMenuItem(title: "Accessibility permission is required", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(withTitle: "Open Ayre Settings…", action: #selector(showWindow), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ayre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = item
        item.menu = menu
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showWindow), keyEquivalent: ",")
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ayre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    @objc private func showWindow() {
        guard window != nil else { return }
        NSApp.setActivationPolicy(.regular)
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshStatus()
        refreshLoginItemStatus()
    }

    @objc private func refreshStatus() {
        let trusted = AXIsProcessTrusted()
        statusLabel.stringValue = trusted
            ? "Accessibility permission is granted. Ayre can insert prompts into the focused field."
            : "Accessibility permission is not granted. Request it here or open System Settings → Privacy & Security → Accessibility. After granting access, return to Ayre; the Claude Code setup commands will appear below."
        commandGroup.isHidden = !trusted
        updatePermissionStatusItem(isTrusted: trusted)
        let (prompts, skipped) = picker.store.list()
        storeLabel.stringValue = "Saved prompts: \(prompts.count) files\(skipped > 0 ? " (\(skipped) unreadable files skipped)" : "")\nFolder: \(picker.store.directory.path)\nFiles: <slug>.md, UTF-8, up to \(PromptStore.maxBytes / 1000) KB"
        ProbeLog.log("AXIsProcessTrusted=\(trusted) prompts=\(prompts.count) skipped=\(skipped)")
    }

    private func refreshLoginItemStatus(operationError: String? = nil) {
        let snapshot = loginItemController.snapshot(operationError: operationError)
        loginItemCheckbox.state = snapshot.isToggleOn ? .on : .off
        loginStatusLabel.stringValue = snapshot.summary
        ProbeLog.log("SMAppService.mainApp.status=\(snapshot.status)")
    }

    @objc private func requestPermission() {
        _ = AX.isTrusted(prompt: true)
        refreshStatus()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(AX.accessibilitySettingsURL)
    }

    @objc private func openLoginItemsSettings() {
        loginItemController.openSystemSettings()
    }

    @objc private func copyInstallCommands() {
        let commands = "/plugin marketplace add toyamarinyon/ayre\n/plugin install ayre@ayre"
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(commands, forType: .string) {
            copyFeedbackLabel.stringValue = "Copied. Paste into Claude Code."
        } else {
            copyFeedbackLabel.stringValue = "Could not copy the commands."
        }
    }

    @objc private func openLog() { NSWorkspace.shared.open(ProbeLog.logURL) }

    @objc private func openStore() {
        try? FileManager.default.createDirectory(at: picker.store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(picker.store.directory)
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        let snapshot = loginItemController.setEnabled(sender.state == .on)
        loginItemCheckbox.state = snapshot.isToggleOn ? .on : .off
        loginStatusLabel.stringValue = snapshot.summary
    }

    @objc private func toggleHotKey() {
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


extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
