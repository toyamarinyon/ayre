#!/usr/bin/env python3
"""Verify the assembled Ayre app without launching it or touching user data."""
import argparse
import base64
import binascii
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile


def app_info(app: pathlib.Path) -> dict:
    with (app / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file)


def numeric_version(value: str, label: str) -> tuple[int, ...]:
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise SystemExit(f"{label} must be a numeric dotted version; got {value!r}")
    return tuple(int(part) for part in value.split("."))


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", nargs="?", default="build/DerivedData/Build/Products/Release/Ayre.app")
parser.add_argument("--distribution", action="store_true", help="Require stable Sparkle release metadata")
options = parser.parse_args()
app = pathlib.Path(options.app).resolve()
info = app_info(app)
cli = app / "Contents/MacOS/ayre"
assert info["CFBundleIdentifier"] == "com.toyamarinyon.ayre"
marketing_version = info["CFBundleShortVersionString"]
build_version = info["CFBundleVersion"]
numeric_version(marketing_version, "CFBundleShortVersionString")
numeric_version(build_version, "CFBundleVersion")
assert info["LSUIElement"] is True
icon_name = info.get("CFBundleIconFile", "")
assert icon_name, "App bundle must declare its application icon"
icon_file = icon_name if icon_name.endswith(".icns") else icon_name + ".icns"
assert (app / "Contents/Resources" / icon_file).is_file(), "Declared application icon must be bundled"
assert info.get("SUFeedURL") == "https://github.com/toyamarinyon/ayre/releases/latest/download/appcast.xml"
assert info.get("SUEnableAutomaticChecks") is False
assert info.get("SUAutomaticallyUpdate") is False
assert info.get("SUAllowsAutomaticUpdates") is False
sparkle_binary = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
assert sparkle_binary.is_file(), "Sparkle.framework must be embedded in the app"
public_key = info.get("SUPublicEDKey", "")
if public_key:
    try:
        public_key_bytes = base64.b64decode(public_key, validate=True)
    except (ValueError, binascii.Error) as error:
        raise AssertionError("Sparkle EdDSA public key must be base64 encoded") from error
    assert len(public_key_bytes) == 32, "Sparkle EdDSA public key must decode to 32 bytes"
gui = app / "Contents/MacOS" / info["CFBundleExecutable"]
assert gui.is_file()
assert not gui.samefile(cli), "GUI and CLI must be distinct files on case-insensitive macOS volumes"

with (app / "Contents/Resources/Metadata.appintents/extract.actionsdata").open() as file:
    actions = json.load(file)["actions"]
assert actions["InsertLatestPromptIntent"]["title"]["key"] == "Ayre Go"
assert actions["InsertLatestPromptIntent"]["parameters"] == []
assert actions["InsertPromptIntent"]["title"]["key"] == "Ayre Pick"
assert all(actions[key]["openAppWhenRun"] is False for key in ["InsertLatestPromptIntent", "InsertPromptIntent"])


def run(*args, data=b""):
    return subprocess.run([str(cli), *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


caps = run("capabilities", "--json")
assert caps.returncode == 0, caps.stderr
capabilities = json.loads(caps.stdout)
assert capabilities["protocolVersion"] == 1 and "put" in capabilities["capabilities"]
# The CLI contract is versioned independently from the GUI app bundle.
cli_version = run("--version")
assert cli_version.returncode == 0 and cli_version.stdout.strip()
assert capabilities["version"] == cli_version.stdout.decode().strip()
with tempfile.TemporaryDirectory(prefix="Ayre packaged CLI ") as directory:
    target = pathlib.Path(directory) / "unicode.md"
    body = "# Exact title\r\n\r\n日本語 👨‍👩‍👧‍👦 e\u0301\nTrailing spaces  \r\n".encode("utf-8")
    args = ("put", "unicode", "--title", "Exact title", "--store", directory)
    saved = run(*args, data=body)
    assert saved.returncode == 0, saved.stderr
    assert target.read_bytes() == body
    conflict = run(*args, data=body + b"replacement")
    assert conflict.returncode != 0
    assert target.read_bytes() == body
    replacement = body + b"new body\n"
    updated = run(*args, "--overwrite", data=replacement)
    assert updated.returncode == 0, updated.stderr
    assert target.read_bytes() == replacement
    for slug, title, invalid in [("invalid", "invalid", b"\xff"), ("large", "large", b"a" * 1_000_001), ("mismatch", "Wrong", b"# Right\n")]:
        failed = run("put", slug, "--title", title, "--store", directory, data=invalid)
        assert failed.returncode != 0
        assert not (pathlib.Path(directory) / (slug + ".md")).exists()

if options.distribution:
    assert isinstance(public_key, str) and public_key.strip(), "Public distribution needs the Sparkle EdDSA public key"
    macho_files = []
    for candidate in (app / "Contents").rglob("*"):
        if candidate.is_file():
            file_type = subprocess.run(["file", "-b", str(candidate)], text=True, capture_output=True, check=True).stdout
            if "Mach-O" in file_type:
                macho_files.append(candidate)
    assert gui in macho_files and cli in macho_files and sparkle_binary in macho_files, "Expected Ayre, CLI, and Sparkle Mach-O binaries"
    assert len(macho_files) >= 7, "Expected embedded Sparkle helper and framework binaries"
    for executable in macho_files:
        architectures = set(subprocess.run(["lipo", "-archs", str(executable)], text=True, capture_output=True, check=True).stdout.split())
        assert {"arm64", "x86_64"}.issubset(architectures), f"Public binary must be universal: {executable} ({sorted(architectures)})"
        entitlements = subprocess.run(["codesign", "-d", "--entitlements=-", "--xml", str(executable)], capture_output=True, check=True)
        values = plistlib.loads(entitlements.stdout) if entitlements.stdout.strip() else {}
        assert not values.get("com.apple.security.get-task-allow", False), "Public builds must not allow debugger attachment"
if options.distribution:
    print(f"PASS: {info['CFBundleIdentifier']} app {marketing_version} ({build_version}); independent CLI {cli_version.stdout.decode().strip()}; Sparkle distribution metadata, universal nested code, and bundled CLI behavior")
else:
    print(f"PASS: {info['CFBundleIdentifier']} app {marketing_version} ({build_version}); independent CLI {cli_version.stdout.decode().strip()}; Sparkle framework/config and bundled CLI behavior")
