#!/usr/bin/env bash
# Explicitly invoked distribution: signed universal build, notarize, staple, verify, ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
  echo 'Usage: scripts/release.sh "Developer ID Application: …" NOTARY_KEYCHAIN_PROFILE' >&2
  echo 'Requires Apple Developer Program membership, a certificate/private key, and a preconfigured notarytool Keychain profile.' >&2
  exit 2
fi
bash scripts/build.sh --identity "$1" --universal
app=build/DerivedData/Build/Products/Release/Ayre.app
python3 scripts/verify-package.py "$app" --distribution
mkdir -p build/release
archive=build/release/Ayre-0.2.1-macOS.zip
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$2" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$archive"
shasum -a 256 "$archive"
echo "Ready for review and GitHub Release upload: $archive"
