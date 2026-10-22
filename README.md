# Ayre

Ayre (pronounced “Air”) inserts saved Markdown prompts into the focused text field on macOS 14+. **Ayre Go** inserts the latest modified readable file; **Ayre Pick** lets you choose. Neither submits a message. Insertion uses Accessibility APIs, strict UTF-16 readback, and caret restoration. No clipboard or simulated keystrokes are used for insertion.

## Install and onboarding

Download a signed, notarized ZIP from [GitHub Releases](https://github.com/toyamarinyon/ayre/releases), when available, extract it, and move Ayre.app to a persistent location. Open Ayre to see settings. Grant Accessibility permission under System Settings → Privacy & Security → Accessibility. The app shows the actual permission status and provides a Request Permission button.

Once permission is granted, install the Claude Code plugin by running these commands **inside Claude Code**:

```text
/plugin marketplace add toyamarinyon/ayre
/plugin install ayre@ayre
```

The settings window can copy these commands. Restart Claude Code if it requests it. Use `/ayre:use-ayre` to create or refine a reusable prompt and register it with Ayre. The plugin discovers a compatible CLI on PATH or finds the installed app through Launch Services; no PATH change or fixed installation directory is required. If the app has moved, open it once at its new location to refresh macOS registration.

Use `/ayre:handoff-codex` when an implementation discussion in Claude Code is ready to move to Codex. It turns the next agreed work into a goal-first, self-contained assignment that Codex can execute and verify, rather than a summary of the conversation. It includes the authorized destination workspace, decisions, acceptance checks, and a coordination plan using GPT-6 Luna subagents. It saves the result to Ayre without launching Codex or sending a message. Source Claude Code sessions and investigation workspaces are out of bounds for the receiving agents; restricted source details must be omitted or explicitly cleared for transfer. Necessary missing destination context is resolved before saving. Actual filesystem isolation still depends on Codex workspace permissions.

Update an existing installation with `/plugin marketplace update ayre` and `/plugin update ayre@ayre`, then restart Claude Code if requested. The `handoff-codex` skill is included in plugin **0.2.2** and uses the existing protocol-1 CLI; no app update is required for this skill addition.

Place the cursor in the destination field, then invoke Ayre Go or Ayre Pick through Spotlight. Focus must return to the captured original field; unknown targets or field state cause an abort without writing. Ayre Go selects the latest **modified**, not latest used, file.

## Settings, background operation, and login

Closing settings hides the Dock icon and leaves Ayre running. Reopening the app shows settings and its Dock icon again. Spotlight/App Intent launches run without opening settings or taking focus. Launch at login is off until explicitly enabled in settings; its status comes from macOS Service Management rather than a saved preference. If Accessibility is missing during background startup, a menu-bar item provides a route to settings without opening a window. A pending login approval must be completed in System Settings → General → Login Items. See the status in Ayre if registration fails or is unavailable.

Use Quit Ayre to stop the process. Disable Launch at login before uninstalling, quit Ayre, then remove the app and optionally uninstall the Claude plugin with `/plugin uninstall ayre@ayre`. Remove its marketplace with `/plugin marketplace remove ayre` if no longer needed. Prompt files and logs remain until you delete them deliberately.

For updates, quit Ayre, back up the existing app, replace it with the new signed build, and open it again. Keep the same stable identity and signing team. Update the plugin with `/plugin marketplace update ayre` followed by `/plugin update ayre@ayre`. If Accessibility stops working after an update, review the app entry in System Settings.

## Prompt storage and CLI contract

Prompts and diagnostic logs use the Ayre locations:

```text
~/Library/Application Support/Ayre/Prompts/<slug>.md
~/Library/Logs/Ayre/ayre.log
```

Ayre reads and writes prompts only in `~/Library/Application Support/Ayre/Prompts`. It does not import prompts from other locations.

Files must be valid UTF-8 and at most 1,000,000 bytes. Slugs are at most 128 ASCII characters, start with a letter or digit, contain only letters, digits, dots, underscores or hyphens, and cannot contain `..`. The first nonempty `# ` heading within the first 20 lines supplies the title; otherwise the slug is displayed. The entire file, including that heading, is inserted unchanged. Edit files using any text editor; Ayre rereads a selected file before insertion. Existing user text is never translated or normalized.

The bundled executable is `Ayre.app/Contents/MacOS/ayre`:

```sh
"/path with spaces/Ayre.app/Contents/MacOS/ayre" --version
"/path with spaces/Ayre.app/Contents/MacOS/ayre" capabilities --json
"/path with spaces/Ayre.app/Contents/MacOS/ayre" put review --title "Review" < prompt.md
# Intentional replacement only:
"/path with spaces/Ayre.app/Contents/MacOS/ayre" put review --title "Review" --overwrite < prompt.md
```

`--title` is an assertion, not metadata that changes the file: the example expects a `# Review` heading in the first 20 lines. For a heading-free body, use the slug as title. A mismatch fails with an actionable error. Registration preserves stdin UTF-8 bytes exactly, including CRLF, Unicode normalization, and trailing newlines. It does not require Accessibility, launch the app, activate a window, insert into another application, or submit anything. By default an existing slug is rejected; replacement requires `--overwrite`. Exit codes: 0 success, 2 usage/input validation, 3 existing slug, 4 storage or stdin I/O failure. Use `--store DIRECTORY` for isolated fixtures.

The app source version is **0.3.0** (build **3**, not yet published) and the Claude Code plugin version is **0.2.2**. Discovery requires CLI protocol **1** and the `put` capability, not an exact release-version match. `capabilities --json` provides `protocolVersion`, `version`, and `capabilities`. The app Bundle ID is `com.toyamarinyon.ayre`. Grant Accessibility permission to Ayre in System Settings.

## Build and distribution

Requires macOS 14+, Xcode, and SwiftPM. The Xcode project and scheme are `Ayre`; the core and test targets are `AyreCore` and `AyreCoreTests`, and the diagnostic receiver product is `AyreReceiver`. The app product is Ayre.app (GUI executable `AyreApp`, bundled CLI `ayre`); `scripts/build.sh` is the canonical packaging path and embeds the CLI before signing.

```sh
swift test
bash scripts/build.sh --unsigned
# Local App Intents testing (supply your own usable certificate/team):
bash scripts/build.sh --team YOUR_TEAM_ID
# Public distribution, both Apple silicon and Intel:
bash scripts/build.sh --identity "Developer ID Application: Your Name (TEAM)" --universal
```

Output: `build/DerivedData/Build/Products/Release/Ayre.app`. Unsigned builds are for compilation/fixture checks; an Apple Development signature is needed for reliable local App Intents testing. Raw `xcodebuild` builds the UI only; use the script to obtain the complete app with CLI. The default CLI build targets the host architecture; `--universal` builds both executables for arm64 and x86_64. Use `--derived-data DIRECTORY` to isolate build output when needed.

Public distribution requires Apple Developer Program membership, a Developer ID Application certificate/private key, hardened runtime, and successful notarization. Apple Development/Personal Team and ad-hoc signatures do not establish public distribution readiness. See [Apple’s Developer ID guidance](https://developer.apple.com/developer-id/) and [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Configure a notarytool Keychain profile and the Sparkle keys described in [Sparkle distribution](docs/sparkle-distribution.md), then explicitly run:

```sh
bash scripts/release.sh "Developer ID Application: Your Name (TEAM)" YOUR_NOTARY_PROFILE
```

The script builds a universal signed app, uploads it to Apple for notarization, staples and validates its ticket, verifies Gatekeeper acceptance, then creates `build/release/Ayre-0.3.0-macOS.zip` and a Sparkle `appcast.xml` containing the archive signature and prints its SHA-256. It does not publish a GitHub Release. Review the artifact and evidence before uploading publicly. Never commit certificates, credentials, signing settings, build output, logs, or user prompts.

## Development and validation

```sh
swift run ayre --help
swift run ayre prompts
swift run ayre export-samples
swift run ayre inspect --delay 5
swift run ayre insert --sample short --delay 5 --method auto
bash scripts/verify-lifecycle.sh
bash scripts/verify-updater-state.sh
bash scripts/verify-sparkle-feed.sh
bash scripts/verify-sparkle-install.sh
python3 scripts/test-appcast.py
python3 scripts/test-release.py
bash plugins/ayre/tests/test-helper.sh
python3 scripts/verify-package.py
claude plugin validate .
claude plugin validate plugins/ayre
```

Sample export is explicit and does not overwrite existing files without `--force`. Unicode fixture content is intentional. Insertion code lives in `Sources/Core/`; UI, picker, and App Intents in `App/`; diagnostic receiver source in `Sources/Receiver/`. Current implementation evidence and remaining manual checks are recorded in [0.2.0 verification](verification/implementation-0.2.0.md); earlier insertion evidence is in [hardware results](verification/results.md). Test registration against temporary directories, never the user's real prompts.

### GitHub Actions signing and notarization

The **Signed macOS release** workflow runs manually from `main`. It tests the project, imports a Developer ID Application identity into a temporary keychain, builds the universal app, notarizes it, staples and validates the ticket, checks Gatekeeper acceptance, and creates a **draft** GitHub Release with a ZIP, Sparkle appcast, and SHA-256 checksums. It never publishes the draft automatically and refuses to replace an existing release.

Set these repository Actions secrets before running it:

- `APPLE_CERTIFICATE_P12_BASE64`: Base64-encoded password-protected certificate and private key export.
- `APPLE_CERTIFICATE_PASSWORD`: export password.
- `APPLE_ID`: Apple Account email for notarization.
- `APPLE_TEAM_ID`: the signing certificate's Developer team.
- `APPLE_APP_SPECIFIC_PASSWORD`: an app-specific password, not the normal account password.

Use **Actions → Signed macOS release → Run workflow**, choosing `main` and tag `v0.3.0`. Only run trusted reviewed code: release workflows can access signing secrets. The hosted runner is ephemeral, and an always-run cleanup removes its temporary signing keychain. Review and download-test the draft artifact before publishing. Increase both the app marketing version and its numeric build number when preparing a new app version. Archive names and tag validation are derived from the project.


### In-app updates

Settings shows the current app version, **Check for Updates…**, and **Automatically check for updates**. Automatic checks are opt-in and persist across launches. Downloads and installation require user action in Sparkle’s standard UI; automatic installation is disabled. Scheduled checks announce available versions inside Settings without opening windows or taking focus from Spotlight. A restart requested while an App Intent is inserting waits for that insertion to finish (or time out).

Users of 0.2.1 and earlier must download and install a Sparkle-enabled release once manually. App updates retain the bundle identifier, saved prompt folder, Accessibility identity, and login-item registration; macOS can still request permission confirmation after signing or location changes. Claude Code plugin updates remain separate and are never performed by the app updater.

Release setup, EdDSA key handling, publication review, and troubleshooting are in [Sparkle distribution](docs/sparkle-distribution.md). A local build without a real public key displays an unavailable message and does not start the updater. Such a build is not ready for distribution.
