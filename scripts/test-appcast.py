#!/usr/bin/env python3
"""Offline regression tests for Sparkle appcast validation and stable release policy."""
import importlib.util
import pathlib
import plistlib
import base64
import os
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile

MODULE_PATH = pathlib.Path(__file__).with_name("verify-appcast.py")
spec = importlib.util.spec_from_file_location("verify_appcast", MODULE_PATH)
verify_appcast = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(verify_appcast)


def ephemeral_keypair(directory: pathlib.Path):
    module_cache = directory / "swift-module-cache"
    module_cache.mkdir()
    generated = subprocess.run(
        ["swift", "-module-cache-path", str(module_cache), "-e",
         "import CryptoKit; let key = Curve25519.Signing.PrivateKey(); print(key.rawRepresentation.base64EncodedString()); print(key.publicKey.rawRepresentation.base64EncodedString())"],
        text=True, capture_output=True, check=True, timeout=30,
    )
    seed, public_key = generated.stdout.strip().splitlines()
    if len(base64.b64decode(seed, validate=True)) != 32 or len(base64.b64decode(public_key, validate=True)) != 32:
        raise AssertionError("CryptoKit emitted an invalid ephemeral Ed25519 keypair")
    key_file = directory / "ephemeral-ed25519.seed"
    key_file.write_text(seed + "\n")
    key_file.chmod(0o600)
    return seed, public_key, key_file


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="Ayre appcast tests ")
        self.root = pathlib.Path(self.temp.name)
        self.app = self.root / "Ayre.app"
        (self.app / "Contents").mkdir(parents=True)
        self.archive = self.root / "Ayre-0.2.2-macOS.zip"
        self.archive.write_bytes(b"not a real zip; only size metadata is used")
        info = {
            "CFBundleShortVersionString": "0.2.2",
            "CFBundleVersion": "2",
            "LSMinimumSystemVersion": "14.0",
            "SUFeedURL": verify_appcast.APPCAST_URL,
            "SUPublicEDKey": "test-public-key",
        }
        with (self.app / "Contents/Info.plist").open("wb") as file:
            plistlib.dump(info, file)
        self.feed = self.root / "appcast.xml"
        self.write_feed()

    def tearDown(self):
        self.temp.cleanup()

    def write_feed(self, *, version="2", tag="v0.2.2", length=None, signature=None, channel=""):
        length = self.archive.stat().st_size if length is None else length
        signature = "A" * 86 + "==" if signature is None else signature
        xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="{verify_appcast.SPARKLE}" version="2.0"><channel>
<item><sparkle:version>{version}</sparkle:version><sparkle:shortVersionString>0.2.2</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:channel>{channel}</sparkle:channel><enclosure url="https://github.com/toyamarinyon/ayre/releases/download/{tag}/{self.archive.name}"
sparkle:edSignature="{signature}" length="{length}" type="application/octet-stream" /></item>
</channel></rss>'''
        self.feed.write_text(xml)

    def verify(self, previous=(), tag="v0.2.2"):
        verify_appcast.verify(self.app, self.feed, self.archive, tag, list(previous))

    def test_accepts_signed_stable_feed_and_exact_archive_size(self):
        self.verify()

    def test_rejects_missing_or_malformed_signature(self):
        self.write_feed(signature="not-base64!")
        with self.assertRaisesRegex(ValueError, "valid EdDSA signature"):
            self.verify()

    def test_rejects_archive_length_mismatch(self):
        self.write_feed(length=1)
        with self.assertRaisesRegex(ValueError, "length does not match"):
            self.verify()

    def test_rejects_tag_mismatch_and_prerelease_tag(self):
        with self.assertRaisesRegex(ValueError, "does not match app version"):
            self.verify(tag="v0.2.3")
        with self.assertRaisesRegex(ValueError, "stable"):
            self.verify(tag="v0.2.2-rc1")

    def test_rejects_non_monotonic_bundle_build(self):
        previous = self.root / "previous.xml"
        previous.write_text(f'''<rss xmlns:sparkle="{verify_appcast.SPARKLE}"><channel>
<item><sparkle:version>2</sparkle:version></item></channel></rss>''')
        with self.assertRaisesRegex(ValueError, "not greater"):
            self.verify(previous=[previous])

    def test_rejects_prerelease_channel(self):
        self.write_feed(channel="beta")
        with self.assertRaisesRegex(ValueError, "prerelease channel"):
            self.verify()

    def test_sparkle_signature_and_tamper_rejection_with_ephemeral_key(self):
        sparkle_bin = pathlib.Path(os.environ.get(
            "SPARKLE_BIN",
            "build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin",
        ))
        sign_update = sparkle_bin / "sign_update"
        if not sign_update.is_file():
            self.skipTest("Sparkle sign_update is not available")
        _, _, key_file = ephemeral_keypair(self.root)
        archive = self.root / "signed.zip"
        with zipfile.ZipFile(archive, "w") as package:
            package.writestr("payload.txt", "offline Sparkle signature fixture")
        signed = subprocess.run(
            [str(sign_update), "--ed-key-file", str(key_file), "-p", str(archive)],
            text=True, capture_output=True, check=True, timeout=30,
        )
        match = re.search(r'sparkle:edSignature="([^"]+)"', signed.stdout)
        signature = match.group(1) if match else signed.stdout.strip()
        self.assertEqual(len(base64.b64decode(signature, validate=True)), 64, signed.stdout + signed.stderr)
        verified = subprocess.run(
            [str(sign_update), "--verify", "--ed-key-file", str(key_file), str(archive), signature],
            text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)
        with archive.open("ab") as file:
            file.write(b"tampered")
        rejected = subprocess.run(
            [str(sign_update), "--verify", "--ed-key-file", str(key_file), str(archive), signature],
            text=True, capture_output=True, timeout=30,
        )
        self.assertNotEqual(rejected.returncode, 0, "Sparkle accepted an archive changed after signing")

    def test_real_generate_appcast_output_and_wrong_key_rejection(self):
        sparkle_bin = pathlib.Path(os.environ.get(
            "SPARKLE_BIN",
            "build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin",
        ))
        generate_appcast = sparkle_bin / "generate_appcast"
        sign_update = sparkle_bin / "sign_update"
        if not generate_appcast.is_file() or not sign_update.is_file():
            self.skipTest("Sparkle command-line tools are not available")
        seed, public_key, key_file = ephemeral_keypair(self.root)
        source_app = pathlib.Path(os.environ.get(
            "AYRE_TEST_APP",
            "build/DerivedData/Build/Products/Release/Ayre.app",
        ))
        if not source_app.is_dir():
            self.skipTest("Build Ayre.app before testing generated appcast output")
        app = self.root / "Ayre.app"
        subprocess.run(["ditto", str(source_app), str(app)], check=True)
        app_signature = app / "Contents/_CodeSignature"
        if app_signature.exists():
            shutil.rmtree(app_signature)
        info_path = app / "Contents/Info.plist"
        with info_path.open("rb") as file:
            info = plistlib.load(file)
        info["SUPublicEDKey"] = public_key
        info["SUFeedURL"] = verify_appcast.APPCAST_URL
        with info_path.open("wb") as file:
            plistlib.dump(info, file)
        marketing_version = info["CFBundleShortVersionString"]
        bundle_version = info["CFBundleVersion"]
        tag = f"v{marketing_version}"
        update_dir = self.root / "updates"
        update_dir.mkdir()
        isolated_home = self.root / "isolated-home"
        isolated_home.mkdir()
        tool_env = os.environ.copy()
        # Sparkle's tool caches extracted archives under ~/Library/Caches; isolate
        # that cache inside the temporary fixture instead of touching user state.
        tool_env["HOME"] = str(isolated_home)
        tool_env["CFFIXED_USER_HOME"] = str(isolated_home)
        archive = update_dir / f"Ayre-{marketing_version}-macOS.zip"
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
        generated = subprocess.run(
            [str(generate_appcast), "--ed-key-file", str(key_file),
             "--download-url-prefix", f"https://github.com/toyamarinyon/ayre/releases/download/{tag}/",
             "-o", str(update_dir / "appcast.xml"), str(update_dir)],
            text=True, capture_output=True, timeout=120, env=tool_env,
        )
        self.assertEqual(generated.returncode, 0, generated.stdout + generated.stderr)
        feed = update_dir / "appcast.xml"
        validated = subprocess.run(
            ["python3", str(MODULE_PATH), "--app", str(app), "--appcast", str(feed),
             "--archive", str(archive), "--tag", tag, "--sign-update", str(sign_update)],
            input=seed + "\n", text=True, capture_output=True, timeout=30,
        )
        self.assertEqual(validated.returncode, 0, validated.stdout + validated.stderr)
        wrong_key_dir = self.root / "wrong-key"
        wrong_key_dir.mkdir()
        wrong_seed, _, _ = ephemeral_keypair(wrong_key_dir)
        wrong_key = subprocess.run(
            ["python3", str(MODULE_PATH), "--app", str(app), "--appcast", str(feed),
             "--archive", str(archive), "--tag", tag, "--sign-update", str(sign_update)],
            input=wrong_seed + "\n", text=True, capture_output=True, timeout=30,
        )
        self.assertNotEqual(wrong_key.returncode, 0, "Appcast verifier accepted a signature from a different key")

        # The generator must not issue an item signature if the embedded app
        # public key belongs to a different keypair than its signing key.
        wrong_key_dir = self.root / "wrong-embedded-key"
        wrong_key_dir.mkdir()
        _, wrong_public_key, _ = ephemeral_keypair(wrong_key_dir)
        mismatched_app = self.root / "MismatchedAyre.app"
        subprocess.run(["ditto", str(app), str(mismatched_app)], check=True)
        mismatched_info_path = mismatched_app / "Contents/Info.plist"
        with mismatched_info_path.open("rb") as file:
            mismatched_info = plistlib.load(file)
        mismatched_info["SUPublicEDKey"] = wrong_public_key
        with mismatched_info_path.open("wb") as file:
            plistlib.dump(mismatched_info, file)
        mismatched_updates = self.root / "mismatched-updates"
        mismatched_updates.mkdir()
        mismatched_archive = mismatched_updates / archive.name
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(mismatched_app), str(mismatched_archive)], check=True)
        mismatched_feed = mismatched_updates / "appcast.xml"
        mismatch_generation = subprocess.run(
            [str(generate_appcast), "--ed-key-file", str(key_file),
             "--download-url-prefix", f"https://github.com/toyamarinyon/ayre/releases/download/{tag}/",
             "-o", str(mismatched_feed), str(mismatched_updates)],
            text=True, capture_output=True, timeout=120, env=tool_env,
        )
        if mismatch_generation.returncode == 0:
            mismatch_verification = subprocess.run(
                ["python3", str(MODULE_PATH), "--app", str(mismatched_app), "--appcast", str(mismatched_feed),
                 "--archive", str(mismatched_archive), "--tag", tag, "--sign-update", str(sign_update)],
                input=seed + "\n", text=True, capture_output=True, timeout=30,
            )
            self.assertNotEqual(mismatch_verification.returncode, 0,
                                "Generated feed accepted an app whose embedded public key differs from the signing key")


if __name__ == "__main__":
    unittest.main()
