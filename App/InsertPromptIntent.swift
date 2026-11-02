import AppIntents
import AppKit
import ApplicationServices

struct PromptEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Prompt"
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
    var localizedStringResource: LocalizedStringResource { "Cannot insert: \(reason)" }
}

struct InsertPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Ayre Pick"
    static var description = IntentDescription("Choose a saved prompt and insert it into the original text field without sending.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Prompt")
    var prompt: PromptEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Insert \(\.$prompt)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AyreLog.section("Intent perform (prompt=\(prompt.id))")
        AyreEnvironment.log()
        let text: String
        do {
            text = try PromptStore().text(prompt.id)
        } catch {
            AyreLog.log("[perform] ABORT: \(error)")
            throw IntentFailure(reason: "\(error)")
        }
        AyreLog.log("[perform] prompt=\(prompt.id) \(TextStats(text))")
        let target = try IntentTargetResolver.resolveAtPerform()
        try IntentTargetResolver.insertIntoTarget(text: text, target: target)
        return .result()
    }
}

/// Parameter-free entry point: selects the most recently modified readable Markdown file.
struct InsertLatestPromptIntent: AppIntent {
    static var title: LocalizedStringResource = "Ayre Go"
    static var description = IntentDescription("Insert the most recently modified saved prompt without choosing. Never sends. Ties are resolved by slug.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AyreLog.section("Intent perform (latest prompt)")
        AyreEnvironment.log()
        let store = PromptStore()
        guard let latest = store.list().prompts.first else {
            AyreLog.log("[perform] ABORT: No readable saved prompts found")
            throw IntentFailure(reason: "No readable saved prompts found")
        }
        let text: String
        do {
            text = try store.text(latest.slug)
        } catch {
            AyreLog.log("[perform] ABORT: \(error)")
            throw IntentFailure(reason: "\(error)")
        }
        AyreLog.log("[perform] latest prompt=\(latest.slug) modified=\(latest.modified) \(TextStats(text))")
        let target = try IntentTargetResolver.resolveAtPerform()
        try IntentTargetResolver.insertIntoTarget(text: text, target: target)
        return .result()
    }
}

enum IntentTargetResolver {
    static let invokerBundleIDs: Set<String> = ["com.apple.Spotlight", "com.apple.shortcuts", "com.apple.siri"]

    /// Prefer the field observed before Spotlight took focus. Cold starts retain direct capture.
    @MainActor
    static func resolveAtPerform() throws -> FocusTarget {
        guard AXIsProcessTrusted() else { throw IntentFailure(reason: AyreError.notTrusted.description) }
        if let remembered = FocusedFieldHistory.shared.snapshot() {
            AyreLog.log("[perform] frozen remembered target: \(remembered.summary)")
            return remembered
        }
        let front = NSWorkspace.shared.frontmostApplication
        AyreLog.log("[perform] NSWorkspace.frontmost=\(front?.bundleIdentifier ?? "?") pid=\(front?.processIdentifier ?? -1)")

        var candidates: [FocusTarget] = []
        switch Focus.captureFocusedTarget(enableElectronAX: true, retry: 0.3) {
        case .success(let t):
            AyreLog.log("[perform] AX focused: \(t.summary)")
            candidates.append(t)
        case .failure(let error):
            AyreLog.log("[perform] AX capture failed: \(error)")
        }
        if let front, front.processIdentifier != getpid(), !invokerBundleIDs.contains(front.bundleIdentifier ?? "") {
            Focus.enableManualAccessibility(pid: front.processIdentifier)
            let (err, el) = Focus.appFocusedElement(pid: front.processIdentifier)
            AyreLog.log("[perform] frontmost app AXFocusedUIElement -> \(axErrorName(err))")
            if let el, let t = Focus.makeTarget(el, source: "NSWorkspace.frontmost.AXFocusedUIElement") {
                AyreLog.log("[perform] frontmost focused: \(t.summary)")
                candidates.append(t)
            }
        }
        for t in candidates {
            if t.pid == getpid() || invokerBundleIDs.contains(t.bundleID ?? "") {
                AyreLog.log("[perform] reject \(t.source): invoker/self")
                continue
            }
            if case .failure(let e) = Focus.checkEditable(t) {
                AyreLog.log("[perform] reject \(t.source): \(e)")
                continue
            }
            Focus.logDiagnostic(id: "resolved", originalPID: t.pid)
            Focus.logReport(t)
            return t
        }
        AyreLog.log("[perform] ABORT: Cannot identify the original text field")
        diagnoseAfterFailure(originalPID: front?.processIdentifier)
        throw IntentFailure(reason: "Cannot identify the original text field; focus may still be on Spotlight. Check the log.")
    }

    /// Observe after returning the failure as well as immediately. No retries of insertion,
    /// activation, AX writes, or new target selection are performed by this diagnostic.
    @MainActor
    private static func diagnoseAfterFailure(originalPID: pid_t?) {
        let id = UUID().uuidString
        let start = Date()
        IntentInsertionActivity.begin()
        Task { @MainActor in
            defer { IntentInsertionActivity.end() }
            for delay: UInt64 in [0, 200_000_000, 600_000_000, 1_200_000_000] {
                do { try await Task.sleep(nanoseconds: delay) }
                catch { return }
                let elapsed = String(format: "%.2f", Date().timeIntervalSince(start))
                Focus.logDiagnostic(id: "\(id) +\(elapsed)s", originalPID: originalPID)
            }
            if let originalPID {
                Focus.logWindowTreeDiagnostic(pid: originalPID, id: id)
            }
        }
    }

    /// AX writes address the frozen element directly; foreground focus is irrelevant.
    @MainActor
    static func insertIntoTarget(text: String, target: FocusTarget) throws {
        IntentInsertionActivity.begin()
        defer { IntentInsertionActivity.end() }
        let method = InsertionStrategy.method(for: target)
        AyreLog.log("[direct] target: \(target.summary) method=\(method.rawValue)")
        switch Inserter.insert(text, into: target, method: method, requireFocused: false) {
        case .failure(let error):
            AyreLog.log("[direct] RESULT: failed \(error)")
            throw IntentFailure(reason: error.description)
        case .success(let outcome):
            AyreLog.log("[direct] RESULT: write=\(axErrorName(outcome.writeError)) verification=\(outcome.verification)")
        }
    }

}

struct AyreShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: InsertLatestPromptIntent(),
            phrases: ["Go with \(.applicationName)", "Insert latest prompt with \(.applicationName)"],
            shortTitle: "Ayre Go",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: InsertPromptIntent(),
            phrases: ["Pick a prompt with \(.applicationName)", "Insert prompt with \(.applicationName)"],
            shortTitle: "Ayre Pick",
            systemImageName: "text.insert"
        )
    }
}
