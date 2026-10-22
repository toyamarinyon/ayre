# Sparkle implementation evidence — 0.2.2 (build 2)

Initial local verification snapshot. Subsequent signed CI and downloaded-artifact results are recorded in [signed release evidence](sparkle-distribution-run.md), and actual fixture installation/relaunch in [install fixture evidence](sparkle-install-fixture.md). The limitations below describe this earlier local snapshot.

Status at that snapshot: implemented locally, not published. Existing unrelated README/handoff-codex skill edits were preserved. No installed app, production signing key, saved prompt data, GitHub secret, or release was changed by this work.

## Verified

- Pinned Sparkle 2.10.0 resolves with its recorded package revision and binary checksum.
- Unsigned Release build succeeds for arm64 and x86_64. Both Ayre executables, Sparkle, Autoupdate, Updater.app, Installer.xpc, and Downloader.xpc contain both architectures.
- Assembled Info.plist has the intended bundle ID, build 2, app version 0.2.2, HTTPS feed, and disabled automatic checks/install defaults. Sparkle keys use an explicit base plist because arbitrary generated `INFOPLIST_KEY_SU*` settings were not emitted by Xcode.
- Existing 31 Swift tests, Apple Event lifecycle script, and plugin helper checks pass. Bundled CLI packaging checks use only temporary prompt stores; CLI remains protocol 1/version 0.2.1.
- `verify-updater-state.sh` passes actual install-delegate deferral during insertion, nested insertion completion, Sparkle opt-in/out persistence across updater instances, and dormant updater behavior for missing/invalid keys.
- `verify-sparkle-feed.sh` passes actual Sparkle no-update, valid-update discovery, and HTTP 503 cases using a disposable bundle ID, local server, and ephemeral key. It only requests update information.
- `test-appcast.py` passes eight tests covering stable feed metadata, archive size, build monotonicity, real `generate_appcast` output, EdDSA signing, and rejection of modified archives and mismatched keys. The generator requires normal macOS Launch Services access and passed in elevated execution; a sandboxed run failed app-type discovery. No production key or Keychain item is used.
- `test-release.py` passes four isolated tests against macOS `/bin/bash` 3.2.57. They execute the real release script with mocked external tools, cover first-release empty history and existing history, verify secret environment removal and notarize → staple → final ZIP → EdDSA generation order, and ensure notarization/appcast verification failures stop before release readiness. The audit found and fixed an empty-array `nounset` error that would otherwise break the first release. These tests do not perform Apple signing or notarization.
- Shell syntax, workflow YAML parsing, and diff whitespace checks pass.

## Not established

The local unsigned app intentionally has no production public key, and is rejected by distribution verification. This is not a distributable build. Developer ID signing, notarization, a downloaded-app Gatekeeper check, and installation/restart between two actual distribution versions remain pending. No workflow was dispatched, Draft created, tag pushed, or stable feed published. Existing GitHub v0.2.0 and v0.2.1 releases were Drafts at inspection time.

Live Settings/Dock/Spotlight/Codex focus behavior and preservation of Accessibility/login-item choices after installation require the manual checks in [distribution instructions](../docs/sparkle-distribution.md). Existing lifecycle policy and insertion algorithm were retained; automated policy tests do not replace those UI checks. Signature tamper rejection was tested with Sparkle's signing tool, not through a completed standard-UI installation attempt.

Set up the Sparkle public variable/private secret on a trusted Mac, review these changes, then run the signing workflow from reviewed main. Review the resulting Draft and manual acceptance evidence before separately approving publication.
