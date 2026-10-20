import AppKit
import ApplicationServices
import ProbeCore

let usage = """
usage:
  PromptInsertProbeCLI env
  PromptInsertProbeCLI samples
  PromptInsertProbeCLI prompts
  PromptInsertProbeCLI export-samples [--force]
  PromptInsertProbeCLI request-permission
  PromptInsertProbeCLI inspect [--delay 5] [--no-electron-ax]
  PromptInsertProbeCLI insert --sample short|markdown|long [--method auto|selected-text|value|codex-value] [--delay 5] [--no-electron-ax]

prompts: 保存済みプロンプト（アプリの選択UIに出るもの）の一覧。
export-samples: サンプル3種を sample-short / sample-markdown / sample-long として保存先へ書き出す（受け入れ検証用）。

--method auto（既定）: Codex (com.openai.codex) は codex-value、それ以外は selected-text。

inspect/insert は --delay 秒待ってから、その時点でフォーカスされている要素を対象にします。
待機中に対象アプリの入力欄へフォーカスしてください（Cmd+Tab ならカーソル位置・選択範囲が保たれます）。
開始時と同じアプリ（=起動したターミナル）にフォーカスが残っている場合は何もしません。
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

func waitForUser(seconds: Double) -> pid_t? {
    let startPID = try? Focus.systemWideFocusedApplicationPID().get()
    if let startPID {
        ProbeLog.log("start focused app: pid=\(startPID) bundleID=\(Focus.appInfo(pid: startPID).bundleID ?? "?")")
    }
    var remaining = Int(seconds.rounded(.up))
    while remaining > 0 {
        FileHandle.standardError.write(Data("  \(remaining)秒後に対象を取得します…\n".utf8))
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
            fail("フォーカスが起動元アプリ(pid=\(startPID))から移っていません。対象の入力欄へフォーカスしてください")
        }
        Focus.logReport(t)
        return t
    }
}

guard let command = args.first else { print(usage); exit(2) }
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
    print(trusted ? "trusted" : "未許可：表示されたダイアログ、または システム設定 > プライバシーとセキュリティ > アクセシビリティ でターミナルアプリを許可してください")
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
