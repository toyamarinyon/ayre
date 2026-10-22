#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
sparkle=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle
framework="$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
sign_update="$sparkle/bin/sign_update"
for tool in swift swiftc python3 curl open codesign ditto uuidgen; do
 command -v "$tool" >/dev/null 2>&1 || { echo "Required fixture tool is unavailable: $tool" >&2; exit 2; }
done
[[ -d "$framework" && -x "$sign_update" ]] || { echo "Sparkle framework or sign_update tool not found under $sparkle" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ayre-sparkle-install.XXXXXX")
tmp=$(cd "$tmp" && pwd -P)
pids=()
app_pids=()
app_paths=()
bundle_ids=()
cleanup() {
 local i p command
 i=0
 while [[ "$i" -lt "${#app_pids[@]}" ]]; do
  p="${app_pids[$i]}"; command=$(ps -p "$p" -o command= 2>/dev/null || true)
  command="${command%% *}"
  command=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$command" 2>/dev/null || true)
  if [[ -n "$command" && "$command" == "${app_paths[$i]}" ]]; then kill "$p" 2>/dev/null || true; fi
  i=$((i + 1))
 done
 for p in "${pids[@]-}"; do [[ -n "$p" ]] || continue; kill "$p" 2>/dev/null || true; done
 for p in "${pids[@]-}"; do [[ -n "$p" ]] || continue; wait "$p" 2>/dev/null || true; done
 for p in "${bundle_ids[@]-}"; do
  [[ -n "$p" ]] || continue
  defaults delete "$p" >/dev/null 2>&1 || true
  for attempt in {1..20}; do
   rm -rf "$HOME/Library/Caches/$p" 2>/dev/null || true
   [[ -e "$HOME/Library/Caches/$p" ]] || break
   sleep .1
  done
 done
 rm -rf "$tmp"
}
trap cleanup EXIT
swiftc -module-cache-path "$tmp/Modules" -parse-as-library -F "$(dirname "$framework")" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' scripts/verify-sparkle-install.swift -o "$tmp/fixture"
cat > "$tmp/key.swift" <<'SWIFT'
import CryptoKit
import Foundation
let k = Curve25519.Signing.PrivateKey()
try Data(k.rawRepresentation.base64EncodedString().utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
print(k.publicKey.rawRepresentation.base64EncodedString())
SWIFT
cat > "$tmp/check.swift" <<'SWIFT'
import CryptoKit
import Foundation
let k = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: CommandLine.arguments[1])!)
let sig = Data(base64Encoded: CommandLine.arguments[2])!
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard k.isValidSignature(sig, for: bytes) else { fatalError("CryptoKit rejected Sparkle sign_update signature") }
print(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
SWIFT
cat > "$tmp/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import pathlib, sys
import base64
p=pathlib.Path(sys.argv[1])
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=="/update.zip":
   b=(p/"update.zip").read_bytes(); self.send_response(200); self.send_header("Content-Length",str(len(b))); self.end_headers(); self.wfile.write(b); return
  sig,n=(p/"meta").read_text().splitlines()
  if not (p/"valid").exists():
   raw=bytearray(base64.b64decode(sig, validate=True)); raw[0] ^= 1; sig=base64.b64encode(raw).decode("ascii")
  x=f'''<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Fixture</title><item><title>Fixture update</title><pubDate>Wed, 21 Oct 2026 00:00:00 +0000</pubDate><sparkle:version>2.0</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><enclosure url="http://127.0.0.1:{self.server.server_port}/update.zip" length="{n}" type="application/octet-stream" sparkle:edSignature="{sig}" /></item></channel></rss>'''.encode()
  self.send_response(200); self.send_header("Content-Type","application/rss+xml"); self.send_header("Content-Length",str(len(x))); self.end_headers(); self.wfile.write(x)
 def log_message(self,*_): pass
s=HTTPServer(("127.0.0.1",0),H); (p/"port").write_text(str(s.server_port)); s.serve_forever()
PY

run_case() {
 local mode="$1" root="$tmp/$1" line private pub id port sig n app version seed_file
 mkdir -p "$root/Old.app/Contents/MacOS" "$root/Old.app/Contents/Frameworks" "$root/Update.app/Contents/MacOS" "$root/Update.app/Contents/Frameworks" "$root/marker"
 id="dev.ayre.sparkle.installfixture.$(uuidgen | tr '[:upper:]' '[:lower:]')"
 bundle_ids+=("$id")
 seed_file="$root/private.seed"
 pub=$(swift -module-cache-path "$tmp/Modules" "$tmp/key.swift" "$seed_file")
 [[ "$(stat -f %Lp "$seed_file")" == 600 ]] || { echo "Ephemeral key file permissions are not private" >&2; return 1; }
 python3 "$tmp/server.py" "$root" & pids+=("$!")
 for _ in {1..100}; do [[ -s "$root/port" ]] && break; sleep .05; done
 [[ -s "$root/port" ]] || { echo "Loopback fixture server failed to publish its port" >&2; return 1; }
 port=$(<"$root/port")
 for entry in 'Old.app 1.0' 'Update.app 2.0'; do
  read -r app version <<< "$entry"; target="$root/$app"
  cp "$tmp/fixture" "$target/Contents/MacOS/AyreFixture"; cp -R "$framework" "$target/Contents/Frameworks/"
  cat > "$target/Contents/Info.plist" <<PLIST
<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string><key>CFBundleName</key><string>Disposable Sparkle Fixture</string><key>CFBundleExecutable</key><string>AyreFixture</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>$version</string><key>CFBundleShortVersionString</key><string>$version</string>
<key>SUFeedURL</key><string>http://127.0.0.1:$port/feed.xml</string><key>SUPublicEDKey</key><string>$pub</string><key>SUEnableAutomaticChecks</key><false/><key>FixtureMarker</key><string>$root/marker</string><key>FixtureInvalidCase</key><$([[ "$mode" == invalid ]] && echo true || echo false)/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict></dict></plist>
PLIST
  codesign --force --sign - --timestamp=none "$target/Contents/MacOS/AyreFixture" >/dev/null
  codesign --force --sign - --timestamp=none "$target" >/dev/null
  codesign --verify --deep --strict "$target"
 done
 ditto -c -k --sequesterRsrc --keepParent "$root/Update.app" "$root/update.zip"
 sig=$("$sign_update" --ed-key-file "$root/private.seed" -p "$root/update.zip" | awk '{print $1}')
 n=$(stat -f %z "$root/update.zip")
 hash=$(swift -module-cache-path "$tmp/Modules" "$tmp/check.swift" "$pub" "$sig" "$root/update.zip")
 "$sign_update" --verify --ed-key-file "$root/private.seed" "$root/update.zip" "$sig"
 printf '%s\n%s\n' "$sig" "$n" > "$root/meta"
 [[ "$mode" != valid ]] || touch "$root/valid"
 curl -fsS "http://127.0.0.1:$port/update.zip" -o "$root/served.zip"; cmp "$root/update.zip" "$root/served.zip"
 echo "PASS: $mode archive signature verified; served bytes match (sha256 $hash)."
 open -g -n "$root/Old.app"
 expected_executable=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$root/Old.app/Contents/MacOS/AyreFixture")
 for _ in {1..100}; do [[ -s "$root/marker/updater-process" ]] && break; sleep .1; done
 [[ -s "$root/marker/updater-process" ]] || { echo "Fixture process did not publish its PID and executable path" >&2; return 1; }
 process_pid=$(sed -n '1p' "$root/marker/updater-process")
 process_path=$(sed -n '2p' "$root/marker/updater-process")
 same_executable=$(python3 -c 'import os,sys; print("yes" if os.path.samefile(sys.argv[1],sys.argv[2]) else "no")' "$expected_executable" "$process_path")
 [[ "$same_executable" == yes ]] || { echo "Fixture executable path did not match its temporary app bundle: $process_path (expected $expected_executable)" >&2; return 1; }
 app_pids+=("$process_pid"); app_paths+=("$process_path")
 if [[ "$mode" == invalid ]]; then
  for _ in {1..300}; do [[ -s "$root/marker/signature-rejection" || -s "$root/marker/unexpected-error" ]] && break; sleep .1; done
  [[ -s "$root/marker/signature-rejection" ]] || { echo 'Sparkle did not report the expected signature-validation error' >&2; cat "$root/marker/unexpected-error" 2>/dev/null || true; return 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/Old.app/Contents/Info.plist")" == 1.0 ]] || return 1
  [[ ! -e "$root/marker/relaunched" ]] || { echo 'Invalid signature relaunched the fixture' >&2; return 1; }
 else
  for _ in {1..300}; do [[ -s "$root/marker/relaunched" ]] && break; sleep .1; done
  [[ -s "$root/marker/relaunched" ]] || { echo 'valid update did not relaunch' >&2; cat "$root/marker/unexpected-error" 2>/dev/null || true; return 1; }
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/Old.app/Contents/Info.plist")" == 2.0 ]] || return 1
 fi
}
run_case invalid
run_case valid
echo 'PASS: isolated invalid signature rejection and valid Sparkle replacement/relaunch.'
