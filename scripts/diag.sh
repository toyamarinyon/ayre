#!/usr/bin/env bash
# Collects environment info for the report. Does not read field contents.
# Usage: scripts/diag.sh > diag.txt
cd "$(dirname "$0")/.."
echo "## sw_vers"; sw_vers
echo "## uname"; uname -m
echo "## xcodebuild -version"; xcodebuild -version 2>&1
echo "## xcode-select -p"; xcode-select -p 2>&1
echo "## swift --version"; swift --version 2>&1
echo "## SDK"; xcrun --sdk macosx --show-sdk-version 2>&1
echo "## Codex App"
found=0
while IFS= read -r app; do
  [[ -z "$app" ]] && continue
  found=1
  plist="$app/Contents/Info.plist"
  echo "path: $app"
  echo "bundleID: $(defaults read "$plist" CFBundleIdentifier 2>/dev/null)"
  echo "version: $(defaults read "$plist" CFBundleShortVersionString 2>/dev/null) ($(defaults read "$plist" CFBundleVersion 2>/dev/null))"
  if [[ -d "$app/Contents/Frameworks/Electron Framework.framework" ]]; then echo "electron: yes"; else echo "electron: no (Electron Framework.framework なし)"; fi
done < <(mdfind 'kMDItemContentType == "com.apple.application-bundle" && kMDItemDisplayName == "Codex*"c' 2>/dev/null)
[[ $found == 0 ]] && echo "Codex.app が見つかりません（mdfind）"
echo "## PromptInsertProbe.app"
for app in /Applications/PromptInsertProbe.app build/DerivedData/Build/Products/Debug/PromptInsertProbe.app; do
  [[ -d "$app" ]] || continue
  echo "path: $app"
  codesign -dv "$app" 2>&1 | grep -E 'Identifier|TeamIdentifier|Signature|CDHash'
done
echo "## Spotlight process"
pgrep -lf Spotlight | head -3
echo "## probe.log (last 300 lines)"
tail -n 300 ~/Library/Logs/PromptInsertProbe/probe.log 2>/dev/null || echo "(no log)"
