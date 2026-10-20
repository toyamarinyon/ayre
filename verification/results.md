# 実機検証結果

環境: macOS 26.6.2 (25G83), arm64

## 2026-10-19 Receiver・短文・空欄・非アクティブ化パネル

成功。ユーザーが Control+Option+Command+P → 1 → 検証 を実施。

- Receiver独立検証: UTF-16単位で期待値と完全一致 (chars=30, utf16=30, utf8Bytes=54, lines=1)
- 挿入前: AXValue UTF-16=0, 選択範囲 {0,0}
- AXSelectedText書き込み: success, 0.002秒
- 挿入後: AXValue UTF-16=30, カーソル {30,0}
- AX読み戻し検証: EXACT
- パネル終了後: 元のReceiverのpidとフォーカス要素が一致
- Receiver編集イベント: {0,0}→1 / {0,1}→0 / {0,0}→30 sample=short

Codexへの挿入、途中挿入、選択範囲置換、Markdown、長文、通常ウィンドウ、Spotlightは未確認。

## 2026-10-19 Receiver・短文・既存本文の途中・非アクティブ化パネル

成功。Receiver独立検証とAX読み戻し検証の両方で完全一致。

- 挿入前: UTF-16=33, 選択範囲 {16,0}
- AXSelectedText書き込み: success, 0.001秒
- 挿入後: chars=62, UTF-16=63, UTF-8=119, 2行, カーソル {46,0}
- 編集イベント: 1件、{16,0}→utf16=30 sample=short
- 前後の本文、絵文字、改行を保持
- パネル終了後に元のReceiverのpidとフォーカス要素が一致

## 2026-10-19 Receiver・短文・選択範囲置換・非アクティブ化パネル

AX読み戻し検証はEXACT。対象は非バンドルReceiver pid=27380。

- 挿入前: UTF-16=28, 選択範囲 {7,15}
- AXSelectedText書き込み: success, 0.002秒
- 挿入後: UTF-16=43, カーソル {37,0}
- 元のフォーカス要素への復帰を確認
- ユーザーは検証ボタンを押したと報告。二重起動していた別Receiverを画面取得したため、当該Receiverの独立検証表示は未確認。AX結果と混同しない。

## 2026-10-19 Receiver追加結果

- 選択範囲置換: ユーザー提供スクリーンショットで独立検証の完全一致を確認 (UTF-16=43)。
- Markdown・空欄: ユーザーが独立検証の完全一致を報告。ログでもEXACT (UTF-16=401, UTF-8=649, 31行)。
- 長文・空欄: ユーザーが独立検証の完全一致を報告。ログでもEXACT (UTF-16=33530, UTF-8=52828, 424行)。

## 2026-10-19 Codex入力欄・短文・非アクティブ化パネル

失敗。ユーザーは入力されないと報告。ログでもMISMATCH。

- 対象: com.openai.codex, pid=8538, AXTextArea, ラベル Work with Codex
- AXSelectedText: settable=true
- パネル終了後の元アプリpid・元フォーカス要素一致を確認
- 挿入前: UTF-16=16, 選択範囲 {0,0}
- AXSelectedText書き込みAPIの戻り値: success (0.000秒)
- 約2秒後もAXValueはUTF-16=16、カーソル {0,0} のまま
- 期待値UTF-16=46、実際UTF-16=16、挿入本文の出現回数増分=0

この環境の当該入力欄では、settable=true と API success が実際の挿入を保証しない。ホットキーによる対象取得・復帰は成功しており、現在のAXSelectedText書き込み方式の実効性が確認できない。Spotlight経由は未検証。

## 2026-10-19 AXValue方式

### Codex・短文

ユーザーは画面に値が入ったと報告。ただし12:48:07ZのログではAPI success後もAXValue UTF-16=16のまま、期待値46と不一致。表示とAX読み戻しの食い違いは未解明。送信可能な内部状態・通常編集の確認は未実施。

### Receiver・短文・選択範囲置換

12:51:24ZにAXValueで書き込み。Receiver独立検証とAX読み戻しの両方で完全一致。

- 元本文UTF-16=28、選択範囲 {7,15}
- 期待する全文UTF-16=43、AXValueへ1回書き込み (success, 0.001秒)
- Receiver編集イベント: {0,28}→utf16=43（全文置換）
- 前後のBEFORE- / -AFTERを保持
- 本文の結果はEXACTだが、カーソルは {43,0}（全文末尾）。通常挿入で期待する {37,0} と異なる。カーソル自動補正は未実装。

### Codex・AXValue短文の再検証 (12:53:51Z)

ユーザーが挿入後の通常編集ができること、未入力扱いにならずEnterで送信できそうな状態になることを報告。実際の送信は未実施。挿入後のカーソルは文頭。

ログでは今回、挿入本文の出現回数の増分=1。前回の無変化とは異なりAX読み戻しにも挿入が反映された。ただし期待値UTF-16=46に対し実際45、firstDiff=45（期待値末尾の1コード単位不足）。期待2行に対し実際1行。具体的に何が欠けたかは本文を記録していないため未確定。caret={0,0}、通常挿入での期待={30,0}。

判定: Codexで画面上の入力・通常編集・非空状態への反映は確認。本文の厳密一致と挿入直後のカーソル位置は未達成。空欄に見えるときもAXValueには挿入前16コード単位があったため、プレースホルダー等との関係を追加調査する必要がある。

### Codex・カーソル復元と末尾差分の診断 (12:59:00Z)

- AXValue書き込み後、期待値の末尾LF1個だけが欠けていることをUTF-16比較で確定。その他は一致。厳密判定はMISMATCHを維持。
- 約2秒の本文検証後にAXSelectedTextRange={30,0}を設定し、読み戻しもEXACT、本文不変。
- ユーザー目視: 初めは文頭、数秒後に Work with Codex の前へ移動。ログの短文30コード単位直後への復元と整合。
- 空に見えるCodex欄のAXValueがUTF-16=16で、ラベル Work with Codex は15コード単位。ユーザー目視と合わせ、プレースホルダーとLFが既存本文として混入した可能性が高いが、書き込み前の本文そのものは記録していないので未確定。
- 文頭からの復元自体は成功。初回約2秒の遅延は完全一致を待つ検証時間によるもの。

## 空欄の案内文を本文として引き継ぐ問題への対応

AXValueとUIラベルの一致だけでは、実際に同じ文字が入力された場合を区別できない。Codex画面の自動取得はツール側で拒否されたため、その経路での追加調査は実施していない。

- 診断: AXPlaceholderValue/AXTitle/AXDescriptionの取得結果・型と長さ・元の値との一致フラグだけをログに追加。
- 明示的な空欄確認モードを追加。ユーザーが空にしたと確認したときに限り選択する。
- 選択範囲{0,0}かつ値が空またはUIラベル一致という追加条件が必要。全文・文字数・フォーカス・本文不変の既存チェックを維持。
- 書き込む値と検証期待値はサンプル単体。カーソルはサンプル末尾。
- サンプル選択時に空欄確認チェックを解除。自動的な案内文削除はしない。
- swift test: 3件成功。空欄確認モードの実機検証は未実施。

## 空欄と同一文字列の実入力の読み取り比較

ユーザー操作による空欄記録と、手入力 Work with Codex（文頭へカーソル移動後）の診断を比較。

| 観測 | 空欄側 (14:49:29Zまで) | 実入力側 (14:51:13Z) |
|---|---|---|
| root AXValue | Work with Codex + LF、UTF-16=16、2行 | Work with Codex、UTF-16=15、1行 |
| AXStringForRange | AXValueと同一 | AXValueと同一 |
| AXPlaceholderValue | noValue | noValue |
| root AXTitle/AXDescription | 既知テスト文字列と同一 | 同一 |
| 子構造 | AXTextArea → AXGroup → AXGroup → AXStaticText | AXTextArea → AXGroup → AXStaticText |
| root選択範囲 | {0,0} | {0,0} |

末尾改行とグループ階層数に観測上の差があった。範囲指定の取得は案内文を除外しなかった。

ただし自動比較では保存した要素と今回の要素のCFEqualが成立せず、UIに「同じ入力欄で先に空欄を記録してください」と表示。取得した2つのログを手動比較した結果であり、同一AX要素による対照実験の成立までは保証できない。再描画による要素再生成か、別欄/別チャットだったかは不明。実入力末尾にLFを付けた場合や、通常文・複数行、消去後の再現性は未検証。自動空欄判定にはまだ使わない。

## 2026-10-20 全通常属性スナップショット版

TextAreaが公開する通常属性すべての取得結果・書き込み可否・型別の値要約を追加。文字列やURLは本文非保存、同一起動中の差分はセッション鍵付きHMACで比較。パラメーター付き属性・アクションは名前のみ一覧化。AXReplaceRangeWithTextは通常属性に現れても取得せず記録だけにする。

JSON保存先: ~/Library/Logs/PromptInsertProbe/snapshots/

- 子要素: 最大12要素・深さ3。配列/辞書・取得時間の上限による省略を明示。
- rootの取得前後で本文・選択範囲・フォーカスを確認。全属性を原子的に取得した保証はない。
- 同一アプリでAX要素が変わった場合は警告付きの診断比較を許可するが、同一入力欄を証明したという意味ではない。
- 3状態（空欄、既知の文字列の実入力、実入力＋末尾改行）をラベル付けして収集可能。
- swift test: 6件成功、アプリビルド成功。
- 更新版を起動し、比較診断・ホットキーをオン。再ビルドによりAccessibility未許可になっていることを確認。実機スナップショットの収集・判別材料の評価は許可後のユーザー操作待ち。

## 2026-10-20 全属性の空欄 vs 手入力比較

空欄 snapshot-3498D441-C7CB-4C7C-B6E1-30FF87006F9F.json と、手入力 snapshot-DCEA080D-12E2-4076-8B8B-4BCBC7C374E4.json を比較（同一起動中の識別値）。

有望な候補:
- root.child0 のAXDOMClassList: 空欄ではクラス1個、実入力では0個。文字列は保存していないのでクラス名自体は未確認。
- 既知文字列を持つAXStaticText: 空欄ではroot.child0.child0.child0、AXValue settable=false / AXSelectedText noValue・settable=false / AXEditableAncestorなし。
- 実入力ではroot.child0.child0がAXStaticText、AXValue settable=true / AXSelectedText success・settable=true / AXEditableAncestorとAXHighestEditableAncestorがAXTextArea。
- root属性は長さ・AXValue・可視文字範囲以外に差を認めない。rootのクラス情報は同じ。

文字列の内容や改行の有無に依存しない可能性があるのは、子要素のクラスとテキスト葉の編集関連属性。まだ1組の対照なので自動空欄判定は未実装。次に実入力＋LFで、空欄と同じAXValueでもこれらの差が残るかを確認する。

### 実入力＋末尾改行の対照 (2026-10-20)

snapshot-29742AAE-5208-4218-9F7D-B97567B97A95.json を取得。実入力 Work with Codex＋LF はAXValue/AXStringForRangeともUTF-16=16・既知テスト＋LFであり、空欄の案内文と同じ内容・長さ。

それでも以下の差が残った:
- 実入力の文字葉root.child0.child0はAXStaticText、AXValue settable=true、AXSelectedText settable=true、AXEditableAncestor=AXTextArea。
- 空欄の案内文の文字葉root.child0.child0.child0はAXStaticText、AXValue/AXSelectedText settable=false、AXEditableAncestorなし。
- root.child0のDOMクラスは実入力（改行あり・なし）では0件、空欄では1件。
- 改行ありの実入力ではrootに2つ目のAXGroup（空行）がある。
- 全取得でSKIPPEDなし。本文の文字列だけでは判別できないが、文字葉の編集関連属性は今回の3状態で区別材料になった。

未確認: 全消去後に空欄構造へ戻るか、別の文言・複数段落・別チャット・アプリ再起動後にも安定するか。自動判別への適用はまだ行っていない。

### 全消去後の再現 (2026-10-20)

snapshot-45418323-CEAD-4F31-B45D-C642D415C757.json。ユーザーが実入力を全選択・削除後に取得。

- root AXValueは既知テスト文字列＋LF（16コード単位）へ復帰。
- root.child0のクラス情報は初回空欄と同じセッション識別値の1件へ復帰。
- TextArea→Group→Group→StaticTextへ復帰。
- 文字葉のAXValue・AXSelectedTextは再び書き込み不可、AXEditableAncestorなし。
- 初回空欄との差7項目は中間Groupの選択/行属性と動的ノードIDであり、上記の判別候補は再現。

観測した状態: 初回空欄→同文手入力→同文＋LF→全消去後空欄。文字葉の編集関連属性とGroupクラス情報は、このサイクルで案内文と実入力を区別した。ただし1環境・1入力欄での観測で、他の内容やCodex更新への一般性は未検証。文字葉の編集属性等を組み合わせたCodex限定の空欄判別候補として扱える。入力欄rootは空欄でも編集可能なので、rootのsettableだけでは区別できない。

## 2026-10-20 Codex空欄自動判別の実装

CodexFieldStateを追加。既知の空欄構造と編集関連属性に一致する場合はempty、全非空文字葉が編集対象rootを参照しAXValue/AXSelectedText書き込み可能ならcontent、それ以外はunknownとして中止。文字列の決め打ちなし。自動判別はAXValueの明示的なモードとして追加し、他bundle IDは通常AXValue。書き込み直前に再判別する。

- 空欄はサンプル単体が検証期待値、本文は選択範囲置換後の全文が期待値。
- カーソル復元は既存の厳密読み戻しチェックを継続。
- テスト: 空欄→同文手入力→同文＋改行→空欄、ラベル変更、混在/未確認構造、選択範囲あり、編集属性不足を検証。既存と合計10件成功。
- 判別器の実機運用確認はビルド後の権限再許可・ユーザー操作で行う。現時点ではテスト成功を実機での成功と扱わない。

### 自動判別初回の停止と修正

ユーザーは何も入力されないと報告。21:28:14ZログではCodex field state=unknownのため書き込み前に中止。元のフォーカスへの復帰と全文・選択範囲は正常。既存ログに個別取得の停止理由がなかったため、原因箇所の確定には追加診断が必要。

スナップショットで確認済みの「AXEditableAncestorが属性一覧にない」状態と、公開されている属性の取得失敗を区別するよう収集処理を修正。未公開を読み出してエラーになるケースを避ける。公開済み属性のfailure/cannotCompleteや別祖先参照はunknownを維持。各停止条件とノードのrole・文字数・編集フラグをログに追加（本文は記録しない）。

テストはAX要素CFArrayのネイティブ型変換も含め12件成功。修正版の実機結果は未確認。

### 自動判別修正版・Codex空欄への短文挿入成功

2026-10-20（ログ21:39:23Z）。ユーザーが入力されたことを確認。

- 子要素のAXEditableAncestor未公開を正しく扱い、state=emptyと判別。
- 書き込み直前の再判別も同じ結果。
- payloadはサンプル単体 UTF-16=30 / UTF-8=54 / 1行。案内文を引き継がない。
- AXValue書き込みsuccess。約0.1秒後に本文検証EXACT。
- AXSelectedTextRange={30,0}の復元成功、読み戻しEXACT、本文不変。
- 最終RESULT: write=success verification=EXACT。

未実施: 全消去後の繰り返し挿入、通常本文への途中挿入・選択置換、案内文と同じ文字を実入力した状態への挿入の実機検証（判別の読み取り比較と単体テストは実施済み）。

### 自動判別・全消去後の繰り返し挿入成功

2026-10-20（ログ22:22:41Z）。ユーザーは全消去後の再実行ができたと報告、提供画像でも短文のみの表示と送信ボタン有効を確認。

- 自動判別の設定を入れ直さず、再び案内文を除外したpayload UTF-16=30を書き込み。
- 本文EXACT、カーソル復元{30,0}もEXACT、本文不変。
- 空欄→挿入→全消去→再挿入の実機サイクル成功。
- 実際の送信、既存本文への途中挿入/選択置換、CodexでのMarkdown/長文はこの自動判別モードでは未検証。

## 2026-10-20 InsertionStrategy導入（Devin・Linux上で作業）

- CLIの `--method auto` と App Intent が、Codexでは `codexValue`、それ以外では `selectedText` を使うように変更した。
- 確認できたのは構文チェック（`swiftc -parse`）のみ。ビルド・単体テスト・実機検証は未実施。CLIとApp IntentでのCodex挿入は未確認。

## 2026-10-19 Devin macOS子セッション（macOS 26.6.2 25G83 / Xcode 26.6 17F113 / Swift 6.3.3 / arm64、VM）

- ビルド：`swift build -c release` 成功、`xcodebuild`（PromptInsertProbe, Debug）成功。コード修正なし。
- 単体テスト：`swift test` 14件成功・0件失敗（CodexFieldStateTests 6、InsertionStrategyTests 2、TextComparisonTests 6）。
- 実機検証（Receiver）：未確認。このVMでは、TerminalにAccessibility権限を許可（`AXIsProcessTrusted=true`）した後でも、システム全体の要素からフォーカス中のアプリ・要素を取得すると常に `AXError=cannotComplete` (-25204) になった。アプリ単体の要素からは取得できた。CLIは対象を取得する前に `FAILED` で止まり、書き込みは行わなかった。Receiverの本文は0、編集イベントも0。安全側の失敗の確認（Terminalに留まる場合・Finderの場合）も同じエラーで止まったため、期待した失敗理由の確認にはなっていない。

## 2026-10-20 ユーザー実機：Spotlight → App Intent → Codex 短文

- 無料Personal TeamのApple Development署名で成功（アドホック署名のときに出た通信エラーは解消）。本文EXACT、カーソルEXACT。
- 続いて、保存済みプロンプトの選択UI（`PromptStore`、検索付きパネル、Intentの候補）に置き換えた。置き換え後は実機で未確認。

## 2026-10-20 保存済みプロンプト選択パネルのローカル確認

- Devin abfefb2 のソースをベースに調整。Codex挿入本体の差分は bundle ID 定数参照への変更のみ。
- 一覧にフォーカスした状態でも Return / テンキーEnter で選択、Esc で中止できるように修正。通常修飾キー付き入力は標準処理へ渡す。
- フォーカス復帰待ちから挿入完了まで再呼び出しを防止し、前回の対象を次回へ引き継がないように修正。
- 検索件数と検索結果なしを表示。
- swift test: 19件成功、失敗0。
- AppKit上で一覧のkeyDownへイベントを直接渡し、Return / テンキーEnter / Esc のコールバック成功を確認。外部アプリへの入力イベント送信は行っていない。
- この版のCodexへの実挿入は未確認。

- 署名付きXcodeビルド成功。配置後のcodesign --verify --deep --strict成功。旧版は /private/tmp/PromptInsertProbe-before-picker-20261020190633.app へ退避。
- /Applications版を起動し、Accessibility権限「許可済み」、保存済み3件、グローバルホットキー有効を画面で確認。
- Receiverを起動し短文・空欄シナリオを準備。GUI自動操作のホットキーではパネル表示を確認できず、実機キーボードによる呼び出しと挿入はユーザー確認待ち。

### 2026-10-20 19:09 JST Spotlightから長文をCodexへ挿入成功

ユーザーがSpotlight経由でsample-longを実行し、L0001〜L0400とEND-OF-LONG-TESTの本文を報告。配置版PID87671のログを確認。

- perform: sample-long、33,126文字、33,530 UTF-16単位、52,828 UTF-8 bytes、424行。
- systemWideとfrontmost両経路でCodexのAXTextAreaを取得。0.11秒後に対象へフォーカス復帰。
- Codex空欄自動判別empty。AXValue書き込み成功。
- 挿入後全文はUTF-16単位でEXACT。
- カーソルを{33530,0}へ復元しEXACT、本文不変。
- ユーザーの報告テキストがチャットへ届いたことも確認。

### 最新のPromptを入力 (2026-10-20)

- パラメータなしのInsertLatestPromptIntentとApp Shortcutを追加。PromptStore既存の更新日時降順・同時刻slug順を利用。空の場合はエラー。
- 既存の対象解決とフォーカス復帰後の挿入処理を共用。
- 署名付きビルドと配置後codesign検証成功。Accessibility許可済みの起動画面を確認。
- 配置版App Intentsメタデータにdiscoverable=true、parameters=[]、タイトル「最新のPromptを入力」を確認。
- 新コマンドのSpotlight上での表示と実挿入はユーザーによる確認待ち。
