import AppIntents
import AppKit
import ApplicationServices

struct PromptEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "プロンプト"
    static var defaultQuery = PromptEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(id)")
    }

    init(_ prompt: StoredPrompt) {
        id = prompt.slug
        title = prompt.title
    }
}

struct PromptEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PromptEntity] {
        let prompts = PromptStore().list().prompts
        return identifiers.compactMap { id in prompts.first { $0.slug == id } }.map(PromptEntity.init)
    }

    func entities(matching string: String) async throws -> [PromptEntity] {
        PromptStore.filter(PromptStore().list().prompts, query: string).map(PromptEntity.init)
    }

    func suggestedEntities() async throws -> [PromptEntity] {
        PromptStore().list().prompts.map(PromptEntity.init)
    }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let reason: String
    var localizedStringResource: LocalizedStringResource { "挿入できません: \(reason)" }
}

struct InsertPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Promptを入力"
    static var description = IntentDescription("保存済みのプロンプトを、元のアプリの入力欄へ挿入します（送信はしません）。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "プロンプト")
    var prompt: PromptEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$prompt) を入力")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ProbeLog.section("Intent perform (prompt=\(prompt.id))")
        ProbeEnvironment.log()
        let text: String
        do {
            text = try PromptStore().text(prompt.id)
        } catch {
            ProbeLog.log("[perform] ABORT: \(error)")
            throw IntentFailure(reason: "\(error)")
        }
        ProbeLog.log("[perform] prompt=\(prompt.id) \(TextStats(text))")
        let target = try IntentTargetResolver.resolveAtPerform()
        IntentTargetResolver.insertAfterSpotlightCloses(text: text, target: target)
        return .result()
    }
}

/// Parameter-free entry point: selects the most recently modified readable Markdown file.
struct InsertLatestPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "最新のPromptを入力"
    static var description = IntentDescription("保存フォルダで更新日時が最も新しいプロンプトを、選択せずに入力します（送信はしません）。同じ更新日時の場合はslug順です。")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ProbeLog.section("Intent perform (latest prompt)")
        ProbeEnvironment.log()
        let store = PromptStore()
        guard let latest = store.list().prompts.first else {
            ProbeLog.log("[perform] ABORT: 読み込める保存済みプロンプトがありません")
            throw IntentFailure(reason: "読み込める保存済みプロンプトがありません")
        }
        let text: String
        do {
            text = try store.text(latest.slug)
        } catch {
            ProbeLog.log("[perform] ABORT: \(error)")
            throw IntentFailure(reason: "\(error)")
        }
        ProbeLog.log("[perform] latest prompt=\(latest.slug) modified=\(latest.modified) \(TextStats(text))")
        let target = try IntentTargetResolver.resolveAtPerform()
        IntentTargetResolver.insertAfterSpotlightCloses(text: text, target: target)
        return .result()
    }
}

enum IntentTargetResolver {
    static let invokerBundleIDs: Set<String> = ["com.apple.Spotlight", "com.apple.shortcuts", "com.apple.siri"]

    /// Uses only what AX reports at perform() time. If focus is on Spotlight (or anything we cannot
    /// attribute to the original field), fail instead of guessing.
    @MainActor
    static func resolveAtPerform() throws -> FocusTarget {
        guard AXIsProcessTrusted() else { throw IntentFailure(reason: ProbeError.notTrusted.description) }
        let front = NSWorkspace.shared.frontmostApplication
        ProbeLog.log("[perform] NSWorkspace.frontmost=\(front?.bundleIdentifier ?? "?") pid=\(front?.processIdentifier ?? -1)")

        var candidates: [FocusTarget] = []
        if case .success(let t) = Focus.captureFocusedTarget(enableElectronAX: true, retry: 0.3) {
            ProbeLog.log("[perform] AX focused: \(t.summary)")
            candidates.append(t)
        }
        if let front, front.processIdentifier != getpid(), !invokerBundleIDs.contains(front.bundleIdentifier ?? "") {
            Focus.enableManualAccessibility(pid: front.processIdentifier)
            let (err, el) = Focus.appFocusedElement(pid: front.processIdentifier)
            ProbeLog.log("[perform] frontmost app AXFocusedUIElement -> \(axErrorName(err))")
            if let el, let t = Focus.makeTarget(el, source: "NSWorkspace.frontmost.AXFocusedUIElement") {
                ProbeLog.log("[perform] frontmost focused: \(t.summary)")
                candidates.append(t)
            }
        }
        for t in candidates {
            if t.pid == getpid() || invokerBundleIDs.contains(t.bundleID ?? "") {
                ProbeLog.log("[perform] reject \(t.source): invoker/self")
                continue
            }
            if case .failure(let e) = Focus.checkEditable(t) {
                ProbeLog.log("[perform] reject \(t.source): \(e)")
                continue
            }
            Focus.logReport(t)
            return t
        }
        ProbeLog.log("[perform] ABORT: 元の入力対象を特定できない")
        throw IntentFailure(reason: "元の入力欄を特定できません（実行時のフォーカスがSpotlight等にあります）。ログを確認してください")
    }

    /// perform() returns first so Spotlight can close. Then we wait for the captured element itself to be focused again.
    @MainActor
    static func insertAfterSpotlightCloses(text: String, target: FocusTarget) {
        let start = Date()
        func poll() {
            let pid = try? Focus.systemWideFocusedApplicationPID().get()
            let elapsed = Date().timeIntervalSince(start)
            if pid == target.pid {
                ProbeLog.log("[deferred] focus returned to target app after \(String(format: "%.2f", elapsed))s")
                switch Focus.validateStillFocused(target) {
                case .failure(let e):
                    ProbeLog.log("[deferred] ABORT (書き込みなし): \(e)")
                    NSSound.beep()
                case .success:
                    let method = InsertionStrategy.method(for: target)
                    ProbeLog.log("[deferred] insertion method=\(method.rawValue)")
                    switch Inserter.insert(text, into: target, method: method) {
                    case .failure(let e): ProbeLog.log("[deferred] RESULT: failed \(e)"); NSSound.beep()
                    case .success(let o): ProbeLog.log("[deferred] RESULT: write=\(axErrorName(o.writeError)) verification=\(o.verification)")
                    }
                }
                return
            }
            if elapsed > 5 {
                let bid = pid.flatMap { Focus.appInfo(pid: $0).bundleID } ?? "?"
                ProbeLog.log("[deferred] ABORT: 5秒以内に対象アプリへフォーカスが戻らない (現在 pid=\(pid.map(String.init) ?? "?") \(bid))")
                NSSound.beep()
                return
            }
            schedule()
        }
        func schedule() {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                poll()
            }
        }
        schedule()
    }
}

struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: InsertLatestPromptIntent(),
            phrases: ["\(.applicationName)で最新のPromptを入力", "Insert latest prompt with \(.applicationName)"],
            shortTitle: "最新のPromptを入力",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: InsertPromptIntent(),
            phrases: ["\(.applicationName)でPromptを入力", "Insert prompt with \(.applicationName)"],
            shortTitle: "Promptを入力",
            systemImageName: "text.insert"
        )
    }
}
