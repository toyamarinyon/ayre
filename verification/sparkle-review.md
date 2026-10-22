# Sparkle integration verification and code review

## Feed probe results

`scripts/verify-sparkle-feed.sh` runs Sparkle 2.10.0 against a temporary `.app` with a unique bundle identifier and isolated defaults domain. It creates an ephemeral Ed25519 keypair, signs a temporary update archive, and serves local appcast fixtures. The Swift probe constructs `SPUUpdater` with `SPUStandardUserDriver`, calls `checkForUpdateInformation()`, and observes Sparkle delegate callbacks.

The three cases passed:

- A feed containing only the fixture app's current version reports no update.
- A signed 2.0 feed item reports a valid update.
- A local 503 response reports a network error.

The probe never invokes an update offering or download/install path. Its temporary files, server, app bundle, and key are removed on exit; cleanup also deletes only the UUID fixture's defaults domain and Sparkle cache directory. Swift compiler module caches stay under the temporary directory. The successful run used elevated execution for loopback networking; no Keychain operation, installed app, production credential, or user prompt was used.

## Code review

The updater validates the public key and HTTPS feed before it starts. Automatic checks use Sparkle's persisted `automaticallyChecksForUpdates` setting; available updates from scheduled checks stay in Settings, and the standard Sparkle UI handles user initiated updates. App Intent insertion postpones relaunch until the insertion activity ends. I found no material updater lifecycle issue.

The release script previously kept `SPARKLE_PRIVATE_KEY` exported while launching build, signing, and notarization subprocesses, although only appcast generation consumes the key. Capturing it into an unexported shell variable and unsetting the environment binding before those subprocesses reduces its exposure. The distribution script now does this before starting the build.
