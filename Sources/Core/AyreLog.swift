import Foundation

/// Diagnostic log. Never pass the user's existing field content here; log lengths only.
public enum AyreLog {
    public static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Ayre", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ayre.log")
    }()

    public static var echoToStderr = true
    public static var focusMonitorURL: URL { logURL.deletingLastPathComponent().appendingPathComponent("focus-monitor.log") }

    /// Keep the current and previous file, each at most approximately 1 MiB.
    public static func monitor(_ message: String) {
        queue.sync {
            let url = focusMonitorURL
            let fm = FileManager.default
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size >= 1_048_576 {
                let previous = url.appendingPathExtension("previous")
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: url, to: previous)
            }
            let data = Data("\(formatter.string(from: Date())) \(message)\n".utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else { try? data.write(to: url) }
        }
    }
    private static let queue = DispatchQueue(label: "Ayre.log")
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
