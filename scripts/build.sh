#!/usr/bin/env bash
# Canonical app packaging path. No signing credentials are stored in this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=unsigned
team=""
identity=""
universal=false
configuration=Release
derived_data=build/DerivedData
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) mode=unsigned; shift ;;
    --team) mode=development; team="${2:?Missing team}"; shift 2 ;;
    --identity) mode=distribution; identity="${2:?Missing Developer ID Application identity}"; shift 2 ;;
    --universal) universal=true; shift ;;
    --debug) configuration=Debug; shift ;;
    --derived-data) derived_data="${2:?Missing build directory}"; shift 2 ;;
    --help|-h) echo 'Usage: scripts/build.sh [--unsigned | --team TEAM | --identity "Developer ID Application: …"] [--universal] [--debug] [--derived-data DIRECTORY]'; exit 0 ;;
    *) echo "Unknown argument: $1. Use --help." >&2; exit 2 ;;
  esac
done
swift_args=(-c release)
xcode_args=()
if $universal; then
  swift_args+=(--arch arm64 --arch x86_64)
  xcode_args+=(ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO)
fi
swift build "${swift_args[@]}"
bin_dir=$(swift build "${swift_args[@]}" --show-bin-path)
# Let Xcode process App Intents with the selected team before final nested signing.
case "$mode" in
  unsigned) xcode_args+=(CODE_SIGNING_ALLOWED=NO) ;;
  development) xcode_args+=(CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="$team" CODE_SIGN_IDENTITY="Apple Development") ;;
  distribution)
    if [[ "$identity" != 'Developer ID Application:'* || "$identity" != *')' ]]; then
      echo 'Public distribution requires a Developer ID Application identity including its team suffix.' >&2; exit 2
    fi
    team="${identity##*(}"
    team="${team%)}"
    xcode_args+=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" CODE_SIGN_IDENTITY="$identity" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
    ;;
esac
xcodebuild -project PromptInsertProbe.xcodeproj -scheme PromptInsertProbe -configuration "$configuration" \
  -derivedDataPath "$derived_data" "${xcode_args[@]}" clean build
app="$derived_data/Build/Products/$configuration/Ayre.app"
# Resolve the exact certificate selected by Xcode, without reading private key material.
if [[ "$mode" != unsigned ]]; then
  mkdir -p build/signing
  codesign --display --extract-certificates=build/signing/cert "$app"
  identity=$(shasum -a 1 build/signing/cert0 | cut -d ' ' -f 1)
fi
gui_executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")
if [[ "$(printf '%s' "$gui_executable" | tr '[:upper:]' '[:lower:]')" == ayre ]]; then
  echo 'GUI executable must have a distinct name from the bundled ayre CLI.' >&2; exit 1
fi
cp "$bin_dir/ayre" "$app/Contents/MacOS/ayre"
chmod 755 "$app/Contents/MacOS/ayre"
if [[ "$mode" != unsigned ]]; then
  signing_args=(--force --options runtime --sign "$identity")
  if [[ "$mode" == distribution ]]; then signing_args+=(--timestamp); fi
  codesign "${signing_args[@]}" "$app/Contents/MacOS/ayre"
  codesign "${signing_args[@]}" --preserve-metadata=entitlements "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
if $universal; then
  for executable in "$app/Contents/MacOS/$gui_executable" "$app/Contents/MacOS/ayre"; do
    architectures=" $(lipo -archs "$executable") "
    for architecture in arm64 x86_64; do
      if [[ "$architectures" != *" $architecture "* ]]; then
        echo "Missing $architecture architecture: $executable" >&2; exit 1
      fi
    done
  done
fi
"$app/Contents/MacOS/ayre" capabilities --json
printf '\nApp: %s\nReceiver: %s\nSigning mode: %s\n' "$app" "$bin_dir/PromptInsertProbeReceiver" "$mode"
echo 'Install or register this app with Launch Services before testing discovery/App Intents. See README.md.'
