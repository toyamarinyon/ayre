import Foundation

/// Diagnostic log. Never pass the user's existing field content here; log lengths only.
public enum ProbeLog {
    public static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PromptInsertProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("probe.log")
    }()

    public static var echoToStderr = true
    private static let queue = DispatchQueue(label: "PromptInsertProbe.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func log(_ message: String) {
        queue.sync {
            let line = "\(formatter.string(from: Date())) [\(ProcessInfo.processInfo.processName):\(getpid())] \(message)\n"
            let data = Data(line.utf8)
            if echoToStderr { FileHandle.standardError.write(data) }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    public static func section(_ title: String) {
        log("===== \(title) =====")
    }
}
