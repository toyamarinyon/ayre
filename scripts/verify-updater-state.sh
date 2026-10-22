#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

sparkle_framework="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$sparkle_framework" ]] || { echo "Sparkle 2.10.0 framework not found: $sparkle_framework" >&2; exit 2; }
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/ayre-updater-state.XXXXXX")
bundle_id=""
cleanup() {
  if [[ -n "$bundle_id" ]]; then defaults delete "$bundle_id" >/dev/null 2>&1 || true; fi
  rm -rf "$temporary_root"
}
trap cleanup EXIT

app_bundle="$temporary_root/UpdaterProbe.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Frameworks"
cp -R "$sparkle_framework" "$app_bundle/Contents/Frameworks/"
bundle_id="dev.ayre.sparkle.preferences.$(uuidgen | tr '[:upper:]' '[:lower:]')"

cat > "$app_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Ayre Updater State Probe</string>
<key>CFBundleExecutable</key><string>verify-updater-state</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>SUFeedURL</key><string>https://updates.example.invalid/appcast.xml</string>
<key>SUPublicEDKey</key><string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUAllowsAutomaticUpdates</key><false/>
</dict></plist>
PLIST

swiftc -parse-as-library -module-cache-path "$temporary_root/ModuleCache" \
  -F "$(dirname "$sparkle_framework")" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  App/UpdaterController.swift scripts/verify-updater-state.swift \
  -o "$app_bundle/Contents/MacOS/verify-updater-state"

"$app_bundle/Contents/MacOS/verify-updater-state"
PlistBuddy=/usr/libexec/PlistBuddy
"$PlistBuddy" -c 'Set :SUPublicEDKey not-base64' "$app_bundle/Contents/Info.plist"
"$app_bundle/Contents/MacOS/verify-updater-state" invalid-configuration
"$PlistBuddy" -c 'Delete :SUPublicEDKey' "$app_bundle/Contents/Info.plist"
"$app_bundle/Contents/MacOS/verify-updater-state" invalid-configuration
echo "No network request or update installation was performed."
