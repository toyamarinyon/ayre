# PromptInsertProbe

macOSで、**クリップボードを使わずに**別アプリ（Codex App）のフォーカス中の入力欄へテキストを挿入できるかを確かめる検証用プロジェクト。

- CLI（`--method auto`）とApp Intentの挿入方式は `InsertionStrategy` が選ぶ。Codexでは AXValue全文書き込み＋Codex空欄判別、それ以外のアプリではフォーカス中要素の `kAXSelectedTextAttribute` を書き込む（選択範囲があれば置換、なければカーソル位置へ挿入）。アプリのホットキーパネルには、実機検証で追加したAXValue全文置換とCodex空欄自動判別の選択肢もある（末尾の追加実験を参照）。
- `NSPasteboard`、`pbcopy`、`pbpaste`、Cmd+V、合成キーイベント（`CGEvent`）、Return送信は**使わない**。`grep -rn "NSPasteboard\|pbcopy\|pbpaste\|CGEvent" Sources App` で0件になることを確認できる。
- フォールバックは入れていない。失敗したらログに理由を残して何もしない。

## 構成

| パス | 内容 | 段階 |
|---|---|---|
| `Sources/Core/` | AXの取得・検査・挿入・検証、サンプル3種、ログ（CLIとAppで共有） | 共通 |
| `Sources/CLI/` | `PromptInsertProbeCLI`（SwiftPM）。遅延後にフォーカス中の要素を検査・挿入 | 1 |
| `Sources/Receiver/` | `PromptInsertProbeReceiver`（SwiftPM）。テスト用の受け手アプリ。自分のNSTextViewの中身をAXを通さず期待値と厳密比較 | 1 |
| `App/` + `PromptInsertProbe.xcodeproj` | `PromptInsertProbe.app`。ホットキーで選択パネル表示（段階2）、App Intent「Promptを入力」（段階3） | 2, 3 |
| `scripts/build.sh` | ビルド | |
| `scripts/diag.sh` | 結果を返すための環境情報＋ログ収集 | |

サンプル（`PromptInsertProbeCLI samples` で統計を表示）：

- `short` 短文テスト：1行
- `markdown` Markdownテスト：日本語、絵文字（ZWJ・国旗・肌色）、NFD結合文字、改行・連続空行、タブ、バッククォート・コードフェンス、`\`・`$`
- `long` 長文テスト：約400行、UTF-8で約50KB。各行に `L0001` 形式の行番号があり、末尾に `END-OF-LONG-TEST`。欠落・重複・順序の入れ替わりを目で確認できる

## 必要なもの

- macOS 14以降
- Xcode 16以降（`.xcodeproj` はXcode 16の同期フォルダー形式 `objectVersion = 77` で書いている）。CLIとReceiverだけならCommand Line Toolsで足りる見込み
- Spotlightからアクションを実行するのはmacOS 26（Tahoe）以降の機能（推測。下の「段階3」を参照）

## ビルド

```sh
scripts/build.sh                 # アドホック署名
scripts/build.sh ABCDE12345      # Apple Developer の Team ID（任意）。再ビルド後もAccessibility許可が保たれやすい
```

Accessibility権限は、実行するもの（バイナリ）ごとに判定される：

- **CLI**：起動したターミナルアプリ（Terminal／iTermなど）に許可が必要。システム設定 > プライバシーとセキュリティ > アクセシビリティ。`PromptInsertProbeCLI request-permission` で確認ダイアログを表示できる。
- **App**：`PromptInsertProbe.app` に許可が必要。アドホック署名だと、再ビルドで署名が変わり許可が外れることがある。外れたら、一覧から一度削除して追加し直す。

ログ：`~/Library/Logs/PromptInsertProbe/probe.log`（CLIは標準エラーにも出力）。記録するのは、OSとプロセス、対象アプリのbundle ID・pid、UI要素のrole／subrole、属性一覧、主要属性の読み取り結果・型・長さ・書き込み可否、AXError、挿入本文の文字数・UTF-16数・UTF-8バイト数、検証結果。**既存の入力内容は記録しない**（長さだけ）。記録するラベルはプレースホルダーなどのUI文言だけ。

## 段階1：CLIで直接挿入

```sh
BIN=$(swift build -c release --show-bin-path)
$BIN/PromptInsertProbeCLI env
$BIN/PromptInsertProbeCLI inspect --delay 5                    # 5秒以内に対象の入力欄へ移動
$BIN/PromptInsertProbeCLI insert --sample markdown --delay 5
```

- シェルから起動すると、前面にあるのはターミナル。CLIは開始時にフォーカス中のアプリを記録し、`--delay` 秒待ってから対象を取り直す。取り直した対象がまだターミナルなら、何もせず終了する。
- 待機中は **Cmd+Tab** で対象アプリへ切り替える（クリックするとカーソル位置・選択範囲が変わるため）。
- 対象は、AXのシステム全体要素から得た `AXFocusedApplication` → `AXFocusedUIElement`。どちらの経路で取れたかを `source=` としてログに出す。
- 書き込み条件：roleが `AXTextArea`／`AXTextField`／`AXComboBox` のどれかであること、セキュアテキストフィールドではないこと、`AXUIElementIsAttributeSettable(AXSelectedText)` がtrueであること。属性が**存在するだけでは書き込まない**。
- 検証：挿入前の `AXValue` と `AXSelectedTextRange` から期待値を作り、挿入後の `AXValue` とUTF-16単位で比較する（Swiftの `==` はNFC/NFDの違いを同一視するので使わない）。`AXNumberOfCharacters` と長さが合わない場合（`AXValue` が本文の一部しか返していない可能性）は `UNVERIFIABLE` とし、一致とは判定しない。既存本文が丸ごと置き換わった場合は `MISMATCH` になり、ログに「既存本文が丸ごと置換された」と出る。
- 終了コード：0＝書き込み成功（検証結果はログを見る）、1＝失敗（書き込みなし、または書き込みエラー）、3＝MISMATCH。
- Electron／Chromium製のアプリは、支援技術から要求があるまでAXツリーを作らないことがある。そのため対象アプリに `AXManualAccessibility=true` を設定する（Electronのドキュメントに記載の方法）。無効にするには `--no-electron-ax` を付ける。

### 受け手アプリでの厳密比較

```sh
$BIN/PromptInsertProbeReceiver &
```

1. 期待するサンプルとシナリオ（空の入力欄／既存本文の途中へ挿入／選択範囲の置換）を選び、「シナリオを準備」を押す。
2. ターミナルで `insert --sample <同じもの> --delay 5` を実行し、Cmd+TabでReceiverへ戻る。
3. 「検証」を押す。Receiverは自分のテキストを、準備時の本文と選択範囲から作った期待値とUTF-16単位で比較する。AXの読み戻しは使わない。編集イベント（`shouldChangeTextIn` の範囲と置換長）も表示する。

## 段階2：ホットキー＋パネルで、元の入力欄へ戻す

1. `PromptInsertProbe.app` を起動し、権限を許可する。「グローバルホットキー ⌃⌥⌘P」をオンにする（Carbonの `RegisterEventHotKey` で、この1つの組み合わせだけを登録する。キー入力の監視はしない）。
2. Codex Appの入力欄にカーソルを置き、⌃⌥⌘P を押す。
3. **パネルを表示する前**に、フォーカス中の要素を取得して検査する（このアプリはまだ前面ではない）。入力欄でなければ、パネルに理由を表示し、選択肢は出さない。
4. 1／2／3で選ぶ（Escで中止）。パネルを閉じたあと、次を**すべて**確認できた場合だけ書き込む：
   - フォーカス中のアプリのpidが元のアプリと同じ
   - 元のアプリの `AXFocusedUIElement` が、取得した要素と `CFEqual`
   - 要素が有効で、`AXSelectedText` に書き込める
   1つでも満たさなければ `ABORT (書き込みなし)` をログに出し、ビープを鳴らす。
5. パネル方式は2つから選べる：
   - **非アクティブ化パネル**（既定）：`NSPanel` の `.nonactivatingPanel`。元のアプリをアクティブにしたまま、パネルがキーウィンドウになる。
   - **通常ウィンドウ**：このアプリをアクティブにし、選択後に `NSRunningApplication.activate` で元のアプリへ戻す。

   各時点（パネル表示時、閉じる前、閉じた後）の「フォーカス中のアプリ」と「元の要素がまだフォーカスされているか」をログに出すので、2つの方式を比較できる。

## 段階3：App Intents＋Spotlight

- `InsertPromptIntent`（タイトル「Promptを入力」）は `@Parameter var prompt: SamplePromptEntity` を持つ。`SamplePromptQuery.suggestedEntities()` が「短文テスト」「Markdownテスト」「長文テスト」を返す。`AppShortcutsProvider` でも公開している。`openAppWhenRun = false`。
- `perform()` の時点で次をログに出す：`NSWorkspace.frontmostApplication`、AXのフォーカス中アプリと要素、フロントアプリ自身の `AXFocusedUIElement`。
- 対象の決め方：フォーカスがSpotlight、ショートカット、Siri、またはこのアプリ自身にある場合、その候補は捨てる。残った候補が入力欄の条件を満たせば対象とし、満たさなければ **IntentFailureをthrowして書き込まない**（推測で別の入力欄を選ばない）。
- `perform()` はすぐに返す（Spotlightを閉じさせるため）。その後5秒間、0.1秒ごとに確認し、**取得した要素そのもの**にフォーカスが戻った場合だけ挿入する。
- 手順：`scripts/build.sh` → Appを `/Applications` にコピーして一度起動し、権限を許可する → Codex Appの入力欄にカーソルを置く → Spotlight（Cmd+Space）で「Promptを入力」を検索 → プロンプトを選んで実行 → `probe.log` の `[perform]` と `[deferred]` の行を確認する。
- Spotlightがアクションを実行できるのはmacOS 26からの機能と理解している（推測。公式ドキュメントの該当ページは確認できていない）。macOS 15以前では、ショートカットアプリから実行して `perform()` 時点のフォーカスを観察することはできる。ただし、それはSpotlight経由の成功ではない。

## 実機検証チェックリスト

`scripts/diag.sh > diag.txt` の出力と一緒に、各項目の結果（成功／失敗／未確認）を返してください。

| # | 項目 | 手順 | 判定の根拠 | TextEdit | Receiver | Codex App |
|---|---|---|---|---|---|---|
| 1 | 権限なしで安全に失敗 | 許可を外して `insert` | `FAILED: Accessibility権限がありません`。書き込みなし | 未確認 | 未確認 | 未確認 |
| 2 | 入力欄の属性 | `inspect` | ログのrole、`AXSelectedText settable`、`AXValue` の型と長さ | 未確認 | 未確認 | 未確認 |
| 3 | 空の欄に挿入（short） | `insert --sample short` | EXACT／Receiverで「一致」 | 未確認 | 未確認 | 未確認（目視） |
| 4 | 既存本文の途中に挿入 | 本文の途中にカーソル | 同上。前後の本文が残っている | 未確認 | 未確認 | 未確認 |
| 5 | 選択範囲の置換 | 範囲を選択 | 選択部分だけが置き換わる | 未確認 | 未確認 | 未確認 |
| 6 | Markdown（日本語・絵文字・改行・バッククォート） | `--sample markdown` | EXACT／一致。NFDの `é` が保たれている | 未確認 | 未確認 | 未確認 |
| 7 | 長文（約400行・約50KB） | `--sample long` | EXACT／一致。所要時間（ログの `in N s`）。末尾が `END-OF-LONG-TEST` | 未確認 | 未確認 | 未確認 |
| 8 | 欠落・重複・順序 | 7の結果 | 出現回数の増分＝1、`firstDiff` なし | 未確認 | 未確認 | 未確認（目視：L0001〜L0400） |
| 9 | 自動送信されない | Codexで3〜7 | 本文が入力欄に残り、送信されていない | — | — | 未確認 |
| 10 | 入力欄以外にフォーカス | Finderやボタンにフォーカスして `insert` | `FAILED: 編集可能な入力欄ではありません`。書き込みなし | 未確認 | — | 未確認 |
| 11 | ターミナルにフォーカスが残る | 切り替えずに待つ | `FAILED: フォーカスが起動元アプリから移っていません` | 未確認 | — | — |
| 12 | Codexの入力が実際に更新される | Codexで挿入後、編集・送信ボタンの状態を見る | UI上の内部状態とAX上の値が一致するか（例：送信ボタンが有効になるか） | — | — | 未確認 |
| 13 | パネル（非アクティブ化）から挿入 | 段階2 | `[after close] ... ==target: true` と RESULT | 未確認 | 未確認 | 未確認 |
| 14 | パネル（通常ウィンドウ）から挿入 | 段階2 | 同上 | 未確認 | 未確認 | 未確認 |
| 15 | パネル表示中に対象が無効 | パネル表示中に別アプリをクリック、または対象ウィンドウを閉じる | `ABORT (書き込みなし)` | 未確認 | 未確認 | 未確認 |
| 16 | Spotlightで「Promptを入力」が出る | Cmd+Space | 表示されるか、候補3つを選べるか | — | — | 未確認 |
| 17 | `perform()` 時点のフォーカス | 16の実行後 | `[perform] AX focused:` がSpotlightか、元のアプリか | — | — | 未確認 |
| 18 | Spotlight経由で挿入 | 16〜17 | `[deferred] RESULT` または `ABORT` の理由 | 未確認 | 未確認 | 未確認 |

## 報告（この環境での結果）

### 1. 結論

**実機では何も確認できていない。** 作業したのはLinux（Ubuntu 22.04）のVMで、macOS、Xcode、Codex Appは使えなかった。Swiftのコードは構文チェック（`swiftc -parse`）だけ行った。AppKitに対する型チェックとビルドはしていない。AppKitを使わない部分（サンプル生成、UTF-16での厳密比較）だけは、Linux上で実行して動作を確認した。

- Accessibility APIでCodex Appへ直接挿入できたか：**未確認**
- 別のUIから元の入力欄へ戻せたか：**未確認**
- Spotlight経由で実現できたか：**未確認**

### 2. 確認したバージョン

macOS、Xcode、Codex App：すべて**未確認**。`scripts/diag.sh` の出力で埋めてください。

### 3. 実装と起動方法

上の「ビルド」「段階1〜3」を参照。

### 4. 検証結果表

上のチェックリストのとおり、すべて**未確認**。

コードを読んで確認できた事実（実機の挙動ではない）：

- クリップボード、合成キーイベント、Returnを送る処理はコードに含まれていない。
- 対象が入力欄の条件を満たさない場合、書き込み（`AXUIElementSetAttributeValue`）を呼ぶ前に処理が返る。

### 5. 制約と、予想される失敗の理由（**推測**。実機で確かめる必要がある）

- **Codex AppがElectron／Chromium製の場合**（`diag.sh` の `electron:` 行で確認できる）：
  - `AXManualAccessibility` を設定しないと、入力欄が `AXFocusedUIElement` として取れないことがある。
  - Chromiumで `AXSelectedText` への書き込みができるかどうかは、要素の実装（`textarea` か `contenteditable` か）とChromiumのバージョンによると考えられる。
  - `contenteditable` 系のエディタ（ProseMirrorなど）では、AXからの書き込みがDOMには反映されても、エディタ内部の状態やReactの状態に反映されないことがある。そうなると、送信ボタンが有効にならない、送信される本文が表示と違う、といった問題が起き得る。チェックリスト12で確認する。
  - `contenteditable` の `AXValue` は改行の表し方が元の文字列と違うことがあり、その場合はEXACTにならない（ログに「改行コードの差のみ」と出る）。Codex App上での厳密比較は保証できない。
- **長文**：AXの1回のメッセージで数十KBを送ると、時間がかかるか `cannotComplete`（タイムアウト）になる可能性がある。タイムアウトは10秒に設定している。
- **段階2**：非アクティブ化パネルでは、元のアプリがアクティブのまま残るので、閉じた後にフォーカスが戻ると予想している。通常ウィンドウ方式では、`activate` の後にフォーカスが元の要素へ戻るかどうかがアプリによって違い得る（Chromiumは、ウィンドウがアクティブに戻ったとき最後にフォーカスしていた要素を復元するはず）。
- **段階3**：
  - Spotlightのパネルがキーボードフォーカスを持ったまま `perform()` が呼ばれると、AXのフォーカス中アプリはSpotlightになる。その場合は元の要素を特定できないので、この実装はthrowして終わる（安全側）。
  - それでも、`NSWorkspace.frontmostApplication` が元のアプリのままで、そのアプリの `AXFocusedUIElement` が元の入力欄を指している可能性はある。その場合は2番目の候補として採用している。この経路で取れた要素を「元の対象」とみなしてよいかは、ログの `source=` を見て判断してほしい。
  - Spotlight内でパラメーターの候補を選ぶUIがどう表示されるか（`suggestedEntities` の3件が出るか）は、OSのバージョンに依存する。
  - App Intentsが実行されるのはアプリのプロセス内なので、Accessibility権限はAppに対して必要。
- **代替方式**：文字入力イベント（`CGEvent` の `keyboardSetUnicodeString`）は実装していない。この方式は、改行を送るとReturnとして扱われ送信されるおそれがある、長文では1イベントずつ送るため遅い、IMEの状態に影響される、送っている途中でフォーカスが移ると別の場所に入力される、という問題があり、必須条件（自動送信しない）と両立させにくい。

### 6. 次に進むなら最小限必要なこと

1. あなたのMacで `scripts/build.sh` → チェックリスト1〜8を **TextEdit と Receiver** で実施。ここが通らなければAX方式自体を見直す。
2. 同じ手順をCodex Appで実施し、`inspect` のログ（role、属性一覧、`AXSelectedText` に書き込めるか）とチェックリスト9・12の目視結果を返す。**AX方式が成立するかどうかは主にここで決まる**。
3. 2が成立したら、段階2（13〜15）、段階3（16〜18）の順に確認する。Spotlightで17がSpotlightになる場合は、Spotlight経由は不成立とし、ホットキー＋パネル方式で進めるかを判断する。

## 参照

Apple公式：

- AXUIElementSetAttributeValue — https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue
- AXUIElementIsAttributeSettable — https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable
- AXUIElementCopyAttributeValue — https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue
- AXUIElementCreateSystemWide — https://developer.apple.com/documentation/applicationservices/1462095-axuielementcreatesystemwide
- kAXFocusedUIElementAttribute — https://developer.apple.com/documentation/applicationservices/kaxfocuseduielementattribute
- kAXSelectedTextAttribute — https://developer.apple.com/documentation/applicationservices/kaxselectedtextattribute
- AXIsProcessTrustedWithOptions — https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- NSWindow.StyleMask.nonactivatingPanel — https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel
- App Intents — https://developer.apple.com/documentation/appintents
- AppEntity — https://developer.apple.com/documentation/appintents/appentity
- EntityQuery.suggestedEntities() — https://developer.apple.com/documentation/appintents/entityquery/suggestedentities()
- AppIntent.openAppWhenRun — https://developer.apple.com/documentation/appintents/appintent/openappwhenrun
- AppIntent.isDiscoverable（Siri、Spotlight、ショートカットから見つけられるかどうか） — https://developer.apple.com/documentation/appintents/appintent/isdiscoverable
- App Shortcuts／AppShortcutsProvider — https://developer.apple.com/documentation/appintents/app-shortcuts, https://developer.apple.com/documentation/appintents/appshortcutsprovider
- Spotlight integration — https://developer.apple.com/documentation/appintents/spotlight

Apple以外：

- Electron Accessibility（`AXManualAccessibility`） — https://www.electronjs.org/docs/latest/tutorial/accessibility

## 追加実験：AXValueによる全文置換

アプリの「実験: AXValueで全文を置換」をオンにすると、ホットキーのパネルから選んだサンプルをAXValue方式で挿入する。既定は従来のAXSelectedText方式。（当時の記述。現在のApp IntentとCLIは `InsertionStrategy` で方式を選ぶ。末尾の節を参照。）

AXValue方式は挿入前のAXValue全文・AXNumberOfCharacters・AXSelectedTextRangeを取得し、UTF-16長と範囲を検証して期待する全文を組み立てる。AXValueの書き込み可否、直前のフォーカス・本文・選択範囲・文字数を再確認してから1回だけ書き込む。書き込みと読み戻しの間に他プロセスの編集を原子的に防ぐことはできないため、検証中は対象の本文を編集しない。検証は従来と同じUTF-16完全比較。クリップボード、合成キーイベント、送信操作、失敗時の別方式への再試行は使わない。

AXValueの検証後、本文が完全一致するか、期待値末尾の改行1個（LF/CR/CRLF）だけが欠けた場合に限り、フォーカスと文字数を再確認してAXSelectedTextRangeを挿入直後の範囲へ1回書き込む。末尾改行の欠落はMISMATCHのまま、本文を記録せず種類のみ診断する。カーソル復元は本文の判定と独立して `caret restore: EXACT / MISMATCH / SKIPPED / UNVERIFIABLE` を記録する。復元後にも本文不変を確認する。

最初はReceiverで短文の空欄・途中挿入・選択置換を確認し、その後Codexの空の入力欄で試す。再ビルド後はアプリを再起動し、Accessibility権限を再確認する。

### Codexで空欄の案内文がAXValueに含まれる場合

AXValueとAXPlaceholderValue/AXTitle/AXDescriptionの一致を、本文をログへ記録せず診断する。ただし、UIラベルと同じ文字をユーザーが入力している場合と区別できないため、一致だけで空欄扱いにはしない。

目視で対象欄を空にしたと確認できる場合に限り、アプリのAXValue方式をオンにして「対象を空欄と確認済み」をオンにする。パネルにも既存本文を引き継がない旨を表示する。このモードでは、選択範囲が{0,0}で、読み取った値が空文字、またはUIラベルそのもの（末尾LF/CRLF1個も許容）である場合だけサンプル単体を書き込む。通常の本文がある場合は中止する。同じラベル文字列を本当に入力している場合も置換対象になるため、空欄かどうかの確認はユーザーが行う。サンプル選択時にこのモードのチェックは自動で外れ、次回は通常のAXValue方式へ戻る。

検証の期待値はサンプル単体。実際に読んだ元の値の統計と、このモードを選択したことを別途ログに残す。カーソルはサンプル末尾へ復元する。空欄の自動判別を実現したという意味ではない。

### 読み取りだけで空欄と実入力を比較

「比較診断のみ（入力しない）」をオンにすると、登録済みの同じホットキーは挿入パネルを開かず診断だけを行う。

1. 診断対象を「1. 空欄を記録」にする。
2. Codexの対象欄を空にしてフォーカスし、⌃⌥⌘Pを押す。成功すると診断対象が自動で2へ進む。
3. 同じ欄へ `Work with Codex` を手入力する。比較でカーソル位置の差を減らしたければ、手入力後に文頭へ移動する。
4. 同じホットキーを押す。同じpid・同じAX要素であることを確認して差分をログに出す。

記録対象はAXValue・ラベル属性の型と長さ、既知のテスト文字列との一致フラグ、末尾LFの有無、AXStringForRangeによる全文取得（最大4096 UTF-16単位）の結果、対象欄配下のrole・subrole・子数・値の統計。探索は最大12要素・深さ3。本文文字列そのものは記録しない。前後で本文・選択範囲・フォーカスが変わった場合はスナップショットを採用しない。値・選択範囲への書き込みは行わない。

比較で差が見つかっても、その差が常に空欄と実入力を区別できるかは別途確認する。特にカーソル位置や一時的な読み取りエラーの差は空欄判定に使わない。

### TextAreaの全通常属性スナップショット

比較診断で、対象TextAreaが列挙する通常属性をすべて読み取り、AXError・書き込み可否・値の型と要約を記録する。読み取り以外の副作用が疑われるAXReplaceRangeWithTextは通常属性に紛れていても呼ばない。パラメーター付き属性とアクションは一覧だけを記録し、一括実行しない。既知のAXStringForRangeのみ従来どおり取得する。

文字列は文字数等とセッション内HMAC識別値を記録し、同じ長さの異なる文字列も区別する。HMACキーはプロセス内だけに保持し、保存しない。URLや辞書のキー・値も文字列そのものは保存しない。数値・真偽値・範囲・座標は値を記録する。配列は16件まで、辞書は16件以下のみ展開し、ネストは3段まで。上限による省略を明示する。対象配下の探索は従来どおり最大12要素・深さ3、全体に15秒の取得時間目安を設け、超過後の属性はSKIPPEDとして記録する。

保存先は `~/Library/Logs/PromptInsertProbe/snapshots/snapshot-<UUID>.json`。取得前後の本文・選択範囲・フォーカスを確認するが、原子的な全状態取得ではない。取得の途中で値が変化する可能性はある。

比較対象は空欄・実入力・実入力末尾に改行の3種類。入力によってAX要素が再生成される場合もあるため、同じpidなら診断差分は出すが、CFEqual不一致を警告する。同一欄と証明された比較という扱いにはしない。状態の変わる座標・カーソル・要素ID・読み取りエラーだけでは空欄判定しない。

### Codex限定・子要素による空欄自動判別

AXValue方式をオンにすると「Codexの空欄を自動判別」を選べる（初期チェックはオン）。比較診断はオフにして通常のホットキーパネルから実行する。手動の「対象を空欄と確認済み」は、自動判別がオンの間は無効。

対象bundle IDが `com.openai.codex` の場合にだけ判別する。空欄時に観測した `TextArea → 編集可能Group → 編集不可Group → 編集不可StaticText` を確認し、文字葉のAXValue/AXSelectedText書き込み不可・編集可能祖先なし、rootの選択範囲{0,0}、文字葉と現在のrootのタイトル/説明の厳密一致、root本文がその文字葉＋LFであることを組み合わせる。Work with Codexという文字列自体を決め打ちしない。

すべての非空文字葉が編集可能で、AXValue/AXSelectedTextに書き込め、AXEditableAncestorが対象rootそのものなら本文として扱い、既存本文と選択範囲から挿入後の全文を作る。案内文と同じ文字列を実際に入力した場合や末尾LFがある場合も、編集可能な文字葉なら本文として保持する。混在・読み取り失敗・未確認roleや構造・探索上限（64要素/深さ6/5秒）ではunknownとして書き込まない。判別は書き込み直前に再実行し、本文・選択範囲・フォーカスも再確認する。

空欄ならサンプル単体を書き込み、その期待値と厳密比較してカーソルを末尾へ戻す。この自動判別モードは1回で解除されない。ほかのbundle IDでは通常のAXValue方式として扱う。（当時の記述。現在はCLIの `--method auto` とApp IntentでもCodexに適用する。）観測したCodex入力欄への実験的な適応であり、全アプリ共通の空欄判定ではない。Codex更新で構造が変われば中止し、再調査する。

## 2026-10-20 以降：挿入方式のアプリ別切り替え（Devin、実機では未検証）

- Codex固有の処理は `Sources/Core/Adapters/` にまとめた。`InsertionStrategy` は bundle ID を見て方式を選ぶ。`com.openai.codex` なら `codexValue`（AXValue＋`CodexFieldState` による空欄判別）、それ以外は汎用の `selectedText`。`CodexFieldState` の空欄判別は Codex 専用の適応であり、全アプリ共通の仕様ではない。
- CLI：`insert --method auto|selected-text|value|codex-value` を追加した。既定は `auto`（上の規則で方式を選ぶ）。
- App Intent：挿入直前に `InsertionStrategy.method(for:)` で方式を選ぶ。
- ホットキーパネル：従来どおりチェックボックスで方式を選ぶ（変更なし）。
- CLIとApp IntentのCodex向け経路は**実機で未検証**。パネル経由で成功した結果を、そのまま適用済みとはみなさない。

### 次にあなたのMacで行うCodex実機検証（優先順）

CLIを使い、`PromptInsertProbeCLI insert --sample <id> --method auto --delay 5` を実行してから、5秒以内にCodexの入力欄へ戻る（Cmd+Tab）。結果は `RESULT` 行と `insertion method=` 行、`caret restore:` 行、目視結果で判定する。送信はしない。

1. 既存本文の途中への挿入：「abcdef」と入力し、cとdの間にカーソルを置いて short を挿入する。
2. 選択範囲の置換：「abcdef」の「cd」を選択して short を挿入する。
3. 案内文と同じ文字列：自分で「Work with Codex」と入力し、末尾にカーソルを置いて short を挿入する。この文字列が残ること。
4. Markdown：空欄で markdown を挿入する。
5. 長文：空欄で long を挿入する（約400行）。
6. 上の1と4を、ホットキーパネル（Codex空欄自動判別をオン）とApp Intent（ショートカットアプリから実行）でも確認する。

## 実用向けプロンプト選択UI（検証用UIを置き換え）

- 保存先：`~/Library/Application Support/PromptInsertProbe/Prompts/<slug>.md`（`PromptStore`）。slugは英数字と `._-`（先頭は英数字、128文字まで）。UTF-8で1,000,000バイトまで。条件を満たさないファイルは一覧から除外し、件数だけ表示する。本文は選んだ時点でファイルから読み直し、そのまま挿入する（末尾改行を含めて加工しない）。
- タイトル：先頭20行にある最初の `# 見出し`。見出しがなければslugを使う。一覧は更新日時の新しい順。
- ホットキーパネル（⌃⌥⌘P、アプリ起動時に登録）：検索欄（タイトルとslugに対する部分一致。空白区切りの語はすべて一致が必要）、↑↓で選択、Returnかダブルクリックで挿入、Escで中止。パネルは非アクティブ化パネル（実機で確認済みの方式）に固定した。
- App Intent「Promptを入力」：候補は保存済みプロンプト。Spotlight上の文字入力による絞り込み（`EntityStringQuery`）にも対応する。
- 挿入方式は常に `InsertionStrategy`（Codexは AXValue＋空欄判別、それ以外は AXSelectedText）。方式の切り替え、空欄確認モード、比較診断のUIは削除した。`EmptyFieldDiagnostic` はCoreに残しているが、現在はどこからも呼ばれていない。
- 受け入れ検証用のプロンプトは `PromptInsertProbeCLI export-samples` で `sample-short` / `sample-markdown` / `sample-long` として書き出せる。`PromptInsertProbeCLI prompts` で一覧を表示する。
- 受け入れ検証として残っている項目：途中挿入、選択範囲の置換、Markdown、長文、フォーカスを変えたときの中止。いずれも新しいパネルとSpotlightの両方で確認する。

### 最新のプロンプトを選択せずに入力

Spotlightで「最新のPromptを入力」を実行すると、保存フォルダ内の読み込めるMarkdownのうち更新日時が最も新しい1件を入力します。候補の選択は不要です。同じ更新日時ならslug順です。「最新」は最後に使用したものではなく、最後に更新したファイルを意味します。保存済みの有効なファイルがない場合はエラーとなり、入力しません。フォーカス確認・Codexの空欄判別・送信しない動作は「Promptを入力」と共通です。
