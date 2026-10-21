#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."

sparkle="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle"
framework="$sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$framework" ]] || { echo "Sparkle framework not found: $framework" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ayre-sparkle-feed.XXXXXX")
server_pid=""
fixture_id=""
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
  if [[ -n "$fixture_id" ]]; then
    defaults delete "$fixture_id" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Caches/$fixture_id"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/Fixture.app/Contents/MacOS" "$tmp/Fixture.app/Contents/Frameworks" "$tmp/payload"
cp -R "$framework" "$tmp/Fixture.app/Contents/Frameworks/"
printf 'isolated update payload\n' > "$tmp/payload/payload.txt"
ditto -c -k "$tmp/payload" "$tmp/update.zip"

cat > "$tmp/key.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
public_key=$(swift -module-cache-path "$tmp/SwiftModuleCache" "$tmp/key.swift" "$tmp/private-key")
[[ "$(stat -f %Lp "$tmp/private-key")" == 600 ]] || { echo "Ephemeral signing key permissions are not private" >&2; exit 1; }
signature_line=$("$sparkle/bin/sign_update" --ed-key-file "$tmp/private-key" -p "$tmp/update.zip")
signature=$(awk '{print $1}' <<< "$signature_line")
length=$(stat -f %z "$tmp/update.zip")

cat > "$tmp/server.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import pathlib, sys
signature, length, archive = sys.argv[2:]
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/fail.xml":
            self.send_error(503, "isolated fixture failure")
            return
        if self.path == "/update.zip":
            data = pathlib.Path(archive).read_bytes()
            self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
            return
        version = "1.0" if self.path == "/same.xml" else "2.0"
        xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Isolated fixture</title><item><title>Fixture update</title><pubDate>Wed, 21 Oct 2026 00:00:00 +0000</pubDate><sparkle:version>{version}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString><enclosure url="http://127.0.0.1:{self.server.server_port}/update.zip" length="{length}" type="application/octet-stream" sparkle:edSignature="{signature}" /></item></channel></rss>'''.encode()
        self.send_response(200); self.send_header("Content-Type", "application/rss+xml"); self.send_header("Content-Length", str(len(xml))); self.end_headers(); self.wfile.write(xml)
    def log_message(self, *_): pass
server = HTTPServer(("127.0.0.1", 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY
python3 "$tmp/server.py" "$tmp/port" "$signature" "$length" "$tmp/update.zip" & server_pid=$!
for _ in {1..100}; do [[ -s "$tmp/port" ]] && break; sleep 0.05; done
[[ -s "$tmp/port" ]] || { echo "Fixture server failed to start" >&2; exit 2; }
port=$(<"$tmp/port")
fixture_id="dev.ayre.sparkle-fixture.$(uuidgen | tr '[:upper:]' '[:lower:]')"

swiftc -module-cache-path "$tmp/SwiftModuleCache" -parse-as-library -F "$(dirname "$framework")" -framework Sparkle scripts/verify-sparkle-feed.swift -o "$tmp/Fixture.app/Contents/MacOS/verify-sparkle-feed"
cat > "$tmp/Fixture.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$fixture_id</string>
<key>CFBundleName</key><string>Ayre Sparkle Fixture</string>
<key>CFBundleExecutable</key><string>verify-sparkle-feed</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>SUFeedURL</key><string>http://127.0.0.1:$port/same.xml</string>
<key>SUPublicEDKey</key><string>$public_key</string>
<key>SUEnableAutomaticChecks</key><false/>
</dict></plist>
PLIST
probe="$tmp/Fixture.app/Contents/MacOS/verify-sparkle-feed"
run_probe() {
  local feed="$1" expected="$2"
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL http://127.0.0.1:$port/$feed" "$tmp/Fixture.app/Contents/Info.plist"
  DYLD_FRAMEWORK_PATH="$tmp/Fixture.app/Contents/Frameworks" "$probe" "$expected"
}
run_probe same.xml no-update
run_probe newer.xml update-found
run_probe fail.xml network-error
echo "PASS: isolated Sparkle 2 feed checks; fixture never downloads or installs the update."
