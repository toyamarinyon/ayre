#!/usr/bin/env bash
# Build, notarize, staple, then create the final EdDSA-signed Sparkle package/feed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
  echo 'Usage: scripts/release.sh "Developer ID Application: …" NOTARY_KEYCHAIN_PROFILE' >&2
  echo 'Requires Apple distribution signing/notarization credentials and a Sparkle EdDSA private key.' >&2
  exit 2
fi
sparkle_private_key=${SPARKLE_PRIVATE_KEY:?Set SPARKLE_PRIVATE_KEY to the Sparkle EdDSA private key (stdin only; never a command-line argument).}
unset SPARKLE_PRIVATE_KEY
: "${AYRE_SPARKLE_PUBLIC_ED_KEY:?Set AYRE_SPARKLE_PUBLIC_ED_KEY to the matching public key before building.}"
if [[ "$sparkle_private_key" == *$'\n'* ]]; then
  echo 'SPARKLE_PRIVATE_KEY must be a single line.' >&2
  exit 2
fi

sparkle_bin=${SPARKLE_BIN:-build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}
generate_appcast="$sparkle_bin/generate_appcast"
plist_buddy=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}
bash scripts/build.sh --identity "$1" --universal
app=build/DerivedData/Build/Products/Release/Ayre.app
python3 scripts/verify-package.py "$app" --distribution
if [[ ! -x "$generate_appcast" ]]; then
  echo "Sparkle 2.10 generate_appcast was not found at $generate_appcast after dependency resolution." >&2
  exit 1
fi
marketing_version=$("$plist_buddy" -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build_version=$("$plist_buddy" -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
release_tag=${RELEASE_TAG:-v$marketing_version}
if [[ "$release_tag" != "v$marketing_version" ]]; then
  echo "Release tag $release_tag does not match app version $marketing_version." >&2
  exit 1
fi

release_dir=build/release
rm -rf "$release_dir"
mkdir -p "$release_dir"
archive_name="Ayre-${marketing_version}-macOS.zip"
archive="$release_dir/$archive_name"
submission_zip="$release_dir/notarization-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$submission_zip"
xcrun notarytool submit "$submission_zip" --keychain-profile "$2" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl --assess --type execute --verbose=2 "$app"
# Sparkle signs these exact final, stapled bytes; never reuse the pre-stapling ZIP.
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
rm -f "$submission_zip"

download_prefix="https://github.com/toyamarinyon/ayre/releases/download/${release_tag}/"
printf '%s\n' "$sparkle_private_key" | "$generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$download_prefix" \
  -o "$release_dir/appcast.xml" \
  "$release_dir"

verify_args=(
  --app "$app"
  --appcast "$release_dir/appcast.xml"
  --archive "$archive"
  --tag "$release_tag"
  --sign-update "$sparkle_bin/sign_update"
)
previous_dir=${PREVIOUS_APPCAST_DIR:-}
if [[ -n "$previous_dir" && -d "$previous_dir" ]]; then
  while IFS= read -r -d '' feed; do verify_args+=(--previous-feed "$feed"); done \
    < <(find "$previous_dir" -type f -name '*.xml' -print0)
fi
printf '%s\n' "$sparkle_private_key" | python3 scripts/verify-appcast.py \
  "${verify_args[@]}"
(
  cd "$release_dir"
  shasum -a 256 "$archive_name" appcast.xml > SHA256SUMS
)
echo "Ready for review and GitHub draft upload: $release_dir/$archive_name"
echo "Sparkle feed: $release_dir/appcast.xml"
echo "App version/build: $marketing_version/$build_version"
