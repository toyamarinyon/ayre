#!/usr/bin/env python3
"""Offline regression tests for release.sh argument handling and signing order."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TEST_KEY = "dummy-test-only-key-never-use-in-production"


TOOL = r'''#!/bin/bash
set -eu
name=${0##*/}
log_event() { printf '%s\n' "$1" >> "$EVENT_LOG"; }
check_no_key() {
  if [[ ${SPARKLE_PRIVATE_KEY+x} ]]; then echo "private key leaked to $name" >&2; exit 90; fi
}
check_no_key
case "$name" in
  build.sh)
    log_event build
    mkdir -p build/DerivedData/Build/Products/Release/Ayre.app/Contents
    printf 'fake app\n' > build/DerivedData/Build/Products/Release/Ayre.app/Contents/Info.plist
    ;;
  PlistBuddy)
    case "$*" in *CFBundleShortVersionString*) echo 1.2.3;; *) echo 7;; esac
    ;;
  python3)
    case "$1" in
      scripts/verify-package.py) log_event verify-package;;
      scripts/verify-appcast.py)
        key=$(cat)
        [[ "$key" == "$EXPECTED_TEST_PRIVATE_KEY" ]] || { echo wrong verifier key >&2; exit 91; }
        count=0
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == --previous-feed ]]; then count=$((count + 1)); fi
          shift
        done
        log_event "verify-appcast:$count"
        [[ ${FAIL_VERIFY_APPCAST:-0} == 0 ]] || exit 12
        ;;
      *) exec /usr/bin/python3 "$@";;
    esac
    ;;
  ditto)
    src=$((0))
    dest=${!#}
    for arg in "$@"; do [[ "$arg" == *.app ]] && src="$arg"; done
    if [[ "$dest" == *notarization-submission.zip ]]; then
      log_event submission-zip
    else
      [[ -f "$src/Contents/STAPLED" ]] || { echo final archive made before stapling >&2; exit 92; }
      log_event final-zip
    fi
    printf zip > "$dest"
    ;;
  xcrun)
    if [[ "$1" == notarytool ]]; then
      log_event notary
      [[ ${FAIL_NOTARY:-0} == 0 ]] || exit 13
    elif [[ "$1" == stapler && "$2" == staple ]]; then
      log_event staple
      touch "$3/Contents/STAPLED"
    elif [[ "$1" == stapler && "$2" == validate ]]; then log_event staple-validate
    else echo "unexpected xcrun arguments: $*" >&2; exit 93
    fi
    ;;
  codesign) log_event codesign;;
  spctl) log_event spctl;;
  generate_appcast)
    key=
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --ed-key-file ]]; then shift; [[ "$1" == - ]] || exit 94; key=$(cat); fi
      if [[ "$1" == -o ]]; then shift; output=$1; fi
      shift
    done
    [[ "$key" == "$EXPECTED_TEST_PRIVATE_KEY" ]] || { echo wrong generator key >&2; exit 95; }
    log_event generate-appcast
    printf '<rss/>\n' > "$output"
    ;;
  *) echo "unexpected tool $name" >&2; exit 96;;
esac
'''


class ReleaseScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/release.sh", self.root / "scripts/release.sh")
        (self.root / "scripts/build.sh").write_text("#!/bin/bash\nexec \"$MOCK_BIN/build.sh\"\n")
        (self.root / "scripts/verify-package.py").touch()
        (self.root / "scripts/verify-appcast.py").touch()
        self.bin = self.root / "mock-bin"
        self.bin.mkdir()
        dispatch = self.bin / "dispatch"
        dispatch.write_text(TOOL)
        dispatch.chmod(0o755)
        for name in ("build.sh", "PlistBuddy", "python3", "ditto", "xcrun", "codesign", "spctl"):
            (self.bin / name).symlink_to(dispatch)
        self.sparkle = self.root / "sparkle"
        self.sparkle.mkdir()
        (self.sparkle / "generate_appcast").symlink_to(dispatch)
        self.events = self.root / "events"
        self.previous = self.root / "previous"
        self.previous.mkdir()
        self.env = os.environ.copy()
        self.env.update({
            "PATH": str(self.bin) + os.pathsep + self.env.get("PATH", ""),
            "MOCK_BIN": str(self.bin), "EVENT_LOG": str(self.events),
            "EXPECTED_TEST_PRIVATE_KEY": TEST_KEY, "SPARKLE_PRIVATE_KEY": TEST_KEY,
            "AYRE_SPARKLE_PUBLIC_ED_KEY": "dummy-public-key",
            "SPARKLE_BIN": str(self.sparkle), "PLIST_BUDDY": str(self.bin / "PlistBuddy"),
            "PREVIOUS_APPCAST_DIR": str(self.previous),
        })

    def tearDown(self):
        self.temp.cleanup()

    def run_release(self, **overrides):
        env = self.env.copy()
        env.update(overrides)
        return subprocess.run(["/bin/bash", str(self.root / "scripts/release.sh"), "Developer ID Test", "test-profile"],
                              cwd=self.root, env=env, text=True, capture_output=True)

    def event_list(self):
        return self.events.read_text().splitlines() if self.events.exists() else []

    def test_first_release_empty_history_and_secure_order(self):
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.event_list()
        self.assertIn("verify-appcast:0", events)
        expected = ["notary", "staple", "final-zip", "generate-appcast", "verify-appcast:0"]
        positions = [events.index(item) for item in expected]
        self.assertEqual(positions, sorted(positions), events)
        self.assertNotIn(TEST_KEY, result.stdout + result.stderr)
        self.assertTrue((self.root / "build/release/SHA256SUMS").exists())

    def test_previous_feed_is_passed(self):
        (self.previous / "v1.xml").write_text("<rss/>")
        result = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("verify-appcast:1", self.event_list())

    def test_verification_failure_stops_before_checksum_and_publish_message(self):
        result = self.run_release(FAIL_VERIFY_APPCAST="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("Ready for review", result.stdout)
        self.assertFalse((self.root / "build/release/SHA256SUMS").exists())

    def test_notary_failure_stops_before_stapling_and_signing(self):
        result = self.run_release(FAIL_NOTARY="1")
        self.assertNotEqual(result.returncode, 0)
        events = self.event_list()
        self.assertIn("notary", events)
        self.assertNotIn("staple", events)
        self.assertNotIn("generate-appcast", events)


if __name__ == "__main__":
    unittest.main()
