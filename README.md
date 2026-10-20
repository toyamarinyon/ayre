# Ayre

保存したMarkdownプロンプトを、フォーカス中の入力欄へ直接挿入するmacOSアプリです。クリップボードや合成キー入力を使わず、送信もしません。

## 現在の状態

PromptInsertProbeでの実機検証を引き継いだ開発用リポジトリです。初期コミットでは動作を保つため、Xcodeターゲット・Bundle ID・保存先・Spotlightの表示名は検証版の名称を維持しています。

- Spotlight「Promptを入力」: 保存済みプロンプトを選択して入力
- Spotlight「最新のPromptを入力」: 更新日時が最新の1件を選択なしで入力
- グローバルホットキー: Control + Option + Command + P
- 保存先: `~/Library/Application Support/PromptInsertProbe/Prompts/<slug>.md`

正式名称は **Ayre**。次の変更でコマンドを **Ayre Go** / **Ayre Pick** に揃え、既存プロンプトを保ったまま移行します。

## 開発

macOS 14以降とXcodeが必要です。

```sh
swift test
bash scripts/build.sh YOUR_DEVELOPMENT_TEAM
```

Team IDは引数で指定し、証明書・秘密鍵・ビルド成果物はGit管理しません。Spotlight/App Intentsの実機検証にはTeam ID付き署名とAccessibility権限が必要です。

## 構成

- `App/`: AppKit UI、ホットキー、App Intents
- `Sources/Core/`: 対象入力欄の取得、挿入、検証、Markdown保存
- `Sources/CLI/`: 診断・サンプル生成CLI
- `Sources/Receiver/`: 受け手側で全文比較する検証用アプリ
- `Tests/`: コアのテスト
- `verification/`: 検証履歴と検証版の詳細ガイド

## 検証済みの範囲

19件のコアテストが成功。CodexへのSpotlight経由の長文入力（約53KB）はUTF-16単位の全文一致と末尾カーソル復元を確認済みです。パラメータなしの最新プロンプトコマンドはビルド・登録情報の確認までで、実挿入は未確認です。
