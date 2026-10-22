# Sparkle install and relaunch fixture

Run `scripts/verify-sparkle-install.sh` on macOS with the built Sparkle artifact under `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle`. The script builds one disposable updater app and one disposable update app per scenario in a fresh temporary directory. Each scenario uses a fresh UUID bundle ID, an ephemeral CryptoKit Ed25519 seed, and a loopback-only feed server. The fixture app uses a test-only `SPUUserDriver` that accepts installation programmatically; it does not open Ayre or use Ayre's app identity, preferences, or Keychain.

Before serving the archive, the script signs the finalized ZIP with Sparkle's `sign_update`, checks the signature with CryptoKit and `sign_update --verify`, then fetches the ZIP over HTTP and compares it byte-for-byte with the signed source. Nothing in the update bundle or archive is modified after signing.

The invalid-signature scenario confirms Sparkle reports an update error while the old disposable app remains at version 1.0. A separate valid-signature scenario confirms Sparkle replaces that app bundle and launches version 2.0, which writes a relaunch marker. Both scenarios passed on 2026-10-22. This exercises Sparkle's download, validation, installation, replacement, and relaunch path with a programmatic test driver; it does not exercise Sparkle's standard user-facing update dialogs.
