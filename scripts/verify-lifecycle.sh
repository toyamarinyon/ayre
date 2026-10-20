#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary_root=$(mktemp -d)
trap 'rm -rf "$temporary_root"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  Sources/Core/AppLifecycleState.swift App/AppLifecycle.swift scripts/verify-lifecycle.swift \
  -o "$temporary_root/check"
"$temporary_root/check"
