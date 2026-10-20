import Foundation

/// A saved prompt: `<slug>.md` in the store directory. The file's bytes are inserted unchanged.
public struct StoredPrompt: Equatable {
    public let slug: String
    public let title: String
    public let modified: Date
    public let utf8Count: Int
    public let lineCount: Int
}

public enum PromptStoreError: Error, CustomStringConvertible {
    case invalidSlug(String)
    case notFound(String)
    case tooLarge(String, Int)
    case notUTF8(String)
    case alreadyExists(String)

    public var description: String {
        switch self {
        case .invalidSlug(let s): return "slugが不正です: \(s)"
        case .notFound(let s): return "プロンプトが見つかりません: \(s)"
        case .tooLarge(let s, let n): return "プロンプトが大きすぎます: \(s) (\(n) bytes > \(PromptStore.maxBytes))"
        case .notUTF8(let s): return "UTF-8として読めません: \(s)"
        case .alreadyExists(let s): return "既に存在します: \(s)"
        }
    }
}

public struct PromptStore {
    public static let maxBytes = 1_000_000
    public static let fileExtension = "md"

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptInsertProbe/Prompts", isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = PromptStore.defaultDirectory) {
        self.directory = directory
    }

    public static func isValidSlug(_ slug: String) -> Bool {
        guard let first = slug.unicodeScalars.first, slug.unicodeScalars.count <= 128,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return slug.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) }
            && !slug.contains("..")
    }

    /// Title = first ATX level-1 heading in the first lines, otherwise the slug.
    public static func title(of text: String, slug: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return slug
    }

    /// Case- and width-insensitive; every whitespace-separated term must match the title or slug.
    public static func filter(_ prompts: [StoredPrompt], query: String) -> [StoredPrompt] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return prompts }
        return prompts.filter { p in
            terms.allSatisfy { term in
                [p.title, p.slug].contains { $0.range(of: term, options: [.caseInsensitive, .widthInsensitive]) != nil }
            }
        }
    }

    public func url(for slug: String) throws -> URL {
        guard Self.isValidSlug(slug) else { throw PromptStoreError.invalidSlug(slug) }
        return directory.appendingPathComponent("\(slug).\(Self.fileExtension)")
    }

    /// Newest first. Files that are not valid prompts are skipped and counted.
    public func list() -> (prompts: [StoredPrompt], skipped: Int) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return ([], 0)
        }
        var prompts: [StoredPrompt] = []
        var skipped = 0
        for url in urls where url.pathExtension == Self.fileExtension {
            let slug = url.deletingPathExtension().lastPathComponent
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let prompt = try? load(slug).prompt else {
                skipped += 1
                continue
            }
            prompts.append(StoredPrompt(slug: prompt.slug, title: prompt.title,
                                        modified: values.contentModificationDate ?? .distantPast,
                                        utf8Count: prompt.utf8Count, lineCount: prompt.lineCount))
        }
        prompts.sort { $0.modified != $1.modified ? $0.modified > $1.modified : $0.slug < $1.slug }
        return (prompts, skipped)
    }

    /// Re-reads the file so the inserted text is what is on disk at selection time.
    public func text(_ slug: String) throws -> String {
        try load(slug).text
    }

    public func save(_ text: String, slug: String, overwrite: Bool = false) throws {
        let url = try url(for: slug)
        let data = Data(text.utf8)
        guard data.count <= Self.maxBytes else { throw PromptStoreError.tooLarge(slug, data.count) }
        if !overwrite, FileManager.default.fileExists(atPath: url.path) { throw PromptStoreError.alreadyExists(slug) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func load(_ slug: String) throws -> (text: String, prompt: StoredPrompt) {
        let url = try url(for: slug)
        guard let data = FileManager.default.contents(atPath: url.path) else { throw PromptStoreError.notFound(slug) }
        guard data.count <= Self.maxBytes else { throw PromptStoreError.tooLarge(slug, data.count) }
        guard let text = String(data: data, encoding: .utf8) else { throw PromptStoreError.notUTF8(slug) }
        let lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
        return (text, StoredPrompt(slug: slug, title: Self.title(of: text, slug: slug), modified: .distantPast,
                                   utf8Count: data.count, lineCount: lines))
    }
}
