import AppKit
import ApplicationServices

@MainActor
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { (delegate as? PickerController)?.cancel() }
}

@MainActor
final class PromptTableView: NSTableView {
    var confirm: (() -> Void)?
    var dismiss: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty {
            switch event.keyCode {
            case 36, 76: confirm?(); return
            case 53: dismiss?(); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}

/// Saved-prompt picker. The target is captured before the panel is shown; the panel is a
/// non-activating panel (the verified mode), so the original app stays active.
@MainActor
final class PickerController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var store = PromptStore()
    private var panel: KeyablePanel?
    private var target: FocusTarget?
    private var all: [StoredPrompt] = []
    private var shown: [StoredPrompt] = []
    private let search = NSSearchField()
    private let table = PromptTableView()
    private var isInserting = false
    private var skippedCount = 0
    private let footer = NSTextField(wrappingLabelWithString: "")
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    func hotKeyPressed() {
        guard panel == nil, !isInserting else { return }
        target = nil
        AyreLog.section("Picker")
        // Captured before any UI of ours is shown, so focus still belongs to the original app.
        var errorText: String?
        switch Focus.captureFocusedTarget(enableElectronAX: true) {
        case .failure(let e):
            errorText = e.description
        case .success(let t):
            Focus.logReport(t)
            if t.pid == getpid() {
                errorText = "Focus is on Ayre itself"
            } else if case .failure(let e) = Focus.checkEditable(t) {
                errorText = e.description
            } else {
                target = t
            }
        }
        if let errorText { AyreLog.log("capture failed: \(errorText)") }
        let listed = store.list()
        skippedCount = listed.skipped
        all = listed.prompts
        shown = all
        AyreLog.log("prompts=\(all.count) skipped=\(listed.skipped)")
        show(errorText: errorText, skipped: listed.skipped)
    }

    private func show(errorText: String?, skipped: Int) {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                                 styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                                 backing: .buffered, defer: false)
        panel.title = "Ayre Pick"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        var views: [NSView] = []
        if let errorText {
            views.append(NSTextField(wrappingLabelWithString: "Cannot insert: \(errorText)"))
            footer.stringValue = "Place the cursor in a text field, then press ⌃⌥⌘P. Press Esc to close."
        } else {
            search.placeholderString = "Search titles and slugs"
            search.stringValue = ""
            search.delegate = self
            views.append(search)
            views.append(makeTable())
            footer.stringValue = footerText(skipped: skipped)
        }
        views.append(footer)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        views.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true }
        panel.contentView = stack
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        if errorText == nil {
            table.reloadData()
            selectRow(0)
            panel.makeFirstResponder(search)
        }
        logFocusState("panel shown")
    }

    private func footerText(skipped: Int) -> String {
        let where_ = "Target: \(target?.appName ?? "?")"
        if all.isEmpty {
            return "\(where_)\nNo saved prompts. Place <slug>.md files in \(store.directory.path)."
        }
        let skippedText = skipped > 0 ? "  Unreadable files skipped: \(skipped)" : ""
        if shown.isEmpty { return "No matching prompts. Esc: cancel" }
        return "\(where_)  \(shown.count) prompts  Return: insert (never sends)  ↑↓: select  Esc: cancel\(skippedText)"
    }

    private func makeTable() -> NSView {
        if table.tableColumns.isEmpty {
            for (id, title, width) in [("title", "Title", 260.0), ("slug", "slug", 130.0), ("info", "Updated / Lines", 140.0)] {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                column.width = width
                table.addTableColumn(column)
            }
            table.confirm = { [weak self] in self?.insertSelected() }
            table.dismiss = { [weak self] in self?.cancel() }
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.doubleAction = #selector(insertSelected)
            table.allowsEmptySelection = false
            table.usesAlternatingRowBackgroundColors = true
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let p = shown[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "title": text = p.title
        case "slug": text = p.slug
        default: text = "\(Self.dateFormat.string(from: p.modified))  \(p.lineCount) lines"
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func controlTextDidChange(_ obj: Notification) {
        shown = PromptStore.filter(all, query: search.stringValue)
        footer.stringValue = footerText(skipped: skippedCount)
        table.reloadData()
        selectRow(0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): selectRow(table.selectedRow + 1); return true
        case #selector(NSResponder.moveUp(_:)): selectRow(table.selectedRow - 1); return true
        case #selector(NSResponder.insertNewline(_:)): insertSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): cancel(); return true
        default: return false
        }
    }

    private func selectRow(_ row: Int) {
        guard !shown.isEmpty else { return }
        let clamped = max(0, min(row, shown.count - 1))
        table.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        table.scrollRowToVisible(clamped)
    }

    private func logFocusState(_ label: String) {
        let pid = try? Focus.systemWideFocusedApplicationPID().get()
        let front = NSWorkspace.shared.frontmostApplication
        var sameElement = "n/a"
        if let target {
            let (_, el) = Focus.appFocusedElement(pid: target.pid)
            sameElement = el.map { CFEqual($0, target.element) ? "true" : "false" } ?? "nil"
        }
        AyreLog.log("[\(label)] AX focused app pid=\(pid.map(String.init) ?? "?") (\(pid.flatMap { Focus.appInfo(pid: $0).bundleID } ?? "?")) NSWorkspace.frontmost=\(front?.bundleIdentifier ?? "?") originalApp.AXFocusedUIElement==target: \(sameElement) NSApp.isActive=\(NSApp.isActive)")
    }

    @objc private func insertSelected() {
        guard !isInserting, let target, shown.indices.contains(table.selectedRow) else { return }
        let prompt = shown[table.selectedRow]
        let text: String
        do {
            text = try store.text(prompt.slug)
        } catch {
            AyreLog.log("ABORT (nothing written): \(error)")
            footer.stringValue = "Cannot read: \(error)"
            NSSound.beep()
            return
        }
        AyreLog.log("selected prompt=\(prompt.slug) \(TextStats(text))")
        logFocusState("before close")
        isInserting = true
        close()
        waitForFocusReturn(target: target, deadline: Date().addingTimeInterval(2.0)) { [weak self] in
            defer {
                self?.target = nil
                self?.isInserting = false
            }
            self?.logFocusState("after close")
            switch Focus.validateStillFocused(target) {
            case .failure(let e):
                AyreLog.log("ABORT (nothing written): \(e)")
                NSSound.beep()
            case .success:
                let method = InsertionStrategy.method(for: target)
                AyreLog.log("insertion method=\(method.rawValue)")
                switch Inserter.insert(text, into: target, method: method) {
                case .failure(let e):
                    AyreLog.log("RESULT: failed \(e)")
                    NSSound.beep()
                case .success(let o):
                    AyreLog.log("RESULT: write=\(axErrorName(o.writeError)) verification=\(o.verification)")
                }
            }
        }
    }

    /// Polls (without writing) until the original app is focused again or the deadline passes.
    private func waitForFocusReturn(target: FocusTarget, deadline: Date, then: @escaping @MainActor () -> Void) {
        let pid = try? Focus.systemWideFocusedApplicationPID().get()
        if pid == target.pid || Date() >= deadline {
            then()
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            self?.waitForFocusReturn(target: target, deadline: deadline, then: then)
        }
    }

    @objc func cancel() {
        AyreLog.log("cancelled")
        close()
        target = nil
    }

    private func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        if panel != nil { cancel() }
    }
}
