import AppKit
import ApplicationServices

public enum Verification: CustomStringConvertible {
    case exact
    case mismatch(String)
    case unverifiable(String)

    public var description: String {
        switch self {
        case .exact: return "EXACT（AXValueの挿入前後をUTF-16単位で厳密比較して一致）"
        case .mismatch(let d): return "MISMATCH（\(d)）"
        case .unverifiable(let r): return "UNVERIFIABLE（\(r)）"
        }
    }
}

public struct InsertOutcome {
    public let writeError: AXError
    public let elapsed: TimeInterval
    public let verification: Verification
}

/// Inserts through AXSelectedText or explicit AXValue modes. No pasteboard,
/// synthetic key events, Return, or write retries through another method.
public enum Inserter {
    public enum Method: String {
        case selectedText = "AXSelectedText"
        case value = "AXValue"
        case emptyValue = "AXValue (空欄確認済み)"
        case codexValue = "AXValue (Codex空欄自動判別)"
    }

    public static func insert(_ text: String, into target: FocusTarget, method: Method = .selectedText) -> Result<InsertOutcome, ProbeError> {
        if case .failure(let e) = Focus.checkEditable(target) { return .failure(e) }
        let el = target.element
        ProbeLog.log("insert: text \(TextStats(text))")

        let beforeValue = AX.string(el, kAXValueAttribute)
        let beforeRange = AX.range(el, kAXSelectedTextRangeAttribute)
        let beforeCount = AX.int(el, kAXNumberOfCharactersAttribute)
        ProbeLog.log("before: value=\(beforeValue.map { "String(\(TextStats($0)))" } ?? "unreadable") selectedRange=\(beforeRange.map { "{\($0.location),\($0.length)}" } ?? "unreadable") AXNumberOfCharacters=\(beforeCount.map(String.init) ?? "unreadable")")
        if let beforeValue {
            for attribute in ["AXPlaceholderValue", kAXTitleAttribute as String, kAXDescriptionAttribute as String] {
                let (error, raw) = AX.copy(el, attribute)
                let label = AX.string(el, attribute)
                ProbeLog.log("empty diagnostic: \(attribute) read=\(axErrorName(error)) shape=\(AX.describeShape(raw)) valueMatchesLabelOrLabelWithLF=\(label.map { StrictCompare.matchesLabel(beforeValue, label: $0) } ?? false)（一致だけでは空欄と判定しない）")
            }
        }

        let payload: String
        var logicalEmpty = method == .emptyValue
        var codexDecision: CodexFieldState.Decision?
        if method != .selectedText {
            let (error, settable) = AX.isSettable(el, kAXValueAttribute)
            guard error == .success, settable else {
                return .failure(.notEditable("AXValue settable=\(settable) AXError=\(axErrorName(error))"))
            }
            guard let beforeValue, let beforeRange, let beforeCount,
                  beforeCount == beforeValue.utf16.count,
                  let expected = StrictCompare.expected(before: beforeValue,
                      range: NSRange(location: beforeRange.location, length: beforeRange.length), inserted: text) else {
                return .failure(.targetChanged("AXValue全文・文字数・選択範囲を確認できないため書き込み中止"))
            }
            if method == .codexValue, target.bundleID == InsertionStrategy.codexBundleID {
                let decision = CodexFieldState.inspect(target)
                ProbeLog.log("Codex field state=\(decision.rawValue)（子要素の編集属性による判別）")
                guard decision != .unknown else {
                    return .failure(.targetChanged("Codexの入力構造を判別できないため書き込み中止"))
                }
                codexDecision = decision
                logicalEmpty = decision == .empty
                payload = logicalEmpty ? text : expected
            } else if method == .emptyValue {
                // Explicit user-selected mode. Never infer emptiness from matching UI text alone.
                let labels = ["AXPlaceholderValue", kAXTitleAttribute as String, kAXDescriptionAttribute as String]
                    .compactMap { AX.string(el, $0) }
                guard beforeRange.location == 0, beforeRange.length == 0,
                      beforeValue.isEmpty || labels.contains(where: { StrictCompare.matchesLabel(beforeValue, label: $0) }) else {
                    return .failure(.targetChanged("空欄確認モード: 本文が空/UIラベル一致、かつ選択範囲が{0,0}という条件を満たさないため中止"))
                }
                payload = text
                ProbeLog.log("explicit empty-field mode: ユーザーによる空欄確認を前提にサンプルのみ書き込む")
            } else {
                payload = expected
            }
            // Recheck the snapshot and focus immediately before replacing the whole value.
            if case .failure(let error) = Focus.validateStillFocused(target) { return .failure(error) }
            guard let current = AX.string(el, kAXValueAttribute), StrictCompare.equal(current, beforeValue),
                  let currentRange = AX.range(el, kAXSelectedTextRangeAttribute),
                  currentRange.location == beforeRange.location, currentRange.length == beforeRange.length,
                  AX.int(el, kAXNumberOfCharactersAttribute) == beforeCount else {
                return .failure(.targetChanged("読み取り後に本文または選択範囲が変化したため書き込み中止"))
            }
            if let codexDecision {
                guard CodexFieldState.inspect(target) == codexDecision,
                      let finalValue = AX.string(el, kAXValueAttribute), StrictCompare.equal(finalValue, beforeValue),
                      let finalRange = AX.range(el, kAXSelectedTextRangeAttribute),
                      finalRange.location == beforeRange.location, finalRange.length == beforeRange.length else {
                    return .failure(.targetChanged("書き込み直前にCodexの状態が変化、または判別不能"))
                }
            }
        } else {
            payload = text
        }
        ProbeLog.log("write method=\(method.rawValue) payload \(TextStats(payload))")
        AXUIElementSetMessagingTimeout(el, 10)
        let start = Date()
        let attribute = method == .selectedText ? kAXSelectedTextAttribute : kAXValueAttribute
        let err = AXUIElementSetAttributeValue(el, attribute as CFString, payload as CFString)
        let elapsed = Date().timeIntervalSince(start)
        ProbeLog.log("AXUIElementSetAttributeValue(\(method.rawValue)) -> \(axErrorName(err)) in \(String(format: "%.3f", elapsed))s")
        guard err == .success else { return .failure(.writeFailed(err)) }

        let verification = verify(el, text: text,
            beforeValue: logicalEmpty ? "" : beforeValue,
            beforeRange: logicalEmpty ? CFRange(location: 0, length: 0) : beforeRange,
            beforeCount: logicalEmpty ? 0 : beforeCount)
        ProbeLog.log("verification: \(verification)")
        if method != .selectedText, let beforeRange {
            restoreCaret(target, expected: payload, offset: (logicalEmpty ? 0 : beforeRange.location) + text.utf16.count)
        }
        return .success(InsertOutcome(writeError: err, elapsed: elapsed, verification: verification))
    }

    private static func restoreCaret(_ target: FocusTarget, expected: String, offset: Int) {
        let el = target.element
        // Do not move the selection after an unexplained text change or focus change.
        guard case .success = Focus.validateStillFocused(target),
              let actual = AX.string(el, kAXValueAttribute),
              AX.int(el, kAXNumberOfCharactersAttribute) == actual.utf16.count,
              offset >= 0, offset <= actual.utf16.count,
              StrictCompare.equal(actual, expected) || StrictCompare.removedTerminalLineEnding(actual: actual, expected: expected) != nil else {
            ProbeLog.log("caret restore: SKIPPED（本文・文字数・フォーカスを確認できない）")
            return
        }
        let (check, settable) = AX.isSettable(el, kAXSelectedTextRangeAttribute)
        guard check == .success, settable else {
            ProbeLog.log("caret restore: SKIPPED（AXSelectedTextRangeに書き込めない）")
            return
        }
        var range = CFRange(location: offset, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        let error = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
        ProbeLog.log("caret restore: set {\(offset),0} -> \(axErrorName(error))")
        guard error == .success else { return }
        let deadline = Date().addingTimeInterval(1)
        repeat {
            guard case .success = Focus.validateStillFocused(target),
                  let current = AX.string(el, kAXValueAttribute), StrictCompare.equal(current, actual) else {
                ProbeLog.log("caret restore: UNVERIFIABLE（本文またはフォーカスが変化）")
                return
            }
            if let readback = AX.range(el, kAXSelectedTextRangeAttribute),
               readback.location == offset, readback.length == 0 {
                ProbeLog.log("caret restore: EXACT {\(offset),0}（本文不変）")
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        let readback = AX.range(el, kAXSelectedTextRangeAttribute)
        ProbeLog.log("caret restore: MISMATCH actual=\(readback.map { "{\($0.location),\($0.length)}" } ?? "unreadable") expected={\(offset),0}")
    }

    static func verify(_ el: AXUIElement, text: String, beforeValue: String?, beforeRange: CFRange?, beforeCount: Int?) -> Verification {
        guard let beforeValue else { return .unverifiable("挿入前のAXValueを読めない") }
        guard let beforeRange else { return .unverifiable("挿入前のAXSelectedTextRangeを読めない") }
        if let beforeCount, beforeCount != beforeValue.utf16.count {
            return .unverifiable("挿入前のAXValue長(\(beforeValue.utf16.count))とAXNumberOfCharacters(\(beforeCount))が不一致。AXValueが本文全体ではない可能性")
        }
        let range = NSRange(location: beforeRange.location, length: beforeRange.length)
        guard let expected = StrictCompare.expected(before: beforeValue, range: range, inserted: text) else {
            return .unverifiable("選択範囲がAXValueの範囲外")
        }

        // Apps may apply the change asynchronously; poll briefly.
        var after: String?
        let deadline = Date().addingTimeInterval(2.0)
        repeat {
            after = AX.string(el, kAXValueAttribute)
            if let after, StrictCompare.equal(after, expected) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        guard let after else { return .unverifiable("挿入後のAXValueを読めない") }
        let afterRange = AX.range(el, kAXSelectedTextRangeAttribute)
        let afterCount = AX.int(el, kAXNumberOfCharactersAttribute)
        let caretExpected = beforeRange.location + text.utf16.count
        let caretInfo = afterRange.map { "caret={\($0.location),\($0.length)} expected={\(caretExpected),0}" } ?? "caret=unreadable"
        ProbeLog.log("after: value=String(\(TextStats(after))) AXNumberOfCharacters=\(afterCount.map(String.init) ?? "unreadable") \(caretInfo)")

        if let afterCount, afterCount != after.utf16.count {
            return .unverifiable("挿入後のAXValue長(\(after.utf16.count))とAXNumberOfCharacters(\(afterCount))が不一致")
        }
        if StrictCompare.equal(after, expected) { return .exact }

        var notes = ["expectedUTF16=\(expected.utf16.count)", "actualUTF16=\(after.utf16.count)"]
        if let ending = StrictCompare.removedTerminalLineEnding(actual: after, expected: expected) {
            notes.append("差分は期待値末尾の\(ending)1個の欠落のみ（厳密一致ではない）")
        }
        if let d = StrictCompare.firstDifferenceUTF16(after, expected) { notes.append("firstDiffAtUTF16=\(d)") }
        if StrictCompare.equal(after, text) && !beforeValue.isEmpty && beforeRange.length != beforeValue.utf16.count {
            notes.append("既存本文が丸ごと置換された")
        }
        let occ = StrictCompare.occurrences(of: text, in: after) - StrictCompare.occurrences(of: text, in: beforeValue)
        notes.append("挿入本文の出現回数の増分=\(occ)")
        if after == expected { notes.append("正規化(NFC/NFD)差のみ") }
        if after.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") == expected {
            notes.append("改行コードの差のみ")
        }
        return .mismatch(notes.joined(separator: " "))
    }
}

public enum ProbeEnvironment {
    public static func log() {
        let info = Bundle.main.infoDictionary
        ProbeLog.log("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        ProbeLog.log("arch=arm64")
        #else
        ProbeLog.log("arch=x86_64")
        #endif
        ProbeLog.log("process=\(ProcessInfo.processInfo.processName) bundleID=\(Bundle.main.bundleIdentifier ?? "(unbundled)") version=\(info?["CFBundleShortVersionString"] as? String ?? "-") build=\(info?["CFBundleVersion"] as? String ?? "-")")
        ProbeLog.log("executable=\(Bundle.main.executablePath ?? CommandLine.arguments[0])")
        ProbeLog.log("AXIsProcessTrusted=\(AXIsProcessTrusted())")
        if Bundle.main.bundleIdentifier == nil {
            ProbeLog.log("note: 非バンドルCLIのAccessibility権限は、起動元のターミナルアプリ（Terminal/iTerm等）に対して判定されます")
        }
        ProbeLog.log("log=\(ProbeLog.logURL.path)")
    }
}
