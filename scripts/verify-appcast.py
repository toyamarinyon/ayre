#!/usr/bin/env python3
"""Check a generated Ayre Sparkle feed against its signed release archive."""
from __future__ import annotations
import argparse
import base64
import pathlib
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
APPCAST_URL = "https://github.com/toyamarinyon/ayre/releases/latest/download/appcast.xml"


def numeric_version(value: str) -> tuple[int, ...]:
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError(f"invalid numeric bundle version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def feed_versions(path: pathlib.Path) -> list[tuple[int, ...]]:
    root = ET.parse(path).getroot()
    return [numeric_version((item.findtext(f"{{{SPARKLE}}}version") or "").strip())
            for item in root.findall("./channel/item")]


def verify(app: pathlib.Path, appcast: pathlib.Path, archive: pathlib.Path, tag: str,
           previous_feeds: list[pathlib.Path], sign_update: pathlib.Path | None = None) -> None:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("release tag must be a stable vMAJOR.MINOR.PATCH tag")
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    app_short_version = info["CFBundleShortVersionString"]
    build_version = info["CFBundleVersion"]
    expected_build = numeric_version(build_version)
    if tag != f"v{app_short_version}":
        raise ValueError(f"tag {tag!r} does not match app version {app_short_version!r}")
    if info.get("SUFeedURL") != APPCAST_URL:
        raise ValueError(f"app SUFeedURL must be {APPCAST_URL}")
    if not info.get("SUPublicEDKey"):
        raise ValueError("app has no Sparkle EdDSA public key")

    root = ET.parse(appcast).getroot()
    items = root.findall("./channel/item")
    if not items:
        raise ValueError("appcast contains no update items")
    matching = []
    expected_url = f"https://github.com/toyamarinyon/ayre/releases/download/{tag}/{archive.name}"
    for item in items:
        channel = item.find(f"{{{SPARKLE}}}channel")
        if channel is not None and (channel.text or "").strip():
            raise ValueError("public stable appcast must not include a prerelease channel")
        version = numeric_version((item.findtext(f"{{{SPARKLE}}}version") or "").strip())
        if version == expected_build:
            matching.append(item)
    if len(matching) != 1:
        raise ValueError(f"expected exactly one appcast item for CFBundleVersion {build_version}")
    item = matching[0]
    appcast_short_version = (item.findtext(f"{{{SPARKLE}}}shortVersionString") or "").strip()
    if appcast_short_version != app_short_version:
        raise ValueError(f"appcast short version {appcast_short_version!r} does not match app version {app_short_version!r}")
    minimum_system = (item.findtext(f"{{{SPARKLE}}}minimumSystemVersion") or "").strip()
    expected_minimum = str(info.get("LSMinimumSystemVersion", ""))
    if not expected_minimum or numeric_version(minimum_system) != numeric_version(expected_minimum):
        raise ValueError(f"appcast minimum system version {minimum_system!r} does not match app minimum {expected_minimum!r}")
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != expected_url:
        raise ValueError(f"release enclosure must point to {expected_url}")
    signature = enclosure.get(f"{{{SPARKLE}}}edSignature", "")
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except (ValueError, base64.binascii.Error) as error:
        raise ValueError("appcast enclosure has no valid EdDSA signature") from error
    if len(signature_bytes) != 64:
        raise ValueError("appcast EdDSA signature must decode to 64 bytes")
    if int(enclosure.get("length", "0")) != archive.stat().st_size:
        raise ValueError("appcast enclosure length does not match final archive")
    if sign_update is not None:
        private_key = sys.stdin.readline().rstrip("\r\n")
        if not private_key:
            raise ValueError("SPARKLE_PRIVATE_KEY is required to verify the archive signature")
        checked = subprocess.run(
            [str(sign_update), "--verify", "--ed-key-file", "-", str(archive), signature],
            input=private_key + "\n", text=True, capture_output=True,
        )
        if checked.returncode != 0:
            raise ValueError("Sparkle sign_update rejected the final archive signature")

    for previous in previous_feeds:
        for prior_version in feed_versions(previous):
            if expected_build <= prior_version:
                raise ValueError(f"CFBundleVersion {build_version} is not greater than published version {'.'.join(map(str, prior_version))}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--appcast", required=True, type=pathlib.Path)
    parser.add_argument("--archive", required=True, type=pathlib.Path)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--previous-feed", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--sign-update", type=pathlib.Path, help="Use Sparkle sign_update to cryptographically verify the archive")
    args = parser.parse_args()
    verify(args.app, args.appcast, args.archive, args.tag, args.previous_feed, args.sign_update)
    print(f"PASS: stable appcast for {args.tag}, archive signature metadata, and monotonic CFBundleVersion")


if __name__ == "__main__":
    main()
