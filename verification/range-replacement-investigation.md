# AXReplaceRangeWithText 調査 (2026-10-19)

## 確認できたこと

- 実機ログでは、ReceiverとCodexの両方が AXReplaceRangeWithText を parameterized attributes に含めている。
- ただし、属性名が列挙されるだけでは実装・引数形式・動作の保証にはならない。
- 現在のMacOSX27.0 SDKのNSAccessibilityヘッダーに ReplaceRangeWithText の定義を確認できなかった。
- WebKitの実装には `accessibilityReplaceRange:withText:` があり、NSRangeとNSStringを受け取り `replaceTextInRange` に渡す。
- これは対象プロセス内のObjective-Cメソッドであり、外部プロセスから AXUIElementCopyParameterizedAttributeValue に渡す引数形式を示していない。
- WebKitのテストランナーも同じObjective-Cメソッドを宣言している。これだけでは外部プロセス経由の呼び出し形式を確定できない。

## 結果

外部プロセスから渡すパラメータの形式を一次資料で確定できなかったため、推測のパラメータによるCodexへの呼び出しは追加・実行していない。
実装済み、またはCodexで検証失敗という意味ではなく、呼び出し仕様の調査段階で未実施。
「公開しているAPI」と案内した説明は不正確。列挙された属性と、文書化された外部呼び出しAPIを区別する必要がある。

## 一次資料

- https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm (`accessibilityReplaceRange:withText:`)
- https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/InjectedBundle/mac/AccessibilityUIElementMac.mm

## 次の候補

公開AX APIの `AXValue` に、読み取った全文と現在の選択範囲から組み立てた期待値を書き込む比較検証は別途可能。ただし対象全文の置換になるため、現在のAXSelectedText方式とは明示的に区別して実装し、Receiverでの検証を先に行う。
