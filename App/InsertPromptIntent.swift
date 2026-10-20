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
    static var title: LocalizedStringResource = "Ayre Go"
    static var description = IntentDescription("Insert the most recently modified saved prompt without choosing. Never sends. Ties are resolved by slug.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ProbeLog.section("Intent perform (latest prompt)")
        ProbeEnvironment.log()
        let store = PromptStore()
        guard let latest = store.list().prompts.first else {
            ProbeLog.log("[perform] ABORT: No readable saved prompts found")
            throw IntentFailure(reason: "No readable saved prompts found")
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
        ProbeLog.log("[perform] ABORT: Cannot identify the original text field")
        throw IntentFailure(reason: "Cannot identify the original text field; focus may still be on Spotlight. Check the log.")
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
                    ProbeLog.log("[deferred] ABORT (nothing written): \(e)")
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
                ProbeLog.log("[deferred] ABORT: Focus did not return to the target app within 5 seconds (current pid=\(pid.map(String.init) ?? "?") \(bid))")
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
