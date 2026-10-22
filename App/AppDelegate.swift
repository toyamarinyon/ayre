import AppKit
import ApplicationServices
import CoreServices

/// One serial worker prevents overlapping AX queries and keeps them off the UI thread.
final class FocusMonitor {
    private let queue = DispatchQueue(label: "Ayre.focus-monitor", qos: .utility)
    private let stateLock = NSLock()
    private var enabled = false
    private var timer: DispatchSourceTimer?

    func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        self.enabled = enabled
        stateLock.unlock()
        timer?.cancel()
        timer = nil
        guard enabled else {
            // Drain any in-flight or already-enqueued tick before returning to the UI.
            queue.sync {}
            AyreLog.monitor("monitor disabled")
            return
        }
        AyreLog.monitor("monitor enabled interval=5s change-only with 60s heartbeat")
        let source = DispatchSource.makeTimerSource(queue: queue)
        var last: String?
        var lastWritten = Date.distantPast
        source.schedule(deadline: .now(), repeating: 5, leeway: .seconds(1))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let shouldRun = self.enabled
            self.stateLock.unlock()
            guard shouldRun else { return }
            autoreleasepool {
                let snapshot = Focus.monitorSnapshot()
                self.stateLock.lock()
                let shouldLog = self.enabled
                self.stateLock.unlock()
                guard shouldLog else { return }
                if snapshot != last || Date().timeIntervalSince(lastWritten) >= 60 {
                    AyreLog.monitor(snapshot)
                    last = snapshot
                    lastWritten = Date()
                }
            }
        }
        timer = source
        source.resume()
    }

    deinit { timer?.cancel() }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
    private let focusMonitor = FocusMonitor()
    private let focusMonitorCheckbox = NSButton(checkboxWithTitle: "Record background focus diagnostics", target: nil, action: nil)
    private let loginItemCheckbox = NSButton(checkboxWithTitle: "Start Ayre at login", target: nil, action: nil)
    private let automaticUpdatesCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates", target: nil, action: nil)
    private let updateStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let updateCheckButton = NSButton(title: "Check for Updates…", target: nil, action: nil)
    private let store = PromptStore()
    private let loginItemController = LoginItemController()
    private let updaterController = UpdaterController()
    private var statusItem: NSStatusItem?
    private var defaultLaunch: Bool?
    private var startupPresentation = StartupWindowPresentation()
    private var hasCenteredWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        recordDefaultLaunch(AppLifecycle.isDefaultLaunch(notification))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AyreLog.echoToStderr = false
        AyreLog.section("App launched")
        AyreEnvironment.log()
        if defaultLaunch == nil {
            recordDefaultLaunch(AppLifecycle.isDefaultLaunch(notification))
        }
        AyreLog.log("NSApplicationLaunchIsDefaultLaunchKey=\(defaultLaunch.map(String.init) ?? "unknown")")
        buildMenu()
        buildWindow()
        let monitoring = UserDefaults.standard.object(forKey: "focusMonitoringEnabled") as? Bool ?? false
        focusMonitorCheckbox.state = monitoring ? .on : .off
        focusMonitor.setEnabled(monitoring)
        updaterController.onScheduledUpdateAvailable = { [weak self] in self?.refreshUpdateSettings() }
        updaterController.onCanCheckForUpdatesChange = { [weak self] in self?.refreshUpdateSettings() }
        updaterController.start()
        refreshUpdateSettings()
        refreshStatus()
        refreshLoginItemStatus()
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
        AyreLog.log("Initial open event=\(eventSummary), kind=\(kind), defaultLaunch=\(defaultLaunch.map(String.init) ?? "unknown"), present=\(shouldPresent)")
        if shouldPresent {
            showWindow()
        }
        // Ayre has no untitled documents. Returning false keeps AppKit from opening one.
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let expected = AppLifecycle.activationExpected(in: event)
        let shouldShow = ReopenWindowPolicy.shouldPresentSettings(
            isReopenApplicationEvent: event?.eventClass == AEEventClass(kCoreEventClass)
                && event?.eventID == AEEventID(kAEReopenApplication),
            activationExpected: expected
        )
        let senderPID = event?.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value
        let senderBundle = senderPID.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "unknown"
        AyreLog.log("Reopen event=\(event?.eventID ?? 0) activationExpected=\(expected.map(String.init) ?? "missing") active=\(sender.isActive) sender=\(senderBundle) showSettings=\(shouldShow)")
        if shouldShow { showWindow() }
        return false
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
        refreshUpdateSettings()
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

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(toggleLoginItem(_:))
        automaticUpdatesCheckbox.target = self
        automaticUpdatesCheckbox.action = #selector(toggleAutomaticUpdateChecks(_:))
        updateCheckButton.target = self
        updateCheckButton.action = #selector(checkForUpdates(_:))

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
        focusMonitorCheckbox.target = self
        focusMonitorCheckbox.action = #selector(toggleFocusMonitor)
        let monitorHelp = NSTextField(wrappingLabelWithString: "Off by default. Enable while troubleshooting, then turn off when finished. Records app paths, versions, focus roles and API errors every 5 seconds when they change. No field content. Keeps two files of about 1 MB each. Your choice is saved across launches.")
        monitorHelp.preferredMaxLayoutWidth = 640
        monitorHelp.textColor = .secondaryLabelColor
        let monitorButtons = horizontalStack([
            makeButton("Mark Problem Now", action: #selector(markFocusProblem)),
            makeButton("Open Focus History", action: #selector(openFocusHistory)),
        ])

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

        let updateHeading = sectionHeading("Software updates")
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let versionLabel = NSTextField(labelWithString: "Current version: \(currentVersion)")

        let stack = NSStackView(views: [
            title, subtitle, sectionSeparator(), permissionHeading, statusLabel, permissionButtons, logButton,
            commandGroup, sectionSeparator(), loginHeading, loginGroup,
            sectionSeparator(), promptsHeading, storeLabel, storeButtons,
            sectionSeparator(), updateHeading, versionLabel, updateStatusLabel, updateCheckButton, automaticUpdatesCheckbox,
            sectionSeparator(), sectionHeading("Focus diagnostics"), focusMonitorCheckbox, monitorHelp, monitorButtons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        [subtitle, statusLabel, storeLabel, loginStatusLabel, installCommandsLabel, updateStatusLabel].forEach {
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
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
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
        let (prompts, skipped) = store.list()
        storeLabel.stringValue = "Saved prompts: \(prompts.count) files\(skipped > 0 ? " (\(skipped) unreadable files skipped)" : "")\nFolder: \(store.directory.path)\nFiles: <slug>.md, UTF-8, up to \(PromptStore.maxBytes / 1000) KB"
        AyreLog.log("AXIsProcessTrusted=\(trusted) prompts=\(prompts.count) skipped=\(skipped)")
    }

    private func refreshLoginItemStatus(operationError: String? = nil) {
        let snapshot = loginItemController.snapshot(operationError: operationError)
        loginItemCheckbox.state = snapshot.isToggleOn ? .on : .off
        loginStatusLabel.stringValue = snapshot.summary
        AyreLog.log("SMAppService.mainApp.status=\(snapshot.status)")
    }

    private func refreshUpdateSettings() {
        let available = updaterController.updater != nil
        if let configurationError = updaterController.configurationError {
            updateStatusLabel.stringValue = configurationError
        } else if let version = updaterController.scheduledUpdateAvailable {
            updateStatusLabel.stringValue = "Version \(version) is available. Choose Check for Updates… to review it."
        } else {
            updateStatusLabel.stringValue = ""
        }
        updateStatusLabel.textColor = .secondaryLabelColor
        updateCheckButton.isEnabled = available && updaterController.canCheckForUpdates
        automaticUpdatesCheckbox.isEnabled = available
        automaticUpdatesCheckbox.state = updaterController.automaticallyChecksForUpdates() ? .on : .off
    }

    @objc private func toggleAutomaticUpdateChecks(_ sender: NSButton) {
        updaterController.setAutomaticChecksEnabled(sender.state == .on)
        refreshUpdateSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        guard updaterController.canCheckForUpdates else {
            refreshUpdateSettings()
            return
        }
        updaterController.checkForUpdates(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(checkForUpdates(_:)) else { return true }
        return updaterController.updater != nil && updaterController.canCheckForUpdates
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

    @objc private func openLog() { NSWorkspace.shared.open(AyreLog.logURL) }

    @objc private func toggleFocusMonitor() {
        let enabled = focusMonitorCheckbox.state == .on
        UserDefaults.standard.set(enabled, forKey: "focusMonitoringEnabled")
        focusMonitor.setEnabled(enabled)
    }

    @objc private func markFocusProblem() {
        AyreLog.monitor("USER MARK: problem reported; inspect preceding focus history and ayre.log at this timestamp")
        AyreLog.log("USER MARK: focus problem reported")
    }

    @objc private func openFocusHistory() { NSWorkspace.shared.open(AyreLog.focusMonitorURL) }

    @objc private func openStore() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.directory)
    }

    @objc private func toggleLoginItem(_ sender: NSButton) {
        let snapshot = loginItemController.setEnabled(sender.state == .on)
        loginItemCheckbox.state = snapshot.isToggleOn ? .on : .off
        loginStatusLabel.stringValue = snapshot.summary
    }
}


extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
