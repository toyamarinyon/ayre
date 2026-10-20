#!/bin/sh
set -eu
plugin_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 "$plugin_root/tests/test-e2e.py"
/usr/bin/osascript -l JavaScript "$plugin_root/scripts/ayre.js" --self-test
