import AppKit
import ProbeCore

/// Test receiver: independently compares its own NSTextView content against the expected result,
/// without going through the Accessibility API.
final class Receiver: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    enum Scenario: Int, CaseIterable {
        case empty, middle, selection
        var title: String { ["空の入力欄", "既存本文の途中へ挿入", "選択範囲の置換"][rawValue] }
        var baseline: (String, NSRange) {
            switch self {
            case .empty: return ("", NSRange(location: 0, length: 0))
            case .middle:
                let head = "BEFORE-前半テキスト😀-"
                return (head + "-AFTER-後半テキスト\n二行目", NSRange(location: (head as NSString).length, length: 0))
            case .selection:
                let head = "BEFORE-"
                let selected = "[置換される選択範囲🇯🇵]"
                return (head + selected + "-AFTER", NSRange(location: (head as NSString).length, length: (selected as NSString).length))
            }
        }
    }

    var window: NSWindow!
    let textView = NSTextView()
    let samplePopup = NSPopUpButton()
    let scenarioPopup = NSPopUpButton()
    let resultLabel = NSTextField(wrappingLabelWithString: "シナリオを準備してください")
    var baseline: (String, NSRange)?
    var edits: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "PromptInsertProbe Receiver"
        SamplePrompts.all.forEach { samplePopup.addItem(withTitle: "\($0.title) (\($0.id))") }
        Scenario.allCases.forEach { scenarioPopup.addItem(withTitle: $0.title) }

        let prepare = NSButton(title: "シナリオを準備", target: self, action: #selector(prepare))
        let verify = NSButton(title: "検証", target: self, action: #selector(verify))
        let controls = NSStackView(views: [samplePopup, scenarioPopup, prepare, verify])

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [controls, scroll, resultLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        window.contentView = stack
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        resultLabel.preferredMaxLayoutWidth = 690

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var sample: SamplePrompt { SamplePrompts.all[samplePopup.indexOfSelectedItem] }

    @objc func prepare() {
        let scenario = Scenario(rawValue: scenarioPopup.indexOfSelectedItem)!
        let (text, range) = scenario.baseline
        textView.string = text
        textView.setSelectedRange(range)
        window.makeFirstResponder(textView)
        baseline = (text, range)
        edits = []
        let msg = "準備完了: \(scenario.title) / 期待する挿入: \(sample.title)。ターミナルで insert を実行し、Cmd+Tab でこのウィンドウに戻ってください（クリックするとカーソルが動きます）"
        resultLabel.stringValue = msg
        print("[receiver] \(msg)")
    }

    @objc func verify() {
        guard let (text, range) = baseline,
              let expected = StrictCompare.expected(before: text, range: range, inserted: sample.text) else { return }
        let actual = textView.string
        var lines: [String] = []
        if StrictCompare.equal(actual, expected) {
            lines.append("一致: UTF-16単位で期待値と完全一致（\(TextStats(actual))）")
        } else {
            lines.append("不一致: expected \(TextStats(expected)) / actual \(TextStats(actual))")
            if let d = StrictCompare.firstDifferenceUTF16(actual, expected) {
                let ns = actual as NSString
                let ctx = ns.substring(with: NSRange(location: max(0, d - 10), length: min(30, ns.length - max(0, d - 10))))
                lines.append("最初の差分 UTF-16 offset=\(d) 付近: \(ctx.debugDescription)")
            }
            lines.append("挿入本文の出現回数: \(StrictCompare.occurrences(of: sample.text, in: actual))")
        }
        lines.append("編集イベント \(edits.count)件: \(edits.joined(separator: " / "))")
        resultLabel.stringValue = lines.joined(separator: "\n")
        lines.forEach { print("[receiver] \($0)") }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        let r = replacementString ?? ""
        let isSample = SamplePrompts.all.first { StrictCompare.equal($0.text, r) }?.id ?? "-"
        edits.append("{\(range.location),\(range.length)}→utf16=\(r.utf16.count) sample=\(isSample)")
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let receiver = Receiver()
app.delegate = receiver
let menu = NSMenu()
let appItem = NSMenuItem()
menu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
let editItem = NSMenuItem()
menu.addItem(editItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editItem.submenu = editMenu
app.mainMenu = menu
app.run()
