# Ayre naming cleanup — 0.2.2 (build 2)

The Xcode project and scheme are `Ayre`. SwiftPM uses package `Ayre`, modules/targets `AyreCore`, `AyreCLI`, `AyreReceiver`, and `AyreCoreTests`. Application logging, errors, environment diagnostics, and shortcuts use Ayre-prefixed names. The log is `~/Library/Logs/Ayre/ayre.log`. The public app bundle identifier remains `com.toyamarinyon.ayre`.

Prototype compatibility has been removed at the user's request. The default prompt directory is only `~/Library/Application Support/Ayre/Prompts`; there is no automatic import, migration marker, or fallback to another location. Existing files outside that directory were not deleted or moved. Explicit CLI `--store` paths continue to work.

## Validation

- `swift test -c release`: 28 tests passed. Three tests solely exercising the removed migration implementation were removed with that implementation.
- `bash scripts/build.sh --unsigned --universal`: succeeded using `Ayre.xcodeproj` and scheme `Ayre`, including `AyreReceiver` and the bundled CLI.
- `python3 scripts/verify-package.py`: passed app identity, App Intent metadata, embedded Sparkle, and temporary-store CLI checks.
- `bash scripts/verify-lifecycle.sh` and `bash plugins/ayre/tests/test-helper.sh`: passed.
- `python3 scripts/test-release.py`: four tests passed. `python3 scripts/test-appcast.py`: eight tests passed with the required macOS metadata access.
- Sparkle feed and updater-state fixtures passed available/no-update/network-error, preference persistence, insertion deferral, and missing/invalid key checks. No actual update was installed.
- A source comparison confirmed 25 Swift files changed only through the intended naming substitutions; the storage simplification and removal of its three tests were reviewed separately.
- Searches of the current repository source (excluding Git metadata and ignored build products) found no previous prototype brand or branded type/module names. Diff whitespace and project plist checks passed.

This remains an unsigned local validation. Production key configuration, Developer ID signing/notarization, and live install/restart acceptance remain pending as described in the Sparkle distribution guide. No application release was published.
