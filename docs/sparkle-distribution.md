# Sparkle distribution

Ayre pins Sparkle **2.10.0** in the Xcode project and Package.resolved. The GUI source is 0.2.2, build 2; CLI contract 0.2.1/protocol 1 is independent. The app bundle ID remains `com.toyamarinyon.ayre`. See the official [setup](https://sparkle-project.org/documentation/), [publishing](https://sparkle-project.org/documentation/publishing/), and [gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/) documentation.

## One-time signing setup

Apple signing uses the existing five Actions secrets listed in README. Sparkle needs a separate Ed25519 signing key. Do this yourself in a trusted local terminal; handle Keychain and GitHub authentication prompts directly. Never paste a private key into chat, commit it, print it, enable shell tracing, or pass it as a command-line argument. Keep a protected offline backup: losing the signing key complicates updating installed apps.

Resolve the pinned tools, then create an Ayre-specific key in your login Keychain:

```sh
xcodebuild -resolvePackageDependencies -project Ayre.xcodeproj \
  -scheme Ayre -derivedDataPath build/DerivedData
sparkle_bin=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
"$sparkle_bin/generate_keys" --account ayre
```

Only the public key is printed. Set that Base64 public key as repository **Actions variable** `AYRE_SPARKLE_PUBLIC_ED_KEY`. It is embedded as `SUPublicEDKey`. For local distribution builds, export the same public value as `AYRE_SPARKLE_PUBLIC_ED_KEY`.

Export the private key directly to a restricted temporary file and upload its contents as a secret, without printing it:

```sh
umask 077
ayre_key_dir=$(mktemp -d)
"$sparkle_bin/generate_keys" --account ayre -x "$ayre_key_dir/private-key"
gh secret set SPARKLE_PRIVATE_KEY --repo toyamarinyon/ayre < "$ayre_key_dir/private-key"
rm -f "$ayre_key_dir/private-key"
rmdir "$ayre_key_dir"
```

Ensure the temporary file is removed if an intervening command fails. Save the backup through your organization's trusted secret-management process before deleting your only copy. For a local release, read the exported key into the environment without echoing it (`export SPARKLE_PRIVATE_KEY="$(cat /protected/path/to/key)"`) and unset it immediately afterward. The release script passes it only through stdin to Sparkle tools. The build and appcast verification reject missing or malformed public keys; the generator rejects a mismatched signing key.

## Using another Mac

Key generation alone does not require these Ayre source changes. On the other Mac, download the pinned official tools and verify the same archive checksum used by Sparkle's package manifest:

```sh
ayre_tools_dir=$(mktemp -d)
curl --fail --location https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip -o "$ayre_tools_dir/Sparkle.zip"
printf '%s  %s\n' 17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959 "$ayre_tools_dir/Sparkle.zip" | shasum -a 256 -c -
ditto -x -k "$ayre_tools_dir/Sparkle.zip" "$ayre_tools_dir/tools"
sparkle_bin="$ayre_tools_dir/tools/bin"
"$sparkle_bin/generate_keys" --account ayre
```

Continue with the public variable/private secret registration above, using this `sparkle_bin`. Remove the temporary tools directory after registration and protected key backup. The tools archive contains no personal signing key.

The Sparkle key may be generated and backed up on a separate trusted Mac. That Mac needs Xcode command-line tools, the pinned Sparkle tools, and authenticated access to configure the GitHub repository. Set the repository variable and secret from that Mac; GitHub Actions will receive them for the release. The private key does not need to be copied to other development Macs. Apple distribution credentials already configured in Actions remain independent of the Sparkle key. Use reviewed source for the tool-resolution command; the handoff patch can be applied to the matching checkout before it is pushed.

## Release pipeline

1. Review trusted source, increase `MARKETING_VERSION` and integer `CURRENT_PROJECT_VERSION` in both configurations, and preserve the bundle ID. Build numbers must strictly increase across published releases, even when the displayed version changes. Never reuse a released build number.
2. Run the validation commands in README and the Sparkle scripts under `scripts/verify-*`. Review the resulting app and the manual checks below.
3. Run **Signed macOS release** from reviewed `main`, with tag matching the app version (`v0.2.2` for this source). Existing tags/releases are refused. It compares the new build number with published appcasts.
4. The pipeline builds both architectures, signs nested Sparkle helpers/framework and CLI before the outer app with Developer ID/hardened runtime, and rejects debug entitlements. `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` remains required. It submits a temporary ZIP to Apple, staples and validates the app, checks code signatures and Gatekeeper, then creates the final ZIP with `ditto` preserving framework symlinks.
5. Only the final stapled ZIP is EdDSA-signed by `generate_appcast`. Its enclosure uses the tag-specific HTTPS ZIP URL. The feed records the app's build number, displayed version, and minimum OS. The archive/feed checks and checksums run before a Draft Release is created. A failure cannot create a published update.
6. Download the draft assets through authenticated GitHub access, verify checksums, and test the extracted app before requesting approval to publish. Publishing is a separate human action; this workflow never publishes automatically.

Local equivalent, after configuring a notarytool profile and the two environment values:

```sh
bash scripts/release.sh "Developer ID Application: Your Name (TEAM)" YOUR_NOTARY_PROFILE
```

Local release builds are artifacts only and do not upload or publish. For version comparison, supply published feeds through `PREVIOUS_APPCAST_DIR`; the workflow downloads those automatically. Do not bypass version checks when publishing a locally generated artifact.

## Feed hosting and publication

The app's `SUFeedURL` is `https://github.com/toyamarinyon/ayre/releases/latest/download/appcast.xml`. This requires no additional server or Pages deployment. GitHub's latest release must always be a stable Ayre app release containing **both** `appcast.xml` and its signed ZIP; never mark a plugin-only release as latest. The plugin can be versioned in the repository independently. The workflow verifies published feed history before producing a draft. Do not manually promote an older build or edit a published ZIP or feed in place.

Drafts and prereleases are not selected by the stable latest endpoint. A Draft's assets are not the production feed. Until the first Sparkle-enabled stable release is published the endpoint may return 404; this is expected, not proof of an updater failure. Publication exposes the prepared feed and ZIP together as assets of the same release. GitHub/CDN caching can delay visibility; verify the resolved latest URL after approved publication.

Before publication, inspect: correct public key, valid Developer ID signature and notarization, both architectures including helpers, strict build-number increase, tag-specific ZIP URL, EdDSA signature, and archive checksum. Existing users must manually install a Sparkle-enabled release once. Release publication and any repository settings changes require the user's approval.

## Runtime and failure recovery

**Check for Updates…** uses Sparkle's standard check, download, install, and restart UI. Auto checks are off until explicitly enabled in Settings, and Sparkle persists this choice. Scheduled checks only add an available-version reminder in Settings, preserving Spotlight focus and background operation. Installation is never automatic. The App Intent insertion guard postpones installation/relaunch while a captured insertion is waiting or running; it releases after completion or the existing five-second timeout. The next launch follows the existing launch-event policy; manually reopen Ayre to see Settings.

Network/404 failures: retry the manual check after checking connectivity and the published latest assets. No update: compare `CFBundleVersion` with `sparkle:version`, including skipped versions and OS requirements. Signature failures: do not bypass validation; verify that the exact final ZIP was signed with the key matching the installed app, and publish a new correct version. A changed or missing public key requires a deliberately reviewed key-transition plan, not a casual replacement. Notarization or Gatekeeper failures must be fixed before distribution. Preserve the previous installed app and saved data when investigating; never delete the prompt folder as an update fix.

## Manual release acceptance

Use a separate macOS account or disposable VM for install/restart tests. Install the previous test app in a temporary persistent directory and use two correctly signed test versions with a private test HTTPS appcast and separate bundle ID/keys. Never change production `SUFeedURL` defaults or replace the user's installed Ayre to run this test.

- Confirm no update, available update, offline failure, and rejection of a modified ZIP. Then install the intact update, confirm restart and version, and confirm the original app remains runnable after each failure.
- Enable automatic checks, relaunch, confirm persistence, disable, and relaunch again. Ensure auto installation is unavailable.
- Open Settings manually: Dock appears. Close Settings: app stays resident and Dock disappears. Reopen manually: Settings appears.
- With an empty Codex input focused, run Spotlight Ayre Go and Ayre Pick on warm and cold app launches. Confirm exact insertion, no send, and no unexpected Settings/Dock or focus change. Repeat with nonempty input to confirm the existing refusal behavior.
- Confirm saved prompts, Accessibility, and the user's login-item choice survive an update. Trigger a test update restart during a pending insertion and confirm it waits for insertion/timeout. Confirm plugin files/version are unchanged.

Automated feed and signature checks do not establish Developer ID notarization or a successful real installation/relaunch. Record those separately; do not call a keyless local build production-ready.
