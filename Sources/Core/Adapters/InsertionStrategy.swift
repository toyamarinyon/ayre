/// Chooses the write method per target app. App-specific adaptations live in this
/// directory; everything else uses the generic AXSelectedText method.
public enum InsertionStrategy {
    /// Codex: AXSelectedText reports success without changing the field, so it gets
    /// AXValue whole-value replacement with CodexFieldState's empty-field detection.
    public static let codexBundleID = "com.openai.codex"

    public static func method(forBundleID bundleID: String?) -> Inserter.Method {
        bundleID == codexBundleID ? .codexValue : .selectedText
    }

    public static func method(for target: FocusTarget) -> Inserter.Method {
        method(forBundleID: target.bundleID)
    }

    /// CLI names. `auto` resolves per target via `method(for:)`.
    public static func parse(_ name: String) -> Inserter.Method?? {
        switch name {
        case "auto": return .some(nil)
        case "selected-text": return .some(.selectedText)
        case "value": return .some(.value)
        case "codex-value": return .some(.codexValue)
        default: return nil
        }
    }
}
