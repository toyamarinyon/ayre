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
    let hotKeyCheckbox = NSButton(checkboxWithTitle: "グローバルホットキー ⌃⌥⌘P で選択パネルを表示（このアプリ起動中のみ）", target: nil, action: nil)
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
        window.title = "PromptInsertProbe"
        window.isReleasedWhenClosed = false
        hotKeyCheckbox.target = self
        hotKeyCheckbox.action = #selector(toggleHotKey)

        let permissionButtons = NSStackView(views: [
            NSButton(title: "権限を再確認", target: self, action: #selector(refreshStatus)),
            NSButton(title: "権限を要求", target: self, action: #selector(requestPermission)),
            NSButton(title: "システム設定を開く", target: self, action: #selector(openSettings)),
            NSButton(title: "ログを開く", target: self, action: #selector(openLog)),
        ])
        let storeButtons = NSStackView(views: [
            NSButton(title: "保存先を開く", target: self, action: #selector(openStore)),
            NSButton(title: "一覧を再読み込み", target: self, action: #selector(refreshStatus)),
        ])
        let help = NSTextField(wrappingLabelWithString: """
        使い方：入力欄にカーソルを置き、⌃⌥⌘P で選択パネルを開く（検索 → ↑↓ → Return、Escで中止）。またはSpotlightで「Promptを入力」を実行。
        挿入は元の入力欄にフォーカスが戻った場合だけ行い、送信はしません。対象や入力欄の状態を判別できない場合は書き込みません。
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
        appMenu.addItem(withTitle: "ウィンドウを表示", action: #selector(showWindow), keyEquivalent: "0")
        appMenu.addItem(withTitle: "PromptInsertProbe を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil) }

    @objc func refreshStatus() {
        let trusted = AXIsProcessTrusted()
        statusLabel.stringValue = trusted
            ? "Accessibility権限: 許可済み（\(Bundle.main.bundlePath)）"
            : "Accessibility権限: 未許可。「権限を要求」またはシステム設定 > プライバシーとセキュリティ > アクセシビリティ で PromptInsertProbe を許可してください。再ビルドで署名が変わると許可が無効になることがあります。"
        let (prompts, skipped) = picker.store.list()
        storeLabel.stringValue = "保存済みプロンプト: \(prompts.count)件\(skipped > 0 ? "（読めないファイル \(skipped)件を除外）" : "")\n保存先: \(picker.store.directory.path)（<slug>.md、UTF-8、\(PromptStore.maxBytes / 1000)KBまで）"
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
