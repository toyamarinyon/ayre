# Ayre 0.2.0 implementation verification

Verified on October 21, 2026, on Apple silicon running macOS 26.6.2 with Xcode 27.1. Deployment target remains macOS 14.0. Intel binaries were compiled and inspected, not run on Intel hardware.

## Automated and package checks

- `swift test` and `swift test -c release`: 28 tests passed. Coverage includes unchanged insertion classification/strict comparison, exact-byte storage, atomic conflict handling including symlinks, invalid/oversized input, explicit replacement, CLI I/O errors, and launch-event ordering/background decisions.
- `scripts/build.sh --unsigned --universal --derived-data build/UnsignedFinal`: passed. Both GUI and CLI contain arm64 and x86_64. Mach-O minimum OS for the bundled CLI is 14.0.
- `scripts/build.sh --team <local-team> --universal`: passed using an existing Apple Development certificate, with manual Keychain authorization. Both nested CLI and enclosing app passed `codesign --verify --deep --strict`. This is a development build, not a public distribution signature.
- `scripts/verify-package.py <app>`: passed for unsigned and signed packages. GUI `AyreApp` and CLI `ayre` are separate files even on a case-insensitive filesystem. App identity/version/background metadata and generated App Intents metadata are checked. Ayre Go has no parameters; both actions have `openAppWhenRun = false`.
- Bundled CLI registration ran before granting Accessibility, using temporary stores. Running the registration suite with the GUI stopped left zero Ayre GUI processes. UTF-8 bytes, CRLF, combining text, emoji, trailing whitespace, conflict protection, replacement and invalid input rejection passed.
- `bash plugins/ayre/tests/test-helper.sh`: passed. Real helper prepare/put calls preserve stdin bytes and literal multiline argument values; compatible PATH selection, stale/duplicate/multiple app matches, nonstandard paths and spaces are exercised. A hung CLI that ignores SIGTERM is forcibly stopped within the probe deadline, and resolution continues to the next compatible candidate.
- The real plugin helper also forwarded a prompt into the bundled signed CLI through a test-only PATH launcher that supplied a temporary store. Stored bytes matched exactly.
- With PATH excluding Ayre, the actual Launch Services resolver found the signed app in a directory outside `/Applications` whose path contains spaces. When two compatible build copies existed it reported ambiguity; after disposable copies were removed it found the one remaining app.
- `claude plugin validate .`, `claude plugin validate plugins/ayre`, and the skill-creator `quick_validate.py`: passed. A temporary `CLAUDE_CONFIG_DIR` successfully added the local marketplace and installed `ayre@ayre`, then was removed. No unrelated Claude settings were changed.
- `scripts/release.sh` passed shell syntax validation. The public-build guard rejected the development app's debugger entitlement as intended. Developer ID signing, notarization, stapling and public Gatekeeper acceptance were not run; the user deferred those prerequisites.

## Live app checks

- Settings opened with English permission guidance and the system-reported login-item state. The login toggle remained off throughout testing. This Mac reported `notFound`; no successful login registration or actual login launch is claimed.
- Closing Settings kept the process alive with AppKit activation policy `.accessory` (Dock hidden). Reopening returned it to `.regular` and displayed Settings. Initial manual launch also exercised the real callback ordering: the open Apple Event arrived before the default-launch flag and window readiness, then Settings appeared once.
- After the user granted Accessibility to the signed app, Check Again reported granted and revealed the exact marketplace-add/plugin-install commands and Copy button.
- Permission registration required care after testing both unsigned and signed copies with the same Bundle ID. Existing prototype permissions do not transfer to the new stable identity.

## Scope and remaining manual checks

The insertion engine, focus/target validation, picker and intent implementation were not changed. Earlier hardware results remain in `results.md`; they are not new 0.2.0 end-to-end evidence. Codex insertion, middle/selection cases through Spotlight, cancellation/error coverage, and an actual login cycle still need user-driven confirmation. The computer-use tool refused System Settings access and timed out when binding Spotlight; no alternative UI automation bypass was used.

Public distribution remains pending Developer ID Application credentials and a notarytool Keychain profile. Once supplied, run the documented release script and review the resulting artifact before publishing a GitHub Release. No release was published in this implementation session.

## Follow-up: Spotlight reopen regression

User-driven Ayre Go tests exposed a focus regression in the initial onboarding implementation: the app became frontmost before `perform()`, so the unchanged target resolver correctly rejected Ayre itself and wrote nothing. The unconditional Settings presentation in the reopen delegate is being replaced with a check for the public `kAEApplicationActivationExpected` Boolean on the reopen event. Only an explicit foreground request may show Settings. Missing/false flags remain in the background; insertion target validation is unchanged.

Debug and Release suites pass 28 tests with this candidate fix. `bash scripts/verify-lifecycle.sh` additionally exercises the actual Foundation Apple Event parameter/attribute bridge and login/service markers without launching UI or registering login items. The updated signed package and actual Spotlight foreground/background event distinction still require live verification; the development signing process is awaiting manual Keychain authorization. Earlier signed ZIP evidence above predates this follow-up and does not prove the regression fixed.
