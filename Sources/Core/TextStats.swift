import Foundation

public struct TextStats: CustomStringConvertible {
    public let graphemes: Int
    public let utf16: Int
    public let utf8Bytes: Int
    public let lines: Int

    public init(_ text: String) {
        graphemes = text.count
        utf16 = text.utf16.count
        utf8Bytes = text.utf8.count
        lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    public var description: String {
        "chars=\(graphemes) utf16=\(utf16) utf8Bytes=\(utf8Bytes) lines=\(lines)"
    }
}

public enum StrictCompare {
    /// Metadata equality is diagnostic evidence, never proof that a field is empty.
    public static func matchesLabel(_ value: String, label: String) -> Bool {
        guard !label.isEmpty else { return false }
        return equal(value, label) || equal(value, label + "\n") || equal(value, label + "\r\n")
    }

    /// Classify only removal of one terminal line ending; never normalize other differences.
    public static func removedTerminalLineEnding(actual: String, expected: String) -> String? {
        for ending in ["\r\n", "\n", "\r"] where expected.hasSuffix(ending) {
            let prefix = (expected as NSString).substring(to: expected.utf16.count - ending.utf16.count)
            if equal(actual, prefix) { return ending == "\r\n" ? "CRLF" : ending == "\n" ? "LF" : "CR" }
        }
        return nil
    }

    /// Code-unit comparison. Swift `==` on String uses canonical equivalence, which would hide NFC/NFD changes.
    public static func equal(_ a: String, _ b: String) -> Bool {
        a.utf16.elementsEqual(b.utf16)
    }

    public static func firstDifferenceUTF16(_ a: String, _ b: String) -> Int? {
        var i = 0
        var ia = a.utf16.makeIterator()
        var ib = b.utf16.makeIterator()
        while true {
            let ca = ia.next(), cb = ib.next()
            if ca == nil && cb == nil { return nil }
            if ca != cb { return i }
            i += 1
        }
    }

    /// Expected field content after replacing `range` (UTF-16) of `before` with `inserted`.
    public static func expected(before: String, range: NSRange, inserted: String) -> String? {
        let ns = before as NSString
        guard range.location >= 0, range.length >= 0,
              range.location <= ns.length, range.length <= ns.length - range.location else { return nil }
        return ns.replacingCharacters(in: range, with: inserted)
    }

    public static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = NSRange(location: 0, length: (haystack as NSString).length)
        let ns = haystack as NSString
        while true {
            let r = ns.range(of: needle, options: .literal, range: search)
            if r.location == NSNotFound { return count }
            count += 1
            let next = NSMaxRange(r)
            search = NSRange(location: next, length: ns.length - next)
        }
    }
}
