#!/usr/bin/env python3
"""Verify the assembled app without launching UI or touching the user's prompt store."""
import argparse
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', nargs='?', default='build/DerivedData/Build/Products/Release/Ayre.app')
parser.add_argument('--distribution', action='store_true', help='Reject debug entitlements before public notarization')
options = parser.parse_args()
app = pathlib.Path(options.app).resolve()
cli = app / 'Contents/MacOS/ayre'
with (app / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info['CFBundleIdentifier'] == 'com.toyamarinyon.ayre'
assert info['CFBundleShortVersionString'] == '0.2.0'
assert info['LSUIElement'] is True
gui = app / 'Contents/MacOS' / info['CFBundleExecutable']
assert gui.is_file()
assert not gui.samefile(cli), 'GUI and CLI must be distinct files on case-insensitive macOS volumes'

with (app / 'Contents/Resources/Metadata.appintents/extract.actionsdata').open() as file:
    actions = json.load(file)['actions']
assert actions['InsertLatestPromptIntent']['title']['key'] == 'Ayre Go'
assert actions['InsertLatestPromptIntent']['parameters'] == []
assert actions['InsertPromptIntent']['title']['key'] == 'Ayre Pick'
assert all(actions[key]['openAppWhenRun'] is False for key in ['InsertLatestPromptIntent', 'InsertPromptIntent'])

def run(*args, data=b''):
    return subprocess.run([str(cli), *args], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)

caps = run('capabilities', '--json')
assert caps.returncode == 0, caps.stderr
capabilities = json.loads(caps.stdout)
assert capabilities['protocolVersion'] == 1 and 'put' in capabilities['capabilities']
assert capabilities['version'] == '0.2.0'
with tempfile.TemporaryDirectory(prefix='Ayre packaged CLI ') as directory:
    target = pathlib.Path(directory) / 'unicode.md'
    body = '# Exact title\r\n\r\n日本語 👨‍👩‍👧‍👦 e\u0301\nTrailing spaces  \r\n'.encode('utf-8')
    args = ('put', 'unicode', '--title', 'Exact title', '--store', directory)
    saved = run(*args, data=body)
    assert saved.returncode == 0, saved.stderr
    assert target.read_bytes() == body
    conflict = run(*args, data=body + b'replacement')
    assert conflict.returncode != 0
    assert target.read_bytes() == body
    replacement = body + b'new body\n'
    updated = run(*args, '--overwrite', data=replacement)
    assert updated.returncode == 0, updated.stderr
    assert target.read_bytes() == replacement
    for slug, title, invalid in [('invalid', 'invalid', b'\xff'), ('large', 'large', b'a' * 1_000_001), ('mismatch', 'Wrong', b'# Right\n')]:
        failed = run('put', slug, '--title', title, '--store', directory, data=invalid)
        assert failed.returncode != 0
        assert not (pathlib.Path(directory) / (slug + '.md')).exists()
if options.distribution:
    for executable in [app, cli]:
        entitlements = subprocess.run(['codesign', '-d', '--entitlements=-', '--xml', str(executable)], capture_output=True, check=True)
        values = plistlib.loads(entitlements.stdout) if entitlements.stdout.strip() else {}
        assert not values.get('com.apple.security.get-task-allow', False), 'Public builds must not allow debugger attachment'
print('PASS: app identity/background metadata, bundled CLI compatibility, exact UTF-8 registration, no-clobber, overwrite, invalid/large/title rejection (temporary store only)')
