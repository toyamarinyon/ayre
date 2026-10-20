#!/usr/bin/env bash
# Builds the CLI/receiver (SwiftPM) and the app (Xcode). Usage: scripts/build.sh [DEVELOPMENT_TEAM]
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
extra=()
if [[ -n "${1:-}" ]]; then
  # A real team keeps the code signature stable across rebuilds, so the Accessibility grant survives.
  extra=(DEVELOPMENT_TEAM="$1" CODE_SIGN_IDENTITY="Apple Development")
fi
xcodebuild -project PromptInsertProbe.xcodeproj -scheme PromptInsertProbe -configuration Debug \
  -derivedDataPath build/DerivedData ${extra[@]+"${extra[@]}"} build
app=build/DerivedData/Build/Products/Debug/PromptInsertProbe.app
echo
echo "CLI:      $(swift build -c release --show-bin-path)/PromptInsertProbeCLI"
echo "Receiver: $(swift build -c release --show-bin-path)/PromptInsertProbeReceiver"
echo "App:      $app"
echo "For Spotlight/App Intents testing, copy the app to /Applications before launching:"
echo "  rm -rf /Applications/PromptInsertProbe.app && cp -R $app /Applications/ && open /Applications/PromptInsertProbe.app"
