import ProbeCore
import AppKit
import ApplicationServices

let usage = """
usage:
  ayre --version
  ayre --help
  ayre capabilities --json
  ayre put <slug> --title <title> [--overwrite] [--store <directory>]
  ayre env | samples | prompts | export-samples [--force] | request-permission
  ayre inspect [--delay 5] [--no-electron-ax]
  ayre insert --sample short|markdown|long [--method auto|selected-text|value|codex-value] [--delay 5] [--no-electron-ax]

prompts: List saved prompts available in the app picker.
export-samples: Save sample-short / sample-markdown / sample-long for acceptance testing.

--method auto (default): codex-value for Codex (com.openai.codex), selected-text otherwise.

inspect/insert wait --delay seconds, then capture the focused element.
Focus the target field during the delay. Cmd+Tab preserves the cursor and selection.
Nothing is written if focus remains on the launching application (the terminal).
"""

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func flag(_ name: String) -> Bool { args.contains(name) }

func fail(_ message: String, code: Int32 = 1) -> Never {
    ProbeLog.log("FAILED: \(message)")
    exit(code)
}

func readStandardInput(maxBytes: Int) throws -> Data {
    var data = Data()
    while data.count <= maxBytes {
        let chunk = try FileHandle.standardInput.read(upToCount: min(64 * 1024, maxBytes + 1 - data.count)) ?? Data()
        if chunk.isEmpty { break }
        data.append(chunk)
    }
    return data
}

func waitForUser(seconds: Double) -> pid_t? {
    let startPID = try? Focus.systemWideFocusedApplicationPID().get()
    if let startPID {
        ProbeLog.log("start focused app: pid=\(startPID) bundleID=\(Focus.appInfo(pid: startPID).bundleID ?? "?")")
    }
    var remaining = Int(seconds.rounded(.up))
    while remaining > 0 {
        FileHandle.standardError.write(Data("  \(remaining) seconds until target capture...\n".utf8))
        RunLoop.current.run(until: Date().addingTimeInterval(min(1, Double(remaining))))
        remaining -= 1
    }
    return startPID
}

func captureAfterDelay() -> FocusTarget {
    let delay = Double(option("--delay") ?? "5") ?? 5
    let startPID = waitForUser(seconds: delay)
    switch Focus.captureFocusedTarget(enableElectronAX: !flag("--no-electron-ax")) {
    case .failure(let e): fail(e.description)
    case .success(let t):
        if let startPID, t.pid == startPID {
            fail("Focus has not left the launching application (pid=\(startPID)). Focus the target text field.")
        }
        Focus.logReport(t)
        return t
    }
}

guard let command = args.first else { print(usage); exit(2) }

func jsonString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
    let encoded = String(decoding: data, as: UTF8.self)
    return String(encoded.dropFirst().dropLast())
}

if command == "--version" {
    print(CLIContract.version)
    exit(0)
}
if command == "--help" || command == "-h" {
    print(usage)
    exit(0)
}
if command == "capabilities" {
    guard args.count == 2, args[1] == "--json" else { print(usage); exit(2) }
    print("{\"protocolVersion\":\(CLIContract.protocolVersion),\"version\":\(jsonString(CLIContract.version)),\"capabilities\":[\(CLIContract.capabilities.map(jsonString).joined(separator: ","))]}")
    exit(0)
}
if command == "put" {
    guard args.count >= 4, let slug = args.dropFirst().first else {
        FileHandle.standardError.write(Data("usage: ayre put <slug> --title <title> [--overwrite] [--store <directory>]\n".utf8)); exit(2)
    }
    var title: String?
    var overwrite = false
    var storeDirectory: URL?
    var i = 2
    while i < args.count {
        switch args[i] {
        case "--title":
            guard title == nil, i + 1 < args.count else { FileHandle.standardError.write(Data("--title must appear once and needs a value\n".utf8)); exit(2) }
            title = args[i + 1]
            i += 2
        case "--overwrite":
            guard !overwrite else { FileHandle.standardError.write(Data("--overwrite may appear only once\n".utf8)); exit(2) }
            overwrite = true; i += 1
        case "--store":
            guard storeDirectory == nil, i + 1 < args.count else { FileHandle.standardError.write(Data("--store must appear once and needs a directory\n".utf8)); exit(2) }
            storeDirectory = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            i += 2
        default:
            FileHandle.standardError.write(Data("Unknown put argument: \(args[i])\n".utf8)); exit(2)
        }
    }
    guard let title else { FileHandle.standardError.write(Data("--title is required\n".utf8)); exit(2) }
    guard PromptStore.isValidSlug(slug) else { FileHandle.standardError.write(Data("Invalid slug: \(slug)\n".utf8)); exit(2) }
    let bytes: Data
    do { bytes = try readStandardInput(maxBytes: PromptStore.maxBytes) }
    catch { FileHandle.standardError.write(Data("Could not read stdin: \(error)\n".utf8)); exit(4) }
    guard bytes.count <= PromptStore.maxBytes else { FileHandle.standardError.write(Data("Prompt exceeds the size limit (maximum \(PromptStore.maxBytes) bytes)\n".utf8)); exit(2) }
    guard let text = String(data: bytes, encoding: .utf8) else { FileHandle.standardError.write(Data("stdin must contain valid UTF-8\n".utf8)); exit(2) }
    let derivedTitle = PromptStore.title(of: text, slug: slug)
    guard title == derivedTitle else {
        FileHandle.standardError.write(Data("Title mismatch: --title must be \(jsonString(derivedTitle)), derived from the first '# ' heading in the first 20 lines or the slug. The text was not changed.\n".utf8)); exit(2)
    }
    do {
        try PromptStore(directory: storeDirectory ?? PromptStore.defaultDirectory).save(bytes, slug: slug, overwrite: overwrite)
        print("saved\t\(slug)\t\(bytes.count) bytes\t\(title)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        if case PromptStoreError.alreadyExists = error { exit(3) }
        if case PromptStoreError.invalidSlug = error { exit(2) }
        if case PromptStoreError.notUTF8 = error { exit(2) }
        if case PromptStoreError.tooLarge = error { exit(2) }
        exit(4)
    }
}

ProbeLog.section("CLI \(args.joined(separator: " "))")
ProbeEnvironment.log()

switch command {
case "env":
    break
case "samples":
    for s in SamplePrompts.all { print("\(s.id)\t\(s.title)\t\(TextStats(s.text))") }
case "prompts":
    let store = PromptStore()
    let (prompts, skipped) = store.list()
    print("dir\t\(store.directory.path)")
    for p in prompts { print("\(p.slug)\t\(p.title)\tutf8=\(p.utf8Count)\tlines=\(p.lineCount)") }
    if skipped > 0 { print("skipped\t\(skipped)") }
case "export-samples":
    let store = PromptStore()
    for s in SamplePrompts.all {
        do {
            try store.save(s.text, slug: "sample-\(s.id)", overwrite: flag("--force"))
            print("saved\tsample-\(s.id)\t\(TextStats(s.text))")
        } catch {
            print("skip\tsample-\(s.id)\t\(error)")
        }
    }
    print("dir\t\(store.directory.path)")
case "request-permission":
    let trusted = AX.isTrusted(prompt: true)
    print(trusted ? "trusted" : "Not granted: allow your terminal in the permission dialog or System Settings > Privacy & Security > Accessibility.")
case "inspect":
    let t = captureAfterDelay()
    switch Focus.checkEditable(t) {
    case .success: ProbeLog.log("editable: yes")
    case .failure(let e): ProbeLog.log("editable: no — \(e)")
    }
case "insert":
    guard let id = option("--sample"), let sample = SamplePrompts.find(id),
          let requested = InsertionStrategy.parse(option("--method") ?? "auto") else { print(usage); exit(2) }
    let t = captureAfterDelay()
    let method = requested ?? InsertionStrategy.method(for: t)
    ProbeLog.log("insertion method=\(method.rawValue) (requested=\(option("--method") ?? "auto"))")
    switch Inserter.insert(sample.text, into: t, method: method) {
    case .failure(let e): fail(e.description)
    case .success(let o):
        ProbeLog.log("RESULT: write=\(axErrorName(o.writeError)) verification=\(o.verification)")
        if case .mismatch = o.verification { exit(3) }
    }
default:
    print(usage)
    exit(2)
}
