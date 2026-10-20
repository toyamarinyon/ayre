# Ayre

Insert saved Markdown prompts into the focused text field on macOS, directly from Spotlight. Ayre uses Accessibility APIs, does not use the clipboard or synthetic keystrokes, and never sends your message.

## Commands

- **Ayre Go**: insert the most recently modified readable prompt without choosing one. Modification-time ties are resolved by slug.
- **Ayre Pick**: choose a saved prompt, then insert it.
- **Control + Option + Command + P**: open the searchable picker; use arrow keys and Return to select, or Esc to cancel.

Place the cursor in the destination field before invoking a command. Insertion proceeds only after focus returns to that same field. Unknown targets or field states abort without writing.

## Prompt files

The existing storage location is retained for compatibility:

```text
~/Library/Application Support/PromptInsertProbe/Prompts/<slug>.md
```

Files must be UTF-8 and no larger than 1,000,000 bytes. Slugs use ASCII letters, digits, dots, underscores, and hyphens, start with a letter or digit, and cannot contain consecutive dots. The first `# ` heading within the first 20 lines supplies the title; otherwise, the slug is displayed. The entire file, including its heading, is inserted unchanged.

Edit these files with any text editor. Ayre reads the selected file again at insertion time. Existing user prompts are never translated. Japanese and other Unicode text in test fixtures is intentional.

## Build and test

Requires macOS 14 or later and Xcode.

```sh
swift test
bash scripts/build.sh YOUR_DEVELOPMENT_TEAM
```

The development target and executable names remain `PromptInsertProbe` for compatibility. The app display name is Ayre. The build script outputs the app path, CLI, and receiver. Use a Team ID and Apple Development signature for Spotlight/App Intents testing; ad-hoc signing previously prevented Shortcuts from communicating with the app.

Install the built app in `/Applications`, launch it once, and grant Accessibility permission in System Settings > Privacy & Security > Accessibility. Preserve a backup before replacing an existing installation. Changing the signing identity or Bundle ID may require granting permission again. Spotlight may need time to refresh its command index.

Do not commit signing keys, credentials, build products, or local diagnostic logs. Supply the development team through the build command rather than committing a personal Team ID.

## Development tools

```sh
swift run PromptInsertProbeCLI prompts
swift run PromptInsertProbeCLI export-samples
swift run PromptInsertProbeCLI inspect --delay 5
swift run PromptInsertProbeCLI insert --sample short --delay 5 --method auto
bash scripts/diag.sh > /tmp/ayre-diag.txt
```

`export-samples` creates three acceptance-test prompts without overwriting existing files unless `--force` is supplied. Sample bodies include Japanese, emoji, combining characters, code fences, and whitespace to exercise exact Unicode handling. Review diagnostic output before sharing it.

## Source layout

- `App/`: AppKit UI, global hotkey, and App Intents.
- `Sources/Core/`: target capture, insertion, strict comparison, and Markdown storage.
- `Sources/CLI/`: diagnostics and sample export.
- `Sources/Receiver/`: independent receiver for exact comparison.
- `Tests/`: core unit tests.
- `verification/`: hardware test results and investigation notes.

## Validation

The imported baseline passed 19 core tests. A roughly 53 KB, 424-line prompt inserted into an empty Codex field through Spotlight matched the expected text exactly in UTF-16, with the caret restored to the end. The parameter-free latest-prompt command has passed build and metadata checks; its end-to-end insertion is still awaiting hardware confirmation. English command titles require a fresh build and Spotlight verification.
