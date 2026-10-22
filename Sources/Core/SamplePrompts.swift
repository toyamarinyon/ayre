import Foundation

public struct SamplePrompt {
    public let id: String
    public let title: String
    public let text: String
}

public enum SamplePrompts {
    public static let all: [SamplePrompt] = [short, markdown, long]

    public static func find(_ id: String) -> SamplePrompt? {
        all.first { $0.id == id }
    }

    public static let short = SamplePrompt(
        id: "short",
        title: "Short test",
        text: "Ayre 短文テスト：こんにちは。"
    )

    public static let markdown = SamplePrompt(
        id: "markdown",
        title: "Markdown test",
        text: """
        # Ayre Markdownテスト

        ## 日本語と絵文字
        - 日本語：漢字・ひらがな・カタカナ・全角記号「」（）、。
        - 絵文字：🧪 ✅ 🇯🇵 👨‍👩‍👧‍👦 👍🏽
        - 結合文字：e\u{301}（NFD） / é（NFC）
        - 記号：$HOME ${VAR} \\backslash "double" 'single' <tag> & | ~ ^ %

        ## バッククォート
        インライン `code` と ``double `tick` `` を含む。

        ```swift
        let greeting = "こんにちは"
        print("\\(greeting) 🧪")
        ```

        ```
        \tタブで始まる行
            スペース4つで始まる行
        ```

        1. 番号付き
        2. リスト
           - ネスト

        > 引用

        空行が続く:


        END-OF-MARKDOWN-TEST
        """
    )

    public static let long: SamplePrompt = {
        var lines: [String] = ["# Ayre 長文テスト", ""]
        let total = 400
        for i in 1...total {
            let n = String(format: "%04d", i)
            if i % 50 == 1 {
                lines.append("## セクション \(i / 50 + 1)")
            }
            if i % 100 == 0 {
                lines.append("```")
                lines.append("L\(n)-code: let value\(i) = \"\(i)\" // 🧪")
                lines.append("```")
            }
            lines.append("L\(n) | 日本語の行です。番号で順序と欠落を確認します。`code_\(n)` 🧪 abcdefghijklmnopqrstuvwxyz0123456789")
        }
        lines.append("")
        lines.append("END-OF-LONG-TEST lines=\(total)")
        return SamplePrompt(id: "long", title: "Long test", text: lines.joined(separator: "\n"))
    }()
}
